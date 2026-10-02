import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from generate_third_party_notices import license_kind
from verify_supplemental_notices import digest, verify


class SupplementalNoticeTests(unittest.TestCase):
    def fixture(self, root):
        def write(name, data):
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            return path

        write("go.mod", b"module example\n")
        write("client/pubspec.lock", b"packages: {}\n")
        text = "Original NOTICE\nAcknowledgement\n"
        original = write("third_party/licenses/original.txt", b"Original NOTICE\n")
        asset = write("client/assets/licenses/supplemental.json", json.dumps({
            "schema_version": 1, "entries": [{"packages": ["example:native:1"], "text": text}]
        }).encode())
        review = {
            "schema_version": 1,
            "supplemental_asset": "client/assets/licenses/supplemental.json",
            "supplemental_asset_sha256": digest(asset.read_bytes()),
            "go_mod_sha256": digest((root / "go.mod").read_bytes()),
            "pubspec_lock_sha256": digest((root / "client/pubspec.lock").read_bytes()),
            "runtime_coordinates": ["example:native:1"],
            "entries": [{"packages": ["example:native:1"], "text_sha256": digest(text.encode())}],
            "required_texts": [{"file": "third_party/licenses/original.txt", "sha256": digest(original.read_bytes())}],
            "required_acknowledgements": ["Acknowledgement"],
        }
        self.save(root, review)
        apk = root / "app.apk"
        with zipfile.ZipFile(apk, "w") as archive:
            archive.writestr("assets/flutter_assets/assets/licenses/supplemental.json", asset.read_bytes())
        inventory = write("inventory.json", json.dumps({
            "schemaVersion": 2, "complete": True, "configuration": "releaseRuntimeClasspath",
            "modules": [{"group": "example", "name": "native", "version": "1"}],
            "artifactFiles": [{"coordinate": "example:native:1", "file": "native.aar"}],
        }).encode())
        return review, apk, inventory

    def save(self, root, review):
        path = root / "third_party/metadata/distribution-notices.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(json.dumps(review).encode())

    def test_exact_apk_asset_and_current_graph_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _, apk, inventory = self.fixture(root)
            self.assertEqual(verify(root, apk, inventory), {
                "entries": 1, "native_modules": 1, "apk_asset_matches": True,
            })

    def test_changed_apk_or_missing_asset_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _, apk, _ = self.fixture(root)
            with zipfile.ZipFile(apk, "w") as archive:
                archive.writestr("assets/flutter_assets/assets/licenses/supplemental.json", b"changed")
            with self.assertRaisesRegex(ValueError, "APK supplemental notices differ"):
                verify(root, apk)
            with zipfile.ZipFile(apk, "w"):
                pass
            with self.assertRaises(KeyError):
                verify(root, apk)

    def test_changed_dependencies_or_runtime_version_requires_review(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _, _, inventory = self.fixture(root)
            (root / "go.mod").write_bytes(b"module changed\n")
            with self.assertRaisesRegex(ValueError, "Dependency declarations changed"):
                verify(root)
            (root / "go.mod").write_bytes(b"module example\r\n")
            document = json.loads(inventory.read_bytes())
            document["modules"][0]["version"] = "2"
            document["artifactFiles"][0]["coordinate"] = "example:native:2"
            inventory.write_bytes(json.dumps(document).encode())
            with self.assertRaisesRegex(ValueError, "Runtime module versions differ"):
                verify(root, inventory=inventory)

    def test_omitted_native_module_and_missing_original_notice_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            review, _, _ = self.fixture(root)
            review["runtime_coordinates"].append("example:omitted:1")
            self.save(root, review)
            with self.assertRaisesRegex(ValueError, "native runtime module"):
                verify(root)
            review["runtime_coordinates"].pop()
            review["required_acknowledgements"] = ["Omitted acknowledgement"]
            self.save(root, review)
            with self.assertRaisesRegex(ValueError, "affirmative acknowledgement"):
                verify(root)
            review["required_acknowledgements"] = ["Acknowledgement"]
            self.save(root, review)
            (root / "third_party/licenses/original.txt").write_bytes(b"Other NOTICE\n")
            with self.assertRaisesRegex(ValueError, "original license or NOTICE"):
                verify(root)

    def test_changed_source_asset_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            (root / "client/assets/licenses/supplemental.json").write_bytes(b"{}")
            with self.assertRaisesRegex(ValueError, "reviewed content"):
                verify(root)

    def test_classification_preserves_special_and_mixed_terms(self):
        self.assertTrue(license_kind("Attribution 4.0 International").startswith("CC-BY-4.0"))
        self.assertTrue(license_kind(
            "Apache License Version 2.0. Permission is hereby granted, free of charge"
        ).startswith("Multiple licenses"))


if __name__ == "__main__":
    unittest.main()
