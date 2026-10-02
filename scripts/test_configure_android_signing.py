from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from configure_android_signing import configure


class ConfigureSigningTests(unittest.TestCase):
    def fixture(self, directory):
        root = Path(directory)
        (root / "client/android").mkdir(parents=True)
        keystore = root / "private.jks"
        keystore.write_bytes(b"test placeholder")
        return root, keystore, root / "client/android/key.properties"

    def test_failed_validation_leaves_no_password_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root, keystore, target = self.fixture(directory)
            with patch("configure_android_signing.subprocess.run", return_value=subprocess.CompletedProcess([], 1)):
                with self.assertRaises(ValueError):
                    configure(root, keystore, "pactick", "keytool", "store-secret", "key-secret")
            self.assertFalse(target.exists())

    def test_existing_configuration_is_not_overwritten_or_validated(self):
        with tempfile.TemporaryDirectory() as directory:
            root, keystore, target = self.fixture(directory)
            target.write_text("original")
            with patch("configure_android_signing.subprocess.run") as run:
                with self.assertRaises(ValueError):
                    configure(root, keystore, "pactick", "keytool", "store-secret", "key-secret")
                run.assert_not_called()
            self.assertEqual(target.read_text(), "original")

    def test_passwords_are_passed_in_child_environment_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root, keystore, target = self.fixture(directory)
            with patch("configure_android_signing.subprocess.run", return_value=subprocess.CompletedProcess([], 0)) as run:
                configure(root, keystore, "pactick", "keytool", "store-secret", "key-secret")
            args, kwargs = run.call_args
            self.assertNotIn("store-secret", args[0])
            self.assertNotIn("key-secret", args[0])
            self.assertEqual(kwargs["env"]["PACTICK_LOCAL_STORE_PASSWORD"], "store-secret")
            self.assertEqual(kwargs["env"]["PACTICK_LOCAL_KEY_PASSWORD"], "key-secret")
            self.assertNotIn("store-secret", target.read_text())
            self.assertNotIn("key-secret", target.read_text())


if __name__ == "__main__":
    unittest.main()
