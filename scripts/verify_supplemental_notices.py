#!/usr/bin/env python3
"""Verify reviewed supplemental notices and their exact bytes in the final APK."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile

from verify_third_party_notices import inventory_coordinates


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def verify(root: Path, apk: Path | None = None, inventory: Path | None = None) -> dict:
    review = json.loads((root / "third_party/metadata/distribution-notices.json").read_bytes())
    if review.get("schema_version") != 1:
        raise ValueError("Unsupported supplemental notice review schema")
    name = review["supplemental_asset"]
    relative = PurePosixPath(name)
    if (relative.is_absolute() or ".." in relative.parts or "\\" in name or ":" in name
            or name != "client/assets/licenses/supplemental.json"):
        raise ValueError("Unsafe supplemental asset path")
    asset = (root / name).read_bytes()
    if digest(asset) != review["supplemental_asset_sha256"]:
        raise ValueError("Supplemental asset differs from its reviewed content")
    for name, key in (("go.mod", "go_mod_sha256"), ("client/pubspec.lock", "pubspec_lock_sha256")):
        if digest((root / name).read_bytes().replace(b"\r\n", b"\n")) != review[key]:
            raise ValueError("Dependency declarations changed; refresh the notice review")
    document = json.loads(asset)
    if document.get("schema_version") != 1 or not document.get("entries"):
        raise ValueError("Supplemental notice asset is incomplete")
    entries = document["entries"]
    evidence = review["entries"]
    if len(entries) != len(evidence):
        raise ValueError("Supplemental entry count differs from its review")
    packages = set()
    for entry, expected in zip(entries, evidence):
        names, text = entry.get("packages"), entry.get("text")
        if (not isinstance(names, list) or not names
                or any(not isinstance(n, str) or not n.strip() for n in names)
                or not isinstance(text, str) or not text.strip()):
            raise ValueError("Supplemental entry has no names or text")
        if names != expected["packages"] or digest(text.encode()) != expected["text_sha256"]:
            raise ValueError("Supplemental entry differs from its reviewed text")
        packages.update(names)
    coordinates = set(review["runtime_coordinates"])
    if inventory and inventory_coordinates(json.loads(inventory.read_bytes())) != coordinates:
        raise ValueError("Runtime module versions differ from the notice review")
    engine_names = {"arm64_v8a_release", "armeabi_v7a_release", "x86_64_release", "flutter_embedding_release"}
    native = {c for c in coordinates if not (c.split(":")[0] == "io.flutter" and c.split(":")[1] in engine_names)}
    if not native.issubset(packages):
        raise ValueError("A native runtime module has no supplemental notice")
    all_text = "\n\n".join(entry["text"] for entry in entries).replace("\r\n", "\n")
    for item in review.get("required_texts", []):
        name = item["file"]
        path = PurePosixPath(name)
        if (path.is_absolute() or ".." in path.parts or "\\" in name or ":" in name
                or not name.startswith("third_party/licenses/")):
            raise ValueError("Unsafe required notice path")
        data = (root / name).read_bytes()
        if digest(data) != item["sha256"] or data.decode().replace("\r\n", "\n").strip() not in all_text:
            raise ValueError("A required original license or NOTICE text is missing or changed")
    for literal in review.get("required_acknowledgements", []):
        if literal not in all_text:
            raise ValueError("A required affirmative acknowledgement is missing")
    for item in review.get("reviewed_source_files", []):
        name = item["file"]
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or "\\" in name or ":" in name:
            raise ValueError("Unsafe reviewed source path")
        if digest((root / name).read_bytes()) != item["sha256"]:
            raise ValueError("A reviewed icon or wrapper changed; refresh its provenance review")
    if apk:
        with zipfile.ZipFile(apk) as archive:
            actual = archive.read("assets/flutter_assets/assets/licenses/supplemental.json")
        if actual != asset:
            raise ValueError("APK supplemental notices differ from the reviewed source asset")
    return {"entries": len(entries), "native_modules": len(native), "apk_asset_matches": apk is not None}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--android-inventory", type=Path)
    args = parser.parse_args()
    try:
        result = verify(args.root, args.apk, args.android_inventory)
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as error:
        raise SystemExit(f"Supplemental notice validation failed: {error}") from error
    print(f"Verified {result['entries']} reviewed entries covering {result['native_modules']} native modules")
    if args.apk:
        print("APK includes the exact reviewed supplemental notice asset")


if __name__ == "__main__":
    main()
