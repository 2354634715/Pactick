#!/usr/bin/env python3
"""Verify project, Flutter engine and reviewed supplemental notices in an APK."""
import argparse
import gzip
import hashlib
from pathlib import Path
import shutil
import zipfile

from verify_supplemental_notices import verify as verify_supplemental


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--engine-license", type=Path, help="Defaults to sky_engine/LICENSE in the Flutter SDK on PATH")
    parser.add_argument("--project-license", type=Path)
    args = parser.parse_args()
    project_license = args.project_license or args.root / "LICENSE"
    engine = args.engine_license
    if engine is None:
        executable = shutil.which("flutter") or shutil.which("flutter.bat")
        if executable is None:
            parser.error("Flutter SDK is not on PATH; specify --engine-license")
        engine = Path(executable).resolve().parents[1] / "bin/cache/pkg/sky_engine/LICENSE"
    with zipfile.ZipFile(args.apk) as archive:
        compressed = archive.read("assets/flutter_assets/NOTICES.Z")
    notices = gzip.decompress(compressed).decode("utf-8")
    if project_license.read_text(encoding="utf-8").strip() not in notices.replace("\r\n", "\n"):
        raise SystemExit("APK is missing the complete project license text")
    print("APK includes the complete project license text")
    parts = engine.read_text(encoding="utf-8").split("\n" + "-" * 80 + "\n")
    bodies = [part.split("\n\n", 1)[1] if "\n\n" in part else part for part in parts]
    missing = [index for index, body in enumerate(bodies, 1) if body not in notices]
    if missing:
        raise SystemExit(f"APK is missing {len(missing)} of {len(bodies)} Flutter engine license sections")
    print(f"APK includes all {len(bodies)} Flutter engine license sections in NOTICES.Z")
    print("NOTICES.Z SHA-256:", hashlib.sha256(compressed).hexdigest())
    supplemental = verify_supplemental(args.root.resolve(), args.apk)
    print(f"APK includes all {supplemental['entries']} supplemental notice entries")
    print("This checks bundled text; also verify the app's About / View licenses entry on a device.")


if __name__ == "__main__":
    main()
