#!/usr/bin/env python3
"""Verify project, Flutter engine and reviewed supplemental notices in an APK."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import zipfile

from verify_supplemental_notices import verify as verify_supplemental


DISPLAY_FONT_SOURCE = "client/assets/fonts/NotoSerifSC.ttf"
DISPLAY_FONT_ASSET = "assets/fonts/NotoSerifSC.ttf"
# Keep this aligned with the reviewed binary allowlist in prepare_public_source.py.
DISPLAY_FONT_SHA256 = "050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"


def verify_display_font(root: Path, archive: zipfile.ZipFile) -> bool:
    """Check the reviewed font bytes and the Flutter family used to select them."""
    source = root / DISPLAY_FONT_SOURCE
    pubspec = root / "client/pubspec.yaml"
    declared = pubspec.is_file() and re.search(
        r"(?m)^\s*-\s*(?:family:\s*['\"]?PactickDisplay['\"]?"
        r"|asset:\s*['\"]?assets/fonts/NotoSerifSC\.ttf['\"]?)\s*(?:#.*)?$",
        pubspec.read_text(encoding="utf-8"),
    )
    if not source.is_file() and not declared:
        return False
    if not source.is_file():
        raise ValueError("Declared display font is missing from the source")
    review = json.loads((root / "third_party/metadata/distribution-notices.json").read_bytes())
    reviewed = [
        item for item in review.get("reviewed_source_files", [])
        if item.get("file") == DISPLAY_FONT_SOURCE
    ]
    if len(reviewed) != 1 or reviewed[0].get("sha256") != DISPLAY_FONT_SHA256:
        raise ValueError("Display font has no matching reviewed SHA-256")
    if hashlib.sha256(source.read_bytes()).hexdigest() != DISPLAY_FONT_SHA256:
        raise ValueError("Source display font differs from the reviewed binary")

    font_name = "assets/flutter_assets/" + DISPLAY_FONT_ASSET
    manifest_name = "assets/flutter_assets/FontManifest.json"
    names = archive.namelist()
    if names.count(font_name) != 1 or names.count(manifest_name) != 1:
        raise ValueError("APK must contain one display font and one FontManifest.json")
    if hashlib.sha256(archive.read(font_name)).hexdigest() != DISPLAY_FONT_SHA256:
        raise ValueError("APK display font differs from the reviewed binary")
    try:
        manifest = json.loads(archive.read(manifest_name))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("APK FontManifest.json is invalid") from error
    if not isinstance(manifest, list):
        raise ValueError("APK FontManifest.json must contain a font family list")
    families = [
        item for item in manifest
        if isinstance(item, dict) and item.get("family") == "PactickDisplay"
    ]
    fonts = families[0].get("fonts") if len(families) == 1 else None
    if (not isinstance(fonts, list) or len(fonts) != 1
            or not isinstance(fonts[0], dict)
            or fonts[0].get("asset") != DISPLAY_FONT_ASSET
            or fonts[0].get("weight") != 400
            or fonts[0].get("style", "normal") != "normal"):
        raise ValueError("APK PactickDisplay family does not map to the reviewed regular font")
    return True


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
        try:
            checked_display_font = verify_display_font(args.root.resolve(), archive)
        except (OSError, ValueError) as error:
            raise SystemExit(f"Display font verification failed: {error}") from error
    if checked_display_font:
        print("APK includes the reviewed Noto Serif SC font and PactickDisplay mapping")
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
