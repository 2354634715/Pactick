#!/usr/bin/env python3
"""Verify dependency versions and local notice evidence; legal review remains manual."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re


def go_dependencies(root: Path) -> dict[str, str]:
    dependencies = {}
    block = False
    for raw in (root / "go.mod").read_text(encoding="utf-8").splitlines():
        line = raw.split("//", 1)[0].strip()
        if not line:
            continue
        if re.match(r"^(replace|exclude)\b", line):
            raise ValueError("Go replace/exclude directives require supported provenance collection before verification")
        if re.fullmatch(r"require\s+\(", line):
            block = True
            continue
        if block and line == ")":
            block = False
            continue
        directive = re.match(r"require\s+", line)
        if not block and directive is None:
            continue
        requirement = line if block else line[directive.end():]
        match = re.fullmatch(r"(\S+)\s+(v\S+)", requirement)
        if match is None or match[1] in dependencies:
            raise ValueError("Go requirements contain an unsupported or duplicate declaration")
        dependencies[match[1]] = match[2]
    if block:
        raise ValueError("Go require block is incomplete")
    return dependencies


def dart_dependencies(root: Path) -> dict[str, str]:
    lock = (root / "client/pubspec.lock").read_text(encoding="utf-8")
    packages = re.findall(r"^  ([a-zA-Z0-9_]+):\n((?:    .*(?:\n|$))+)", lock, re.M)
    dependencies = {}
    for name, block in packages:
        source = re.search(r"^    source: (\S+)\s*$", block, re.M)
        version = re.search(r"^    version: [\"']?([^\s\"']+)[\"']?\s*$", block, re.M)
        if source is None or version is None:
            raise ValueError(f"Dart lock entry is incomplete: {name}")
        if source[1] == "sdk":
            continue
        if source[1] != "hosted":
            raise ValueError(f"Dart {source[1]} dependency requires supported provenance collection: {name}")
        url = re.search(r"^      url: [\"']?([^\s\"']+)[\"']?\s*$", block, re.M)
        if url is None or url[1].rstrip("/") != "https://pub.dev":
            raise ValueError(f"Dart hosted dependency requires verified pub.dev provenance: {name}")
        if name in dependencies:
            raise ValueError(f"Duplicate Dart dependency: {name}")
        dependencies[name] = version[1]
    if not packages and not re.search(r"(?m)^packages:\s*\{\}\s*$", lock):
        raise ValueError("Dart lock file has no supported packages mapping")
    return dependencies


def inventory_coordinates(inventory: dict) -> set[str]:
    if (not isinstance(inventory, dict) or inventory.get("schemaVersion") != 2
            or inventory.get("complete") is not True
            or inventory.get("configuration") != "releaseRuntimeClasspath"
            or not inventory.get("artifactFiles")):
        raise ValueError("A complete schema 2 release runtime inventory with artifacts is required")
    coordinates = [f"{item['group']}:{item['name']}:{item['version']}" for item in inventory["modules"]]
    if not coordinates or len(coordinates) != len(set(coordinates)):
        raise ValueError("Android runtime inventory has empty or duplicate modules")
    if any(artifact["coordinate"] not in coordinates for artifact in inventory["artifactFiles"]):
        raise ValueError("Resolved artifact is absent from the Android runtime graph")
    return set(coordinates)


def verify(root: Path, android_inventory: Path | None = None) -> dict:
    root = root.resolve(strict=True)
    report = json.loads((root / "THIRD_PARTY_NOTICES.json").read_text(encoding="utf-8"))
    components = report["components"]
    if not isinstance(components, list) or not components:
        raise ValueError("Third-party components must be a nonempty list")
    seen = set()

    def verify_evidence(entry: dict) -> None:
        name = entry["file"]
        path = PurePosixPath(name)
        if (path.is_absolute() or ".." in path.parts or "\\" in name or ":" in name
                or path.as_posix() != name
                or not name.startswith(("third_party/licenses/", "third_party/metadata/"))):
            raise ValueError("License evidence has an unsafe path")
        target = root / name
        if any(parent.is_symlink() for parent in (target, *target.parents) if parent != root):
            raise ValueError(f"License evidence contains a symlink: {name}")
        data = target.read_bytes()
        if not data.strip() or hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise ValueError(f"License evidence is empty or differs from its declared hash: {name}")

    for component in components:
        identity = component["ecosystem"], component["name"]
        if identity in seen:
            raise ValueError("Duplicate third-party component")
        seen.add(identity)
        if component.get("status") != "local-license-text-collected" or not component.get("licenses"):
            raise ValueError(f"Missing license text for component: {component['name']}")
        for entry in component["licenses"]:
            verify_evidence(entry)
    for ecosystem, expected in (("Go", go_dependencies(root)), ("Dart", dart_dependencies(root))):
        declared = {item["name"]: item["version"] for item in components if item["ecosystem"] == ecosystem}
        if declared != expected:
            raise ValueError(f"{ecosystem} notices differ from the current locked dependency versions; regenerate the notices")
    required = {("SDK", "Go-runtime-and-standard-library"), ("SDK", "Flutter"), ("SDK", "Dart"),
                ("SDK", "Flutter-engine-and-native-libraries"), ("Asset", "Material-icons-fonts"),
                ("Build", "Gradle-wrapper")}
    if not required.issubset(seen):
        raise ValueError("Required SDK, runtime, font or Gradle-wrapper license evidence is missing")
    android = report["android_metadata"]
    if report.get("android_runtime_graph_complete") is not True or not android:
        raise ValueError("Android metadata must come from a complete runtime graph")
    coordinates = set()
    for item in android:
        coordinate = item["coordinate"]
        if coordinate in coordinates or item.get("status") != "resolved-runtime-POM-metadata":
            raise ValueError("Android metadata contains duplicate, missing or unconfirmed POM records")
        coordinates.add(coordinate)
        if not re.fullmatch(r"[0-9a-f]{64}", item.get("pom_sha256", "")):
            raise ValueError("Android POM hash is missing or invalid")
        if not item.get("licenses") and not item.get("license_evidence"):
            raise ValueError(f"Android component lacks a license declaration or upstream evidence: {coordinate}")
        for entry in [*item.get("license_evidence", []), *item.get("embedded_notices", [])]:
            verify_evidence(entry)
    if android_inventory:
        inventory = json.loads(android_inventory.read_text(encoding="utf-8"))
        if inventory_coordinates(inventory) != coordinates:
            raise ValueError("Android notices differ from the current release runtime graph; regenerate the notices")
    return {"components": len(components), "android_modules": len(android)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--android-inventory", type=Path, help="Also compare the current complete release runtime graph")
    args = parser.parse_args()
    try:
        counts = verify(args.root, args.android_inventory)
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise SystemExit(f"Third-party notice verification failed: {error}") from error
    print(f"Verified {counts['components']} component records and {counts['android_modules']} Android metadata records")
    print("This verifies version declarations and local text evidence; distribution notices and legal compatibility require manual review")


if __name__ == "__main__":
    main()
