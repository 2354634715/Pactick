import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from verify_release_source import verify


class ReleaseSourceTests(unittest.TestCase):
    def fixture(self, root, version="0.2.0-preview.1+3", client_license="license\n"):
        files = {"LICENSE": "license\n", "client/LICENSE": client_license,
                 "client/pubspec.yaml": f"name: pactick\nversion: {version}\n",
                 "client/pubspec.lock": "packages: {}\n"}
        entries = []
        for name, contents in files.items():
            file = root / name
            file.parent.mkdir(parents=True, exist_ok=True)
            data = contents.encode()
            file.write_bytes(data)
            entries.append({"path": name, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)})
        (root / "SOURCE_MANIFEST.json").write_text(json.dumps(entries))

    def test_tag_and_build_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            metadata = verify(root, "v0.2.0-preview.1", "a" * 40)
            self.assertEqual(metadata["android_build_number"], 3)
            self.assertEqual(metadata["client_version"], "0.2.0-preview.1+3")
            with self.assertRaisesRegex(ValueError, "tag must match"):
                verify(root, "v0.2.0", "a" * 40)

    def test_license_mismatch_blocks_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, client_license="different terms\n")
            with self.assertRaisesRegex(ValueError, "licenses must be identical"):
                verify(root, "v0.2.0-preview.1", "a" * 40)

    def test_source_change_after_build_is_rejected_but_generated_output_is_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            generated = root / "client/build/app.apk"
            generated.parent.mkdir()
            generated.write_bytes(b"build output")
            with self.assertRaisesRegex(ValueError, "outside the manifest"):
                verify(root, "v0.2.0-preview.1", "a" * 40)
            verify(root, "v0.2.0-preview.1", "a" * 40, allow_generated_files=True)
            (root / "client/pubspec.lock").write_text("changed dependencies")
            with self.assertRaisesRegex(ValueError, "differs from the manifest"):
                verify(root, "v0.2.0-preview.1", "a" * 40, allow_generated_files=True)

    def test_manifest_rejects_traversal_and_duplicate_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            manifest_file = root / "SOURCE_MANIFEST.json"
            entries = json.loads(manifest_file.read_text())
            for invalid in (entries + [entries[0]], [{**entries[0], "path": "../LICENSE"}]):
                manifest_file.write_text(json.dumps(invalid))
                with self.assertRaisesRegex(ValueError, "unsafe or duplicate"):
                    verify(root, "v0.2.0-preview.1", "a" * 40)

    def test_build_cannot_add_unarchived_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            for name in ("client/lib/added.dart", "client/android/app/src/main/kotlin/Added.kt",
                         "client/android/app/src/main/java/Added.java"):
                file = root / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text("unarchived source")
                with self.assertRaisesRegex(ValueError, "outside the manifest"):
                    verify(root, "v0.2.0-preview.1", "a" * 40, allow_generated_files=True)
                file.unlink()

    def test_rewritten_source_and_manifest_cannot_replace_the_archived_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            metadata = verify(root, "v0.2.0-preview.1", "a" * 40)
            verify(root, "v0.2.0-preview.1", "a" * 40, expected_metadata=metadata)
            manifest_file = root / "SOURCE_MANIFEST.json"
            entries = json.loads(manifest_file.read_text())
            changed = root / "client/pubspec.lock"
            data = b"packages: {changed: dependency}\n"
            changed.write_bytes(data)
            for entry in entries:
                if entry["path"] == "client/pubspec.lock":
                    entry.update(size=len(data), sha256=hashlib.sha256(data).hexdigest())
            manifest_file.write_text(json.dumps(entries))
            with self.assertRaisesRegex(ValueError, "pre-build source archive"):
                verify(root, "v0.2.0-preview.1", "a" * 40,
                       allow_generated_files=True, expected_metadata=metadata)

    def test_cli_cannot_skip_expected_metadata_with_json_null(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            root.mkdir()
            self.fixture(root)
            baseline = Path(directory) / "metadata.json"
            baseline.write_text("null")
            result = subprocess.run(
                [sys.executable, str(Path(__file__).with_name("verify_release_source.py")), str(root),
                 "--tag", "v0.2.0-preview.1", "--commit", "a" * 40,
                 "--expected-metadata", str(baseline)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"must be a JSON object", result.stderr)


if __name__ == "__main__":
    unittest.main()
