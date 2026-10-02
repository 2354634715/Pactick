import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from verify_third_party_notices import dart_dependencies, go_dependencies, verify


class ThirdPartyNoticeTests(unittest.TestCase):
    def fixture(self, root):
        (root / "client").mkdir()
        (root / "go.mod").write_text("module example\nrequire example.org/library v1.0.0\n")
        (root / "client/pubspec.lock").write_text(
            'packages:\n  library:\n    description:\n      url: "https://pub.dev"\n'
            '    source: hosted\n    version: "1.0.0"\n')
        evidence = root / "third_party/licenses/LICENSE"
        evidence.parent.mkdir(parents=True)
        evidence.write_bytes(b"original notice\n")
        notice = {"file": "third_party/licenses/LICENSE",
                  "sha256": hashlib.sha256(evidence.read_bytes()).hexdigest()}
        identities = [("Go", "example.org/library"), ("Dart", "library"),
                      ("SDK", "Go-runtime-and-standard-library"), ("SDK", "Flutter"), ("SDK", "Dart"),
                      ("SDK", "Flutter-engine-and-native-libraries"), ("Asset", "Material-icons-fonts"),
                      ("Build", "Gradle-wrapper")]
        report = {"components": [{"ecosystem": ecosystem, "name": name, "version": "v1.0.0" if ecosystem == "Go" else "1.0.0",
                                  "status": "local-license-text-collected", "licenses": [notice.copy()]}
                                 for ecosystem, name in identities],
                  "android_runtime_graph_complete": True, "completed_legal_audit": False,
                  "android_metadata": [{"coordinate": "example:library:1.0.0", "status": "resolved-runtime-POM-metadata",
                                        "pom_sha256": "a" * 64, "licenses": [{"name": "upstream license"}]}]}
        self.save(root, report)
        return report

    def save(self, root, report):
        (root / "THIRD_PARTY_NOTICES.json").write_text(json.dumps(report))

    def test_complete_local_evidence_does_not_change_legal_audit_status(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            before = (root / "THIRD_PARTY_NOTICES.json").read_bytes()
            counts = verify(root)
            self.assertEqual(counts, {"components": 8, "android_modules": 1})
            self.assertEqual((root / "THIRD_PARTY_NOTICES.json").read_bytes(), before)
            self.assertFalse(json.loads(before)["completed_legal_audit"])

    def test_lock_version_change_or_omitted_dependency_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = self.fixture(root)
            (root / "go.mod").write_text("module example\nrequire example.org/library v2.0.0\n")
            with self.assertRaisesRegex(ValueError, "Go notices differ"):
                verify(root)
            (root / "go.mod").write_text("module example\nrequire example.org/library v1.0.0\n")
            report["components"] = [item for item in report["components"] if item["ecosystem"] != "Dart"]
            self.save(root, report)
            with self.assertRaisesRegex(ValueError, "Dart notices differ"):
                verify(root)

    def test_missing_modified_or_unsafe_license_evidence_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = self.fixture(root)
            evidence = root / "third_party/licenses/LICENSE"
            evidence.write_text("different notice")
            with self.assertRaisesRegex(ValueError, "declared hash"):
                verify(root)
            evidence.unlink()
            with self.assertRaises(OSError):
                verify(root)
            report["components"][0]["licenses"][0]["file"] = "../private.key"
            self.save(root, report)
            with self.assertRaisesRegex(ValueError, "unsafe path"):
                verify(root)

    def test_missing_pom_or_unconfirmed_graph_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = self.fixture(root)
            report["android_metadata"][0]["status"] = "MISSING-POM"
            self.save(root, report)
            with self.assertRaisesRegex(ValueError, "POM records"):
                verify(root)
            report["android_metadata"][0]["status"] = "resolved-runtime-POM-metadata"
            report["android_runtime_graph_complete"] = False
            self.save(root, report)
            with self.assertRaisesRegex(ValueError, "complete runtime graph"):
                verify(root)

    def test_current_runtime_graph_must_match_the_declared_modules(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            inventory_path = root / "inventory.json"
            inventory = {"schemaVersion": 2, "complete": True, "configuration": "releaseRuntimeClasspath",
                         "modules": [{"group": "example", "name": "library", "version": "1.0.0"}],
                         "artifactFiles": [{"coordinate": "example:library:1.0.0", "file": "library.aar"}]}
            inventory_path.write_text(json.dumps(inventory))
            verify(root, inventory_path)
            inventory["modules"][0]["version"] = "2.0.0"
            inventory["artifactFiles"][0]["coordinate"] = "example:library:2.0.0"
            inventory_path.write_text(json.dumps(inventory))
            with self.assertRaisesRegex(ValueError, "current release runtime graph"):
                verify(root, inventory_path)

    def test_generation_parsers_cover_single_require_and_reject_untracked_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            (root / "go.mod").write_text(
                "module example\nrequire\texample.org/one\tv1.0.0\nrequire\t(\n example.org/two v2.0.0 // indirect\n)\n")
            self.assertEqual(go_dependencies(root), {"example.org/one": "v1.0.0", "example.org/two": "v2.0.0"})
            with (root / "go.mod").open("a") as file:
                file.write("replace example.org/one => ../local\n")
            with self.assertRaisesRegex(ValueError, "replace/exclude"):
                go_dependencies(root)
            (root / "client/pubspec.lock").write_text('packages:\n  library:\n    source: git\n    version: "1.0.0"\n')
            with self.assertRaisesRegex(ValueError, "git dependency"):
                dart_dependencies(root)

    def test_a_custom_host_cannot_use_the_public_registry_license_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            lock = root / "client/pubspec.lock"
            lock.write_text(lock.read_text().replace("https://pub.dev", "https://packages.example.com"))
            with self.assertRaisesRegex(ValueError, "pub.dev provenance"):
                verify(root)


if __name__ == "__main__":
    unittest.main()
