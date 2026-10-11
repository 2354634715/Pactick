#!/usr/bin/env python3
"""Build Windows/Linux x86 server bundles from a verified public-source snapshot."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import zipfile

from verify_release_source import verify


PROGRAMS = ("server", "migrate", "healthcheck", "admin", "manager")
CONTAINER_PROGRAMS = ("server", "migrate", "healthcheck", "admin")
ROOT_FILES = {
    ".gitignore", ".gitattributes", ".dockerignore", "Dockerfile", "Dockerfile.prebuilt", "compose.yaml",
    "compose.production.yaml", "go.mod", "go.sum", "LICENSE", "CONTRIBUTING.md",
    "SECURITY.md", "CHANGELOG.md", "THIRD_PARTY_NOTICES.md", "THIRD_PARTY_NOTICES.json",
    "deployment_test.go",
}
SOURCE_TREES = ("cmd/", "internal/", "api/", "deploy/", "docs/", "scripts/", "third_party/")
LAUNCHERS = ("launch-manager.cmd", "launch-manager.sh", "run-server.cmd", "run-server.sh")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_flags(target_os: str) -> list[str]:
    flags = ["-trimpath", "-buildvcs=false"]
    if target_os != "windows":
        flags.append("-ldflags=-s -w")
    return flags


def bundle_source(source: Path, destination: Path) -> None:
    """Copy server inputs only; every input must already be in the verified manifest."""
    entries = json.loads((source / "SOURCE_MANIFEST.json").read_text(encoding="utf-8"))
    selected = {
        entry["path"] for entry in entries
        if entry["path"] in ROOT_FILES or entry["path"].startswith(SOURCE_TREES)
    }
    required = {
        "Dockerfile.prebuilt", ".dockerignore", "compose.production.yaml", "go.mod", "go.sum",
        "LICENSE", "THIRD_PARTY_NOTICES.md", "THIRD_PARTY_NOTICES.json",
        "deploy/desktop/compose.yaml", "deploy/desktop/run-server.ps1",
        "docs/SERVER_MANAGER.md", "docs/SELF_HOSTING.md", "docs/BUILDING.md",
        *(f"cmd/{program}/main.go" for program in PROGRAMS),
        *(f"deploy/desktop/{launcher}" for launcher in LAUNCHERS),
    }
    missing = required - selected
    if missing:
        raise ValueError("Server package lacks required snapshot files: " + ", ".join(sorted(missing)))
    for name in sorted(selected):
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / name, target)
        target.chmod(0o755 if target.suffix in {".sh", ".py"} else 0o644)
    shutil.copyfile(source / "SOURCE_MANIFEST.json", destination / "SOURCE_MANIFEST.json")
    for name in LAUNCHERS:
        shutil.copyfile(source / "deploy/desktop" / name, destination / name)
        (destination / name).chmod(0o755 if name.endswith(".sh") else 0o644)


def build(go: str, source: Path, destination: Path, target_os: str, target_arch: str,
          programs: tuple[str, ...]) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment.update(CGO_ENABLED="0", GOOS=target_os, GOARCH=target_arch)
    for program in programs:
        output = destination / (program + (".exe" if target_os == "windows" else ""))
        print(f"Building {target_os}/{target_arch}: {program}", flush=True)
        subprocess.run(
            [go, "build", *build_flags(target_os), "-o", str(output), f"./cmd/{program}"],
            cwd=source, env=environment, check=True,
        )
        output.chmod(0o755)


def write_metadata(bundle: Path, release_metadata: dict, target_os: str, target_arch: str,
                   go_version: str) -> None:
    (bundle / "RELEASE_SOURCE.json").write_text(
        json.dumps(release_metadata, indent=2) + "\n", encoding="utf-8",
    )
    (bundle / "SOURCE_COMMIT.txt").write_text(release_metadata["source_commit"] + "\n", encoding="utf-8")
    package = {
        "schema_version": 1,
        "release_tag": release_metadata["release_tag"],
        "source_commit": release_metadata["source_commit"],
        "source_manifest_sha256": release_metadata["source_manifest_sha256"],
        "native_platform": f"{target_os}/{target_arch}",
        "docker_platform": "linux/amd64",
        "go_version": go_version,
        "build_flags": build_flags(target_os),
        "build_environment": {"CGO_ENABLED": "0", "GOOS": target_os, "GOARCH": target_arch},
        "container_build_flags": build_flags("linux"),
        "container_build_environment": {"CGO_ENABLED": "0", "GOOS": "linux", "GOARCH": "amd64"},
        "built_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "native_programs": list(PROGRAMS),
        "container_programs": list(CONTAINER_PROGRAMS),
        "native_requirements": ["PostgreSQL 17 or a compatible server", "a local web browser"],
        "docker_requirements": ["Docker Engine with Linux containers", "Docker Compose v2",
                                "an amd64 Docker host", "a local web browser"],
    }
    (bundle / "SERVER_PACKAGE.json").write_text(json.dumps(package, indent=2) + "\n", encoding="utf-8")
    manifest = [
        {"path": path.relative_to(bundle).as_posix(), "size": path.stat().st_size, "sha256": digest(path)}
        for path in sorted(bundle.rglob("*")) if path.is_file()
    ]
    (bundle / "SERVER_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def archive(bundle: Path, output: Path, target_os: str) -> Path:
    """Preserve Linux executable modes even when packaging on Windows."""
    suffix = ".zip" if target_os == "windows" else ".tar.gz"
    path = output / (bundle.name + suffix)
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite release asset: {path}")
    if target_os == "windows":
        with zipfile.ZipFile(path, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive_file:
            for file in sorted(bundle.rglob("*")):
                if file.is_file():
                    relative = file.relative_to(bundle.parent).as_posix()
                    info = zipfile.ZipInfo.from_file(file, relative)
                    info.create_system = 3
                    executable = file.suffix == ".sh" or file.parent.name in {"bin", "prebuilt"}
                    info.external_attr = (0o100755 if executable else 0o100644) << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    archive_file.writestr(info, file.read_bytes(), compresslevel=9)
    else:
        with tarfile.open(path, "x:gz", compresslevel=9) as archive_file:
            for file in sorted(bundle.rglob("*")):
                relative = file.relative_to(bundle.parent).as_posix()
                info = archive_file.gettarinfo(str(file), relative)
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                executable = file.suffix == ".sh" or file.parent.name in {"bin", "prebuilt"}
                info.mode = 0o755 if file.is_dir() or executable else 0o644
                if file.is_file():
                    with file.open("rb") as stream:
                        archive_file.addfile(info, stream)
                else:
                    archive_file.addfile(info)
    checksum = path.with_name(path.name + ".sha256")
    if checksum.exists():
        raise FileExistsError(f"Refusing to overwrite release checksum: {checksum}")
    checksum.write_text(f"{digest(path)}  {path.name}\n", encoding="ascii")
    return path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path,
                        help="Snapshot produced by prepare_public_source.py; not a working tree")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--source-metadata", type=Path,
                        help="Require the metadata saved before source archiving")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "output/dist")
    parser.add_argument("--os", action="append", choices=("windows", "linux"), dest="operating_systems")
    parser.add_argument("--arch", action="append", choices=("amd64", "386"), dest="architectures")
    parser.add_argument("--go", default="go", help="Go executable path")
    args = parser.parse_args()
    try:
        source = args.source.resolve(strict=True)
        expected = (json.loads(args.source_metadata.read_text(encoding="utf-8"))
                    if args.source_metadata else None)
        if args.source_metadata and not isinstance(expected, dict):
            raise ValueError("Expected source metadata must be a JSON object")
        release_metadata = verify(source, args.tag, args.commit, allow_generated_files=True,
                                  expected_metadata=expected)
        output = args.output.resolve()
        if output == source or source in output.parents or output in source.parents:
            raise ValueError("Output must be separate from and outside the source snapshot")
        operating_systems = tuple(dict.fromkeys(args.operating_systems or ("windows", "linux")))
        architectures = tuple(dict.fromkeys(args.architectures or ("amd64",)))
        version = args.tag.removeprefix("v")
        for target_os in operating_systems:
            for target_arch in architectures:
                name = f"pactick-server-{version}-{target_os}-{target_arch}"
                suffix = ".zip" if target_os == "windows" else ".tar.gz"
                if (output / (name + suffix)).exists() or (output / (name + suffix + ".sha256")).exists():
                    raise FileExistsError(f"Release asset already exists: {name}{suffix}")
        go_version = subprocess.check_output([args.go, "version"], text=True).strip()
        output.mkdir(parents=True, exist_ok=True)
        created = []
        with tempfile.TemporaryDirectory(prefix=".server-build-", dir=output) as temporary:
            workspace = Path(temporary)
            container_binaries = workspace / "container-binaries"
            build(args.go, source, container_binaries, "linux", "amd64", CONTAINER_PROGRAMS)
            for target_os in operating_systems:
                for target_arch in architectures:
                    bundle = workspace / f"pactick-server-{version}-{target_os}-{target_arch}"
                    bundle.mkdir()
                    bundle_source(source, bundle)
                    if (target_os, target_arch) == ("linux", "amd64"):
                        shutil.copytree(container_binaries, bundle / "bin")
                        build(args.go, source, bundle / "bin", target_os, target_arch, ("manager",))
                    else:
                        build(args.go, source, bundle / "bin", target_os, target_arch, PROGRAMS)
                    shutil.copytree(container_binaries, bundle / "prebuilt")
                    # Reject any changed source input before creating a deliverable archive.
                    verify(source, args.tag, args.commit, allow_generated_files=True,
                           expected_metadata=release_metadata)
                    write_metadata(bundle, release_metadata, target_os, target_arch, go_version)
                    created.append(archive(bundle, output, target_os))
        for path in created:
            print(f"Created {path.name} ({path.stat().st_size} bytes)")
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Server packaging failed: {error}") from error


if __name__ == "__main__":
    main()
