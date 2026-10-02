#!/usr/bin/env python3
"""Capture final resolved Android binaries and their embedded notice evidence."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import zipfile


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def capture(inventory_path: Path, apk: Path, output: Path) -> dict:
    inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
    if (inventory.get("schemaVersion") != 2 or inventory.get("complete") is not True
            or inventory.get("configuration") != "releaseRuntimeClasspath"
            or not inventory.get("artifactFiles")):
        raise ValueError("A complete schema 2 release runtime inventory with resolved artifacts is required")
    modules = inventory["modules"]
    coordinates = {f"{item['group']}:{item['name']}:{item['version']}" for item in modules}
    output.mkdir(parents=True, exist_ok=False)
    records = []
    for index, artifact in enumerate(inventory["artifactFiles"]):
        coordinate = artifact["coordinate"]
        if coordinate not in coordinates:
            raise ValueError("Resolved binary coordinate is absent from the runtime graph")
        binary = Path(artifact["file"])
        data = binary.read_bytes()
        notices = []
        slug = re.sub(r"[^A-Za-z0-9._-]", "_", coordinate)

        def read_archive(archive_data: bytes, prefix: str = "", read_nested: bool = True) -> None:
            with zipfile.ZipFile(io.BytesIO(archive_data)) as archive:
                for member in archive.infolist():
                    if member.is_dir():
                        continue
                    name = member.filename
                    is_notice = re.search(r"(?:^|/)(?:license|licence|copying|notice|copyright)[^/]*$", name, re.I)
                    is_nested = read_nested and name.lower().endswith(".jar")
                    if not is_notice and not is_nested:
                        continue
                    if member.file_size > 64 * 1024 * 1024:
                        raise ValueError("Embedded notice or JAR exceeds the evidence capture size limit")
                    contents = archive.read(member)
                    if is_notice:
                        target_name = f"{index:03d}-{slug}-{len(notices):03d}.txt"
                        (output / target_name).write_bytes(contents)
                        notices.append({"archive_entry": prefix + name, "file": target_name,
                                        "sha256": digest(contents)})
                    if is_nested:
                        read_archive(contents, prefix + name + "!/", read_nested=False)

        if binary.suffix.lower() in {".aar", ".jar"}:
            read_archive(data)
        records.append({"coordinate": coordinate, "filename": binary.name,
                        "sha256": digest(data), "embedded_notices": notices,
                        "status": "embedded-text-collected" if notices else "no-embedded-text-found-review-upstream"})
    result = {"schema_version": 1, "apk_sha256": digest(apk.read_bytes()),
              "configuration": inventory["configuration"], "modules": modules,
              "artifacts": records, "completed_legal_audit": False,
              "review_required": "Review native component obligations and verify notices in the final distribution"}
    (output / "ANDROID_NATIVE_EVIDENCE.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inventory", type=Path)
    parser.add_argument("apk", type=Path)
    parser.add_argument("output", type=Path, help="New directory for evidence, outside the source archive")
    args = parser.parse_args()
    try:
        result = capture(args.inventory, args.apk, args.output)
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as error:
        raise SystemExit(f"Android native evidence capture failed: {error}") from error
    print(f"Captured {len(result['artifacts'])} resolved Android binaries; native license review remains required")


if __name__ == "__main__":
    main()
