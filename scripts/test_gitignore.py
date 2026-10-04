"""Check repository ignore rules with Git, including nested Android rules."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


@unittest.skipUnless(shutil.which("git"), "Git is required to check ignore rules")
class GitIgnoreTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        cls.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        for name in (".gitignore", "client/.gitignore", "client/android/.gitignore"):
            target = cls.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        subprocess.run(["git", "init", "--quiet", "--initial-branch=ignore-check"],
                       cwd=cls.root, env=cls.env, check=True, capture_output=True)

    def ignored(self, paths):
        result = subprocess.run(
            ["git", "-c", "core.excludesFile=", "check-ignore", "--no-index", "--stdin", "-z"],
            cwd=self.root, env=self.env, input=("\0".join(paths) + "\0").encode(),
            capture_output=True,
        )
        self.assertIn(result.returncode, (0, 1), result.stderr.decode(errors="replace"))
        return set(result.stdout.decode().split("\0")) - {""}

    def test_private_configuration_and_data_are_ignored(self):
        paths = (
            ".env", ".env.production", ".env.production.bak", "internal/private.env",
            "deploy/config/api.env", "deploy/config/api.env.backup",
            "client/android/key.properties", "client/android/key.properties.local",
            "client/android/release.jks", "client/android/release.keystore",
            ".envrc", ".envrc.local", ".direnv/state", ".codex/config.toml",
            ".agents/local.md", "scripts/.codex/config.toml", ".aws/credentials",
            ".ssh/id_ed25519", ".netrc", ".pgpass", "secrets/jwt.txt",
            "database.sqlite", "database.sqlite-wal", "database.db-shm",
            "production.sql", "exports/workspace.json", "backups/production.sql",
            "pactick-backup.json", "pactick-backup (1).json", "pactick-export.json",
            "pactick-server-export.json", "internal/pactick-backup-20261004.json",
            "docs/SERVER_DEPLOYMENT_private.md", "private-history/notes.md",
        )
        self.assertEqual(self.ignored(paths), set(paths))

    def test_generated_files_and_artifacts_are_ignored(self):
        paths = (
            ".cache/check.log", "output/candidate.zip", "artifacts/release.apk",
            "dist/source.tar.gz", "prebuilt/server", "node_modules/module/index.js",
            "scripts/__pycache__/script.pyc", "client/.dart_tool/package_config.json",
            "client/build/app/outputs/flutter-apk/app-debug.apk",
            "client/android/.gradle/state", "client/android/local.properties",
            "client/android/app/.cxx/state", "client/android/app/release/output.json",
            "client/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java",
        )
        self.assertEqual(self.ignored(paths), set(paths))

    def test_templates_and_build_inputs_remain_visible(self):
        paths = (
            ".env.example", ".env.sample", ".env.template", ".env.production.example",
            "deploy/config/api.env.example", "deploy/config/backup.env.example",
            "deploy/config/compose.env.example", "deploy/config/postgres.env.example",
            "client/android/key.properties.example", "go.mod", "go.sum",
            "client/pubspec.yaml", "client/pubspec.lock", "LICENSE", "client/LICENSE",
            "client/android/gradle/wrapper/gradle-wrapper.jar",
            "internal/database/migrations/000001_initial.up.sql",
            "client/assets/licenses/supplemental.json", "third_party/metadata/distribution-notices.json",
        )
        self.assertEqual(self.ignored(paths), set())


if __name__ == "__main__":
    unittest.main()
