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


class ReviewedFontTest(unittest.TestCase):
    def test_only_the_reviewed_font_path_and_bytes_can_be_exported(self):
        name = Path("client/assets/fonts/NotoSerifSC.ttf")
        font = SCRIPT.parent.parent / name
        self.assertTrue(snapshot.allowed(name))
        self.assertFalse(snapshot.allowed(Path("client/assets/fonts/local-font.ttf")))
        self.assertEqual(snapshot.findings(name, font.read_bytes(), set()), [])
        self.assertEqual(snapshot.findings(name, b"modified font", set()),
                         ["unreviewed-font-change"])

    def test_export_preserves_font_bytes_and_manifest(self):
        name = Path("client/assets/fonts/NotoSerifSC.ttf")
        original = (SCRIPT.parent.parent / name).read_bytes()
        self.assertIn(b"\r\n", original)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            for filename in ("LICENSE", "README.md", "go.mod", "go.sum",
                             "client/pubspec.lock", "docs/SELF_HOSTING.md"):
                path = root / filename
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("reviewed source\n", encoding="utf-8")
            font = root / name
            font.parent.mkdir(parents=True, exist_ok=True)
            font.write_bytes(original)
            target = Path(directory) / "public"
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--source", str(root), str(target)],
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((target / name).read_bytes(), original)
            records = json.loads((target / "SOURCE_MANIFEST.json").read_text())
            record = next(entry for entry in records if entry["path"] == name.as_posix())
            self.assertEqual(record["size"], len(original))


class SnapshotTests(unittest.TestCase):
    def test_english_documents_inherit_publication_scope(self):
        for name in ("README.en.md", "CONTRIBUTING.en.md", "CHANGELOG.en.md",
                     "client/README.en.md", "deploy/README.en.md",
                     "docs/GETTING_STARTED.en.md", "docs/LOCALIZATION.en.md", "docs/SYSTEM_CALENDAR.en.md",
                     "docs/AGENT_RELEASE_SPEC.en.md", ".github/pull_request_template.en.md"):
            with self.subTest(name=name):
                self.assertTrue(snapshot.allowed(Path(name)))
        for name in ("docs/SERVER_DEPLOYMENT_private.en.md",
                     "docs/FINAL_CHECK_20261004.en.md", "output/README.en.md",
                     "AGENTS.en.md", "docs/private.en.en.md"):
            with self.subTest(name=name):
                self.assertFalse(snapshot.allowed(Path(name)))

    def fixture(self, root):
        for name in ("LICENSE", "README.md", "go.mod", "go.sum", "client/pubspec.lock", "docs/SELF_HOSTING.md"):
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("reviewed source\n", encoding="utf-8")

    def test_snapshot_copies_english_companions_without_widening_scope(self):
        public_names = (
            "README.en.md", "PROJECT_PLAN.en.md", "CONTRIBUTING.en.md",
            "docs/GETTING_STARTED.en.md", "docs/LOCALIZATION.en.md", "docs/SYSTEM_CALENDAR.en.md",
            "client/README.en.md", "deploy/README.en.md",
            ".github/pull_request_template.en.md", "api/openapi.en.yaml",
            ".github/ISSUE_TEMPLATE/bug_report.en.yml",
            ".github/ISSUE_TEMPLATE/feature_request.en.yml",
        )
        private_names = (
            "docs/SERVER_DEPLOYMENT_private.en.md", "docs/FINAL_CHECK_20261004.en.md",
            "output/README.en.md", "AGENTS.en.md", "client/build/README.en.md",
            "internal/secrets/README.en.md",
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            root.mkdir()
            self.fixture(root)
            for name in public_names + private_names:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(f"translation fixture: {name}\r\n".encode("utf-8"))
                if name in public_names and name.endswith(".en.md"):
                    original = path.with_name(path.name[:-6] + ".md")
                    original.write_bytes(f"source fixture: {original.name}\r\n".encode("utf-8"))
            originals = {path.relative_to(root): path.read_bytes()
                         for path in root.rglob("*") if path.is_file()}
            target = Path(directory) / "public"
            result = subprocess.run([sys.executable, str(SCRIPT), "--source", str(root), str(target)],
                                    capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = {entry["path"] for entry in json.loads((target / "SOURCE_MANIFEST.json").read_text())}
            self.assertTrue(set(public_names).issubset(manifest))
            self.assertTrue(manifest.isdisjoint(private_names))
            for name in public_names:
                self.assertEqual((target / name).read_bytes(),
                                 originals[Path(name)].replace(b"\r\n", b"\n"))
            for name in private_names:
                self.assertFalse((target / name).exists())
            self.assertEqual({path.relative_to(root): path.read_bytes()
                              for path in root.rglob("*") if path.is_file()}, originals)

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

    def test_current_feature_docs_and_desktop_compose_remain_exportable(self):
        public_names = (
            "docs/AGENT_RELEASE_SPEC.md", "docs/ANDROID_TASK_REMINDER_CHECKLIST.md",
            "docs/FOCUS_MODES.md", "docs/PRIVATE_TASK_VAULT.md", "docs/SYSTEM_CALENDAR.md",
            "docs/SERVER_MANAGEMENT.md", "docs/SERVER_MANAGER.md", "docs/TASK_SCHEDULING_AND_REMINDERS.md",
            "deploy/desktop/compose.yaml",
            "deploy/desktop/launch-manager.cmd", "deploy/desktop/launch-manager.sh",
            "deploy/desktop/run-server.cmd", "deploy/desktop/run-server.ps1", "deploy/desktop/run-server.sh",
        )
        for name in public_names:
            with self.subTest(name=name):
                self.assertTrue(snapshot.allowed(Path(name)))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            root.mkdir()
            self.fixture(root)
            for name in public_names:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("reviewed feature source\n", encoding="utf-8")
            private_name = "deploy/desktop/production.env"
            private_path = root / private_name
            private_path.write_text("local configuration\n", encoding="utf-8")
            target = Path(directory) / "public"
            result = subprocess.run([sys.executable, str(SCRIPT), "--source", str(root), str(target)],
                                    capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = {entry["path"] for entry in json.loads((target / "SOURCE_MANIFEST.json").read_text())}
            self.assertTrue(set(public_names).issubset(manifest))
            self.assertNotIn(private_name, manifest)
            self.assertEqual(private_path.read_text(), "local configuration\n")

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
