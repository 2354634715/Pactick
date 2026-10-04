#!/usr/bin/env python3
"""Create a new, reviewed-source snapshot. Never deletes or changes source files."""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import ipaddress
import json
import re
from pathlib import Path

ROOT_FILES = {
    ".gitignore", ".dockerignore", ".gitattributes", ".env.example",
    "README.md", "PROJECT_PLAN.md", "LICENSE", "CONTRIBUTING.md", "SECURITY.md",
    "CHANGELOG.md", "THIRD_PARTY_NOTICES.md", "THIRD_PARTY_NOTICES.json",
    "go.mod", "go.sum", "deployment_test.go", "Dockerfile", "Dockerfile.prebuilt",
    "compose.yaml", "compose.production.yaml", "third_party/gradle-wrapper/LICENSE",
    "third_party/gradle-wrapper/NOTICE", "third_party/metadata/gradle-wrapper.json",
    "third_party/metadata/guava-parent-26.0-android.pom",
    "third_party/metadata/material-timer/timer.svg",
    "third_party/metadata/material-timer/SOURCE.json",
    "third_party/metadata/distribution-notices.json",
    "client/assets/branding/pactick_icon.png",
    "client/assets/licenses/supplemental.json",
}
DOCS = {
    "BUILDING.md", "RELEASING.md", "SELF_HOSTING.md", "LICENSE_FAQ.md", "GETTING_STARTED.md",
    "ENTITY_SCHEMAS.md", "THIRD_PARTY_AUDIT.md", "PROJECT_ARCHITECTURE.md", "SERVER_ARCHITECTURE.md", "LOCAL_BACKUPS.md",
    "RELEASE_AND_PROMOTION_PLAN.md",
    "FINAL_CHECK_20261004.md",
    "ASSET_SOURCES.md", "ANDROID_SIGNING.md",
}
CLIENT_FILES = {
    "README.md", "LICENSE", ".gitignore", ".metadata", "analysis_options.yaml",
    "pubspec.yaml", "pubspec.lock",
}
TREES = ("cmd", "internal", "api", "scripts", ".github", "third_party/licenses",
         "client/lib", "client/test", "client/android/app/src")
ANDROID_FILES = {
    ".gitignore", "settings.gradle.kts", "build.gradle.kts", "gradle.properties",
    "gradlew", "gradlew.bat", "gradle/wrapper/gradle-wrapper.jar",
    "gradle/wrapper/gradle-wrapper.properties", "app/build.gradle.kts", "key.properties.example",
}
BLOCKED_PARTS = {".git", ".cache", ".codex", ".agents", ".direnv", ".ssh", ".aws",
                 "secrets", "backups", "exports", "build", ".dart_tool", ".gradle",
                 ".kotlin", ".cxx", "node_modules", ".venv", "venv", "__pycache__"}
BLOCKED_SUFFIXES = {".jks", ".keystore", ".p12", ".pfx", ".pem", ".key", ".secret",
                    ".db", ".sqlite", ".sqlite3", ".dump", ".log", ".apk", ".aab",
                    ".bak", ".backup", ".old", ".orig", ".rej", ".tmp", ".temp",
                    ".swp", ".swo", ".zip", ".tar", ".gz", ".tgz", ".7z", ".rar",
                    ".pyc", ".pyo", ".pyd"}
BLOCKED_NAMES = {"local.properties", "key.properties", "GeneratedPluginRegistrant.java",
                 ".netrc", "_netrc", ".npmrc", ".pypirc", ".pgpass", ".pgpass.conf",
                 ".pg_service.conf", ".envrc"}
BLOCKED_NAME_PATTERNS = ("*.dump.*", "*.sqlite-*", "*.sqlite3-*", "*.db-*",
                         "key.properties.*", ".envrc.*", "*~", "pactick-backup*.json",
                         "pactick-export*.json", "pactick-server-export*.json")
ENV_PATTERNS = (".env", ".env.*", "*.env", "*.env.*")
ENV_EXAMPLE_PATTERNS = (".env.example", ".env.sample", ".env.template",
                        ".env.*.example", ".env.*.sample", ".env.*.template",
                        "*.env.example", "*.env.sample", "*.env.template")
PATTERNS = {
    "private-key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "cloud-access-key": re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "github-token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b"),
    "jwt-token": re.compile(r"\beyJ[A-Za-z0-9_-]{12,}\.eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{20,}\b"),
    "literal-environment-secret": re.compile(
        r"(?m)^[ \t]*(?:-[ \t]+)?(?:export[ \t]+)?[\"']?"
        r"(?:AUTH_JWT_SECRET|JWT_SECRET|POSTGRES_PASSWORD|TOKEN_HASH_KEY|"
        r"ANDROID_STORE_PASSWORD|ANDROID_KEY_PASSWORD|ANDROID_KEYSTORE_BASE64)"
        r"[\"']?[ \t]*(?:=|:)[ \t]*"
        r"(?P<literal>\"[^\"\r\n]{32,}\"|'[^'\r\n]{32,}'|[A-Za-z0-9+/_=.!@%&*-]{32,})"
        r"[ \t]*(?:#.*)?\r?$"),
    "personal-windows-path": re.compile(r"[A-Za-z]:[\\/]+Users[\\/]+(?!Public\b)[^\s\\/]+", re.I),
}
IPV4 = re.compile(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])")
URL_HOST = re.compile(r"https?://([a-zA-Z0-9.-]+)")
URL_CREDENTIALS = re.compile(r"(?:https?|postgres(?:ql)?):/{2}[A-Za-z0-9_-]+:([A-Za-z0-9+/.=_-]{8,})@")
EXAMPLE_PASSWORDS = {"pactick", "postgres", "password", "change-me", "replace_me", "change_me"}
PUBLIC_REFERENCE_HOSTS = {"github.com", "docs.github.com", "docs.docker.com", "ubuntu.com",
                          "letsencrypt.org", "nginx.org", "www.postgresql.org", "go.dev",
                          "docs.flutter.dev", "developer.android.com", "api.example.com"}


def allowed(relative: Path) -> bool:
    name = relative.as_posix()
    if set(relative.parts) & BLOCKED_PARTS or relative.suffix.lower() in BLOCKED_SUFFIXES:
        return False
    if relative.name in BLOCKED_NAMES:
        return False
    if (relative.name != "key.properties.example"
            and any(fnmatch.fnmatchcase(relative.name, pattern) for pattern in BLOCKED_NAME_PATTERNS)):
        return False
    if (any(fnmatch.fnmatchcase(relative.name, pattern) for pattern in ENV_PATTERNS)
            and not any(fnmatch.fnmatchcase(relative.name, pattern) for pattern in ENV_EXAMPLE_PATTERNS)):
        return False
    if name in ROOT_FILES or name in {"docs/" + x for x in DOCS}:
        return True
    if name in {"client/" + x for x in CLIENT_FILES}:
        return True
    if name in {"client/android/" + x for x in ANDROID_FILES}:
        return True
    if any(name.startswith(tree + "/") for tree in TREES):
        return True
    if name.startswith("deploy/"):
        return relative.name == "README.md" or relative.suffix in {".sh", ".example", ".template", ".service", ".timer"}
    return False


def is_real_public_ip(value: str) -> bool:
    try:
        return ipaddress.ip_address(value).is_global
    except ValueError:
        return False


def private_terms(root: Path, additional: Path | None) -> set[str]:
    """Read historical deployment notes locally; never copy them or print their contents."""
    terms = set()
    for path in (root / "docs").glob("SERVER_DEPLOYMENT_*.md"):
        text = path.read_text(encoding="utf-8-sig")
        terms.update(ip for ip in IPV4.findall(text) if is_real_public_ip(ip))
        terms.update(host.lower() for host in URL_HOST.findall(text)
                     if host.lower() not in PUBLIC_REFERENCE_HOSTS
                     and "." in host and not re.fullmatch(r"[\d.]+", host)
                     and not host.endswith((".example.com", ".example.org", ".example.net")))
    if additional:
        terms.update(line.strip().lower() for line in additional.read_text(encoding="utf-8-sig").splitlines()
                     if line.strip() and not line.startswith("#"))
    return terms


def findings(relative: Path, data: bytes, denied: set[str]) -> list[str]:
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return [] if relative.suffix.lower() in {".png", ".jar"} else ["unreviewed-binary"]
    issues = []
    for label, pattern in PATTERNS.items():
        if label == "literal-environment-secret":
            if any(not _example_secret(match.group("literal")) for match in pattern.finditer(text)):
                issues.append(label)
        elif pattern.search(text):
            issues.append(label)
    if any(password.lower() not in EXAMPLE_PASSWORDS
           and not password.lower().startswith(("replace", "change", "example", "test"))
           for password in URL_CREDENTIALS.findall(text)):
        issues.append("url-credentials")
    if any(term in text.lower() for term in denied):
        issues.append("private-deployment-reference")
    if any(is_real_public_ip(value) for line in text.splitlines()
           if not re.match(r'\s*"coordinate":\s*"[^:]+:[^:]+:', line)
           for value in IPV4.findall(line)):
        issues.append("public-ip-address")
    return issues


def _example_secret(literal: str) -> bool:
    value = literal.strip("\"'").lower()
    return (value in {"local-development-secret-change-before-deploy",
                      "replace-with-at-least-32-random-characters"}
            or bool(re.fullmatch(r"\$\{[a-z_][a-z0-9_]*\}|"
                                 r"\$\{\{[ \t]*secrets\.[a-z_][a-z0-9_]*[ \t]*\}\}", value)))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path, nargs="?", help="New directory; existing paths are never overwritten")
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--private-terms", type=Path, help="Local-only file containing one forbidden value per line")
    parser.add_argument("--check", action="store_true", help="Scan allowlisted files without creating a snapshot")
    args = parser.parse_args()
    root = args.source.resolve(strict=True)
    if not args.check and args.destination is None:
        parser.error("destination is required unless --check is used")
    destination = args.destination.resolve() if args.destination else None
    if destination and (destination.exists() or destination == root or destination in root.parents):
        parser.error("destination must be a new directory and cannot contain the source")
    denied = private_terms(root, args.private_terms)
    selected: list[tuple[Path, bytes]] = []
    problems = []
    candidates = {root / f for f in ROOT_FILES}
    candidates.update(root / "docs" / f for f in DOCS)
    candidates.update(root / "client" / f for f in CLIENT_FILES)
    candidates.update(root / "client/android" / f for f in ANDROID_FILES)
    for tree in (*TREES, "deploy"):
        directory = root / tree
        if directory.is_symlink():
            problems.append(f"{tree}: symlink")
        elif directory.is_dir():
            candidates.update(directory.rglob("*"))
    for path in sorted(candidates):
        relative = path.relative_to(root)
        if not allowed(relative):
            continue
        if path.is_symlink() or any(p.is_symlink() for p in path.parents if p != root and root in p.parents):
            problems.append(f"{relative.as_posix()}: symlink")
            continue
        if not path.is_file():
            continue
        data = path.read_bytes()
        issues = findings(relative, data, denied)
        if issues:
            problems.append(f"{relative.as_posix()}: {', '.join(issues)}")
        selected.append((relative, data))
    required = {"LICENSE", "README.md", "go.mod", "go.sum", "client/pubspec.lock", "docs/SELF_HOSTING.md"}
    missing = required - {path.as_posix() for path, _ in selected}
    problems.extend(f"{name}: required-file-missing" for name in sorted(missing))
    if problems:
        raise SystemExit("Snapshot blocked; original files were not changed:\n" + "\n".join(problems))
    if args.check:
        print(f"Checked {len(selected)} allowlisted files; no heuristic findings. Manual review is still required.")
        return
    destination.mkdir(parents=True, exist_ok=False)
    manifest = []
    for relative, data in selected:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if (relative.suffix.lower() not in {".png", ".jar", ".bat"}
                and relative.parts[0] != "third_party"):
            data = data.replace(b"\r\n", b"\n")
        target.write_bytes(data)
        if relative.suffix in {".sh", ".py"} or relative.name == "gradlew":
            target.chmod(0o755)
        manifest.append({"path": relative.as_posix(), "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)})
    (destination / "SOURCE_MANIFEST.json").write_bytes((json.dumps(manifest, indent=2) + "\n").encode("utf-8"))
    print(f"Created {len(selected)} files in {destination}; original files were not changed.")


if __name__ == "__main__":
    main()
