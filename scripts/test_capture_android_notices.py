import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from capture_android_notices import capture


class NativeNoticeTests(unittest.TestCase):
    def test_final_binary_nested_notices_and_apk_are_linked_without_local_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inner = io.BytesIO()
            with zipfile.ZipFile(inner, "w") as archive:
                archive.writestr("META-INF/NOTICE", "nested attribution")
            binary = root / "library.aar"
            with zipfile.ZipFile(binary, "w") as archive:
                archive.writestr("LICENSE.txt", "library license")
                archive.writestr("classes.jar", inner.getvalue())
            apk = root / "app.apk"
            apk.write_bytes(b"candidate apk")
            inventory = root / "inventory.json"
            inventory.write_text(json.dumps({
                "schemaVersion": 2, "complete": True, "configuration": "releaseRuntimeClasspath",
                "modules": [{"group": "example", "name": "library", "version": "1"}],
                "artifactFiles": [{"coordinate": "example:library:1", "file": str(binary)}],
            }))
            evidence = root / "evidence"
            result = capture(inventory, apk, evidence)
            self.assertEqual(result["apk_sha256"], hashlib.sha256(apk.read_bytes()).hexdigest())
            records = result["artifacts"]
            self.assertEqual(records[0]["sha256"], hashlib.sha256(binary.read_bytes()).hexdigest())
            self.assertEqual(len(records[0]["embedded_notices"]), 2)
            self.assertTrue(any("classes.jar!/META-INF/NOTICE" == item["archive_entry"]
                                for item in records[0]["embedded_notices"]))
            for notice in records[0]["embedded_notices"]:
                data = (evidence / notice["file"]).read_bytes()
                self.assertEqual(notice["sha256"], hashlib.sha256(data).hexdigest())
            self.assertNotIn(str(root), (evidence / "ANDROID_NATIVE_EVIDENCE.json").read_text())
            self.assertFalse(result["completed_legal_audit"])

    def test_historical_graph_without_final_artifacts_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inventory = root / "inventory.json"
            inventory.write_text(json.dumps({"schemaVersion": 1, "complete": True,
                                             "configuration": "releaseRuntimeClasspath", "modules": []}))
            with self.assertRaisesRegex(ValueError, "resolved artifacts"):
                capture(inventory, root / "app.apk", root / "evidence")
            self.assertFalse((root / "evidence").exists())


if __name__ == "__main__":
    unittest.main()
