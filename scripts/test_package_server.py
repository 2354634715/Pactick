import hashlib
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
import zipfile

from package_server import archive, bundle_source, write_metadata


class ServerPackageTests(unittest.TestCase):
    def fixture(self, root):
        names = (
            "Dockerfile.prebuilt", ".dockerignore", "compose.production.yaml", "go.mod", "go.sum",
            "LICENSE", "THIRD_PARTY_NOTICES.md", "THIRD_PARTY_NOTICES.json",
            "deploy/desktop/compose.yaml", "deploy/desktop/run-server.ps1",
            "docs/SERVER_MANAGER.md", "docs/SELF_HOSTING.md", "docs/BUILDING.md",
            *(f"cmd/{program}/main.go" for program in ("server", "migrate", "healthcheck", "admin", "manager")),
            *(f"deploy/desktop/{name}" for name in ("launch-manager.cmd", "launch-manager.sh", "run-server.cmd", "run-server.sh")),
            "client/lib/main.dart", "internal/database/migrations/001_init.sql",
        )
        entries = []
        for name in names:
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            data = f"fixture: {name}\n".encode()
            path.write_bytes(data)
            entries.append({"path": name, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)})
        (root / "SOURCE_MANIFEST.json").write_text(json.dumps(entries), encoding="utf-8")

    def test_package_uses_manifest_and_excludes_client_and_unlisted_private_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source"
            source.mkdir()
            self.fixture(source)
            (source / "deploy/desktop/api.env").write_text("DATABASE_URL=private\n")
            bundle = Path(temporary) / "bundle"
            bundle.mkdir()
            bundle_source(source, bundle)
            self.assertTrue((bundle / "internal/database/migrations/001_init.sql").is_file())
            self.assertTrue((bundle / "launch-manager.cmd").is_file())
            self.assertFalse((bundle / "client").exists())
            self.assertFalse((bundle / "deploy/desktop/api.env").exists())

    def test_missing_manager_or_deployment_inputs_block_packaging(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source"
            source.mkdir()
            self.fixture(source)
            manifest = source / "SOURCE_MANIFEST.json"
            entries = json.loads(manifest.read_text())
            manifest.write_text(json.dumps([entry for entry in entries if entry["path"] != "cmd/manager/main.go"]))
            with self.assertRaisesRegex(ValueError, "cmd/manager/main.go"):
                bundle_source(source, Path(temporary) / "bundle")

    def test_archives_preserve_linux_executable_modes_and_metadata_checksums(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            bundle = output / "pactick-server-test"
            (bundle / "bin").mkdir(parents=True)
            (bundle / "bin/manager").write_bytes(b"executable fixture")
            (bundle / "launch-manager.sh").write_text("#!/bin/sh\n")
            release = {"release_tag": "v0.2.0", "source_commit": "a" * 40,
                       "source_manifest_sha256": "b" * 64}
            write_metadata(bundle, release, "linux", "amd64", "go version test")
            entries = json.loads((bundle / "SERVER_MANIFEST.json").read_text())
            for entry in entries:
                path = bundle / entry["path"]
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), entry["sha256"])
                self.assertEqual(path.stat().st_size, entry["size"])
            linux_asset = archive(bundle, output, "linux")
            with tarfile.open(linux_asset) as asset:
                self.assertEqual(asset.getmember(f"{bundle.name}/bin/manager").mode, 0o755)
                self.assertEqual(asset.getmember(f"{bundle.name}/launch-manager.sh").mode, 0o755)
                self.assertEqual(asset.getmember(f"{bundle.name}/RELEASE_SOURCE.json").mode, 0o644)
            windows_asset = archive(bundle, output, "windows")
            with zipfile.ZipFile(windows_asset) as asset:
                self.assertEqual(asset.getinfo(f"{bundle.name}/bin/manager").external_attr >> 16, 0o100755)
            checksum = linux_asset.with_name(linux_asset.name + ".sha256").read_text()
            self.assertEqual(checksum, f"{hashlib.sha256(linux_asset.read_bytes()).hexdigest()}  {linux_asset.name}\n")
            with self.assertRaises(FileExistsError):
                archive(bundle, output, "linux")


if __name__ == "__main__":
    unittest.main()
