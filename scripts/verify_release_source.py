#!/usr/bin/env python3
"""Validate the source snapshot before signing, and detect later source changes."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re


GENERATED_TREES = (
    "client/build/", "client/.dart_tool/", "client/android/build/",
    "client/android/app/build/", "client/android/.gradle/", "client/android/.kotlin/",
    "client/android/app/.cxx/",
    "scripts/__pycache__/",
)
GENERATED_FILES = {
    "client/.flutter-plugins-dependencies", "client/android/local.properties",
    "client/android/key.properties",
    "client/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java",
    "artifacts/android-runtime-dependencies.json",
}


def verify(root: Path, tag: str, commit: str, allow_generated_files: bool = False,
           expected_metadata: dict | None = None) -> dict:
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?", tag):
        raise ValueError("Release tag must be vMAJOR.MINOR.PATCH[-suffix]")
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", commit):
        raise ValueError("Source commit must be a full Git object ID")
    manifest_path = root / "SOURCE_MANIFEST.json"
    manifest_bytes = manifest_path.read_bytes()
    entries = json.loads(manifest_bytes)
    if not isinstance(entries, list) or not entries:
        raise ValueError("Source manifest must be a nonempty list")
    expected = {"SOURCE_MANIFEST.json"}
    for entry in entries:
        name = entry["path"]
        path = PurePosixPath(name)
        if (path.is_absolute() or ".." in path.parts or "\\" in name
                or ":" in name or path.as_posix() != name or name in expected):
            raise ValueError("Source manifest has an unsafe or duplicate path")
        target = root / name
        if target.is_symlink() or any(parent.is_symlink() for parent in target.parents if parent != root):
            raise ValueError(f"Snapshot contains a symlink: {name}")
        data = target.read_bytes()
        if len(data) != entry["size"] or hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise ValueError(f"Source file differs from the manifest: {name}")
        expected.add(name)
    required = {"LICENSE", "client/LICENSE", "client/pubspec.yaml", "client/pubspec.lock"}
    if not required.issubset(expected):
        raise ValueError("Source manifest lacks release inputs")
    for file in root.rglob("*"):
        name = file.relative_to(root).as_posix()
        generated = name in GENERATED_FILES or name.startswith(GENERATED_TREES)
        if file.is_symlink() or (file.is_file() and name not in expected
                                 and not (allow_generated_files and generated)):
            raise ValueError(f"Snapshot contains files outside the manifest: {name}")
    license_bytes = (root / "LICENSE").read_bytes()
    if license_bytes != (root / "client/LICENSE").read_bytes():
        raise ValueError("Root and client licenses must be identical")
    pubspec = (root / "client/pubspec.yaml").read_text(encoding="utf-8")
    versions = re.findall(r"(?m)^version:\s*([^\s#]+)[ \t]*(?:#.*)?$", pubspec)
    if len(versions) != 1:
        raise ValueError("pubspec.yaml must specify exactly one version")
    version = versions[0].strip("\"'")
    match = re.fullmatch(r"(\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?)\+(\d+)", version)
    if match is None or tag != "v" + match.group(1) or int(match.group(2)) < 1:
        raise ValueError("Release tag must match the pubspec version; a positive Android build number is required")
    metadata = {
        "schema_version": 1,
        "source_commit": commit,
        "release_tag": tag,
        "client_version": version,
        "android_build_number": int(match.group(2)),
        "license_sha256": hashlib.sha256(license_bytes).hexdigest(),
        "source_manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
    }
    if expected_metadata is not None and metadata != expected_metadata:
        raise ValueError("Release source metadata differs from the pre-build source archive")
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--expected-metadata", type=Path,
                        help="Require an exact match to the metadata saved before source archiving")
    parser.add_argument("--allow-generated-files", action="store_true",
                        help="Allow build output and private signing inputs; still verify every manifest file")
    args = parser.parse_args()
    try:
        expected = (json.loads(args.expected_metadata.read_text(encoding="utf-8"))
                    if args.expected_metadata else None)
        if args.expected_metadata and not isinstance(expected, dict):
            raise ValueError("Expected release metadata must be a JSON object")
        metadata = verify(args.root.resolve(strict=True), args.tag, args.commit,
                          args.allow_generated_files, expected)
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise SystemExit(f"Release source validation failed: {error}") from error
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print("Release version, licenses and source manifest verified")


if __name__ == "__main__":
    main()
