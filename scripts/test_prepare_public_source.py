"""Regression checks for the boundary that protects private release material."""
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("prepare_public_source.py")
spec = importlib.util.spec_from_file_location("snapshot", SCRIPT)
snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshot)


class SnapshotTests(unittest.TestCase):
    def fixture(self, root):
        for name in ("LICENSE", "README.md", "go.mod", "go.sum", "client/pubspec.lock", "docs/SELF_HOSTING.md"):
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("reviewed source\n", encoding="utf-8")

    def test_excludes_private_and_generated_files(self):
        for name in (".env", "client/android/key.properties", "client/android/local.properties",
                     "client/android/release.jks", "client/build/a.apk", "internal/private.key",
                     "docs/SERVER_DEPLOYMENT_private.md", "docs/COMMERCIALIZATION_AGENT_IMPLEMENTATION_SPEC.md",
                     "output/screenshot.png", ".cache/test.go"):
            with self.subTest(name=name):
                self.assertFalse(snapshot.allowed(Path(name)))
        self.assertTrue(snapshot.allowed(Path("internal/db/migrations/001_init.sql")))
        self.assertTrue(snapshot.allowed(Path("deploy/config/api.env.example")))
        self.assertTrue(snapshot.allowed(Path("docs/GETTING_STARTED.md")))
        self.assertTrue(snapshot.allowed(Path("docs/ASSET_SOURCES.md")))

    def test_detects_sensitive_values_without_printing_them(self):
        secret = "ghp_" + "a" * 36
        ip = ".".join(["8"] * 4)
        for value in (secret, ip, "-----BEGIN " + "PRIVATE KEY-----"):
            self.assertTrue(snapshot.findings(Path("README.md"), value.encode(), set()))

    def test_snapshot_omits_private_files_inside_allowed_source_trees(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            root.mkdir()
            self.fixture(root)
            private_names = (
                "internal/private.env", "scripts/private.env.local", "scripts/.envrc",
                "scripts/.codex/config.toml", "scripts/.agents/local.md",
                "internal/secrets/jwt.txt", "internal/backups/production.sql",
                "scripts/exports/workspace.json", "scripts/settings.py.bak",
                "scripts/.netrc", "scripts/local.dump.gz", "internal/local.sqlite-wal",
                "client/lib/settings.dart~", "client/test/fixture.db-shm",
                "deploy/config/api.env.example.bak", "scripts/key.properties.local",
                "internal/pactick-backup.json", "scripts/pactick-export.json",
                "client/lib/pactick-server-export.json",
            )
            for name in private_names:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("local private data\n")
            public_names = (
                "deploy/config/api.env.example", "scripts/test.env.sample",
                "internal/database/migrations/001_initial.sql",
                "client/android/key.properties.example",
            )
            for name in public_names:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("reviewed example\n")
            target = Path(directory) / "public"
            result = subprocess.run([sys.executable, str(SCRIPT), "--source", str(root), str(target)],
                                    capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = {entry["path"] for entry in json.loads((target / "SOURCE_MANIFEST.json").read_text())}
            self.assertTrue(manifest.isdisjoint(private_names))
            self.assertTrue(set(public_names).issubset(manifest))
            for name in private_names:
                self.assertEqual((root / name).read_text(), "local private data\n")

    def test_snapshot_refuses_overwrite_and_keeps_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            root.mkdir()
            self.fixture(root)
            (root / ".env").write_text("private data")
            target = Path(directory) / "public"
            result = subprocess.run([sys.executable, str(SCRIPT), "--source", str(root), str(target)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((target / ".env").exists())
            self.assertEqual((root / ".env").read_text(), "private data")
            self.assertEqual(len(json.loads((target / "SOURCE_MANIFEST.json").read_text())), 6)
            repeat = subprocess.run([sys.executable, str(SCRIPT), "--source", str(root), str(target)], capture_output=True)
            self.assertNotEqual(repeat.returncode, 0)

    def test_failure_does_not_create_partial_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            root.mkdir()
            self.fixture(root)
            secret = "ghp_" + "b" * 36
            (root / "README.md").write_text(secret)
            target = Path(directory) / "public"
            result = subprocess.run([sys.executable, str(SCRIPT), "--source", str(root), str(target)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(target.exists())
            self.assertNotIn(secret.encode(), result.stderr)
            self.assertEqual((root / "README.md").read_text(), secret)

    def test_actual_secret_names_and_assignment_forms(self):
        secret = "s" * 64
        for name in ("AUTH_JWT_SECRET", "JWT_SECRET", "POSTGRES_PASSWORD", "TOKEN_HASH_KEY",
                     "ANDROID_STORE_PASSWORD", "ANDROID_KEY_PASSWORD", "ANDROID_KEYSTORE_BASE64"):
            for assignment in (f"{name}={secret}", f" export {name} = '{secret}' # secret",
                               f'  {name}: "{secret}"', f"  '{name}' : '{secret}'",
                               f"  - {name}={secret}", f'{name}="{secret}"\r\n'):
                with self.subTest(name=name, assignment=assignment):
                    self.assertIn("literal-environment-secret",
                                  snapshot.findings(Path(".env.example"), assignment.encode(), set()))
        for value in ("REPLACE_ME", "replace-with-at-least-32-random-characters",
                      "${AUTH_JWT_SECRET}", "${{ secrets.AUTH_JWT_SECRET }}"):
            self.assertNotIn("literal-environment-secret", snapshot.findings(
                Path(".env.example"), f"AUTH_JWT_SECRET={value}".encode(), set()))

    def test_real_jwt_template_blocks_entire_snapshot_without_disclosing_value(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            root.mkdir()
            self.fixture(root)
            secret = "z" * 64
            (root / ".env.example").write_text(f'  AUTH_JWT_SECRET = "{secret}"\n')
            target = Path(directory) / "public"
            result = subprocess.run([sys.executable, str(SCRIPT), "--source", str(root), str(target)],
                                    capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(target.exists())
            self.assertIn(b"literal-environment-secret", result.stderr)
            self.assertNotIn(secret.encode(), result.stderr)

    def test_example_prefix_does_not_exempt_a_real_secret(self):
        for prefix in ("replace-", "change-", "example-", "test-"):
            value = prefix + "a" * 64
            self.assertIn("literal-environment-secret", snapshot.findings(
                Path(".env.example"), f"AUTH_JWT_SECRET={value}".encode(), set()))


if __name__ == "__main__":
    unittest.main()
