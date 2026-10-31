import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from verify_apk_notices import (
    DISPLAY_FONT_ASSET,
    DISPLAY_FONT_SHA256,
    DISPLAY_FONT_SOURCE,
    verify_display_font,
)


class DisplayFontTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.font = (Path(__file__).resolve().parents[1] / DISPLAY_FONT_SOURCE).read_bytes()

    def fixture(self, root):
        font = root / DISPLAY_FONT_SOURCE
        font.parent.mkdir(parents=True, exist_ok=True)
        font.write_bytes(self.font)
        (root / "client/pubspec.yaml").write_text(
            "flutter:\n  fonts:\n    - family: PactickDisplay\n      fonts:\n"
            "        - asset: assets/fonts/NotoSerifSC.ttf\n          weight: 400\n",
            encoding="utf-8",
        )
        review = root / "third_party/metadata/distribution-notices.json"
        review.parent.mkdir(parents=True)
        review.write_text(json.dumps({"reviewed_source_files": [{
            "file": DISPLAY_FONT_SOURCE, "sha256": DISPLAY_FONT_SHA256,
        }]}), encoding="utf-8")

    def apk(self, font=None, manifest=None, omit=()):
        contents = io.BytesIO()
        with zipfile.ZipFile(contents, "w") as archive:
            if "font" not in omit:
                archive.writestr("assets/flutter_assets/" + DISPLAY_FONT_ASSET,
                                 self.font if font is None else font)
            if "manifest" not in omit:
                archive.writestr("assets/flutter_assets/FontManifest.json", json.dumps(
                    [{"family": "PactickDisplay", "fonts": [{
                        "asset": DISPLAY_FONT_ASSET, "weight": 400,
                    }]}] if manifest is None else manifest,
                ))
        return zipfile.ZipFile(contents)

    def test_reviewed_font_and_manifest_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            with self.apk() as archive:
                self.assertTrue(verify_display_font(root, archive))

    def test_fixture_without_font_declaration_or_source_is_compatible(self):
        with tempfile.TemporaryDirectory() as directory, self.apk(omit=("font", "manifest")) as archive:
            self.assertFalse(verify_display_font(Path(directory), archive))

    def test_declared_font_cannot_be_silently_omitted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            (root / DISPLAY_FONT_SOURCE).unlink()
            with self.apk() as archive, self.assertRaisesRegex(ValueError, "missing from the source"):
                verify_display_font(root, archive)

    def test_crlf_conversion_of_packaged_font_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            changed = self.font.replace(b"\r\n", b"\n")
            self.assertNotEqual(changed, self.font)
            with self.apk(font=changed) as archive, self.assertRaisesRegex(ValueError, "APK display font differs"):
                verify_display_font(root, archive)

    def test_changed_source_or_relabelled_font_review_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            (root / DISPLAY_FONT_SOURCE).write_bytes(b"another font")
            with self.apk() as archive, self.assertRaisesRegex(ValueError, "Source display font differs"):
                verify_display_font(root, archive)
            (root / "third_party/metadata/distribution-notices.json").write_text(
                json.dumps({"reviewed_source_files": [{
                    "file": DISPLAY_FONT_SOURCE, "sha256": "0" * 64,
                }]}), encoding="utf-8",
            )
            with self.apk() as archive, self.assertRaisesRegex(ValueError, "matching reviewed SHA-256"):
                verify_display_font(root, archive)

    def test_font_and_manifest_are_both_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            for missing in ("font", "manifest"):
                with self.subTest(missing=missing), self.apk(omit=(missing,)) as archive:
                    with self.assertRaisesRegex(ValueError, "one display font and one FontManifest"):
                        verify_display_font(root, archive)

    def test_wrong_family_asset_or_weight_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            manifests = [
                [],
                [{"family": "AnotherFamily", "fonts": [{"asset": DISPLAY_FONT_ASSET, "weight": 400}]}],
                [{"family": "PactickDisplay", "fonts": [{"asset": "assets/fonts/other.ttf", "weight": 400}]}],
                [{"family": "PactickDisplay", "fonts": [{"asset": DISPLAY_FONT_ASSET, "weight": 700}]}],
            ]
            for manifest in manifests:
                with self.subTest(manifest=manifest), self.apk(manifest=manifest) as archive:
                    with self.assertRaisesRegex(ValueError, "PactickDisplay family"):
                        verify_display_font(root, archive)


if __name__ == "__main__":
    unittest.main()
