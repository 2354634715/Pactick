#!/usr/bin/env python3
"""Collect local license evidence without claiming a completed legal audit."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from verify_third_party_notices import dart_dependencies, go_dependencies, inventory_coordinates


def license_kind(text: str) -> str:
    lower = text.lower()
    if "attribution 4.0 international" in lower:
        return "CC-BY-4.0 (review attribution and modifications)"
    if ("apache license" in lower and "permission is hereby granted, free of charge" in lower):
        return "Multiple licenses (review complete text)"
    if "apache license" in lower and "version 2.0" in lower:
        return "Apache-2.0 (text match; review notices)"
    if "permission is hereby granted, free of charge" in lower:
        return "MIT (text match)"
    if "redistribution and use in source and binary forms" in lower:
        return "BSD family (review exact terms)"
    return "Review original text"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--go-cache", type=Path, required=True)
    parser.add_argument("--pub-cache", type=Path, required=True)
    parser.add_argument("--flutter-sdk", type=Path, required=True)
    parser.add_argument("--go-sdk", type=Path, help="Go SDK root for the runtime/standard library license")
    parser.add_argument("--gradle-cache", type=Path, help="Gradle modules-2/files-2.1 directory; metadata evidence only")
    parser.add_argument("--android-inventory", type=Path, help="Resolved release runtime graph from the Gradle inventory task")
    args = parser.parse_args()
    root = args.root.resolve()
    evidence = root / "third_party/licenses"
    evidence.mkdir(parents=True, exist_ok=True)
    components = []

    def collect(ecosystem: str, name: str, version: str, directory: Path, source: str) -> None:
        files = sorted({path for pattern in ("*LICENSE*", "*LICENCE*", "COPYING*", "*NOTICE*", "*license*", "copyright*")
                        for path in directory.glob(pattern) if path.is_file()})
        notices = []
        slug = re.sub(r"[^A-Za-z0-9._-]", "_", f"{ecosystem}-{name}-{version}")
        for index, path in enumerate(files):
            data = path.read_bytes()
            target = evidence / f"{slug}-{index}-{path.name}"
            target.write_bytes(data)
            notices.append({"file": target.relative_to(root).as_posix(),
                            "sha256": hashlib.sha256(data).hexdigest(),
                            "classification": license_kind(data.decode("utf-8", errors="replace"))})
        components.append({"ecosystem": ecosystem, "name": name, "version": version, "source": source,
                           "status": "local-license-text-collected" if notices else "MISSING-license-text",
                           "licenses": notices})

    for name, version in go_dependencies(root).items():
        escaped = re.sub(r"[A-Z]", lambda m: "!" + m.group().lower(), name)
        collect("Go", name, version, args.go_cache / f"{escaped}@{version}", f"https://pkg.go.dev/{name}@{version}")

    for name, version in dart_dependencies(root).items():
        collect("Dart", name, version, args.pub_cache / "hosted/pub.dev" / f"{name}-{version}",
                f"https://pub.dev/packages/{name}/versions/{version}")
    config_path = root / "client/.dart_tool/package_config.json"
    config = json.loads(config_path.read_text()) if config_path.is_file() else {}
    if args.go_sdk:
        version_file = args.go_sdk / "VERSION"
        version = version_file.read_text().splitlines()[0] if version_file.is_file() else "inspect-sdk-version"
        collect("SDK", "Go-runtime-and-standard-library", version, args.go_sdk, "https://go.dev/LICENSE")
    collect("SDK", "Flutter", config.get("flutterVersion", "inspect-sdk-version"), args.flutter_sdk,
            "https://github.com/flutter/flutter")
    collect("SDK", "Dart", config.get("generatorVersion", "inspect-sdk-version"), args.flutter_sdk / "bin/cache/dart-sdk",
            "https://github.com/dart-lang/sdk")
    engine_stamp = args.flutter_sdk / "bin/cache/engine.stamp"
    engine_version = engine_stamp.read_text().strip() if engine_stamp.is_file() else "inspect-engine-version"
    collect("SDK", "Flutter-engine-and-native-libraries", engine_version,
            args.flutter_sdk / "bin/cache/pkg/sky_engine", "https://github.com/flutter/flutter/tree/main/engine")
    collect("Asset", "Material-icons-fonts", "Flutter-bundled", args.flutter_sdk / "bin/cache/artifacts/material_fonts",
            "https://github.com/google/material-design-icons")
    wrapper_provenance = root / "third_party/metadata/gradle-wrapper.json"
    wrapper_version = "inspect-wrapper-version"
    if wrapper_provenance.is_file():
        wrapper = json.loads(wrapper_provenance.read_text(encoding="utf-8"))
        wrapper_bytes = (root / "client/android/gradle/wrapper/gradle-wrapper.jar").read_bytes()
        if hashlib.sha256(wrapper_bytes).hexdigest() != wrapper["wrapper_sha256"]:
            raise SystemExit("Gradle wrapper differs from its reviewed provenance")
        wrapper_version = wrapper["wrapper_version"]
    collect("Build", "Gradle-wrapper", wrapper_version, root / "third_party/gradle-wrapper",
            "https://github.com/gradle/gradle")
    timer_license = root / "third_party/licenses/Asset-Material-timer-Apache-2.0.txt"
    timer_provenance = root / "third_party/metadata/material-timer/SOURCE.json"
    if timer_license.is_file() and timer_provenance.is_file():
        timer = json.loads(timer_provenance.read_text(encoding="utf-8"))
        components.append({"ecosystem": "Asset", "name": "Material-timer-vector",
                           "version": timer["revision"], "source": timer["repository"],
                           "status": "local-license-text-collected", "licenses": [{
                               "file": timer_license.relative_to(root).as_posix(),
                               "sha256": hashlib.sha256(timer_license.read_bytes()).hexdigest(),
                               "classification": "Apache-2.0 (text match; review notices)"}]})
    cldr_license = root / "third_party/licenses/Asset-Unicode-CLDR-48-LICENSE"
    if cldr_license.is_file():
        components.append({"ecosystem": "Asset", "name": "Unicode-CLDR-locale-data",
                           "version": "48", "source": "https://github.com/unicode-org/cldr/blob/release-48/LICENSE",
                           "status": "local-license-text-collected", "licenses": [{
                               "file": cldr_license.relative_to(root).as_posix(),
                               "sha256": hashlib.sha256(cldr_license.read_bytes()).hexdigest(),
                               "classification": "Unicode-3.0 (review copyright and data notices)"}]})

    android = []
    resolved = None
    if args.android_inventory:
        inventory = json.loads(args.android_inventory.read_text())
        resolved = inventory_coordinates(inventory)
    if args.gradle_cache:
        seen = set()
        for pom in sorted(args.gradle_cache.glob("*/*/*/*/*.pom")):
            group, name, version = pom.relative_to(args.gradle_cache).parts[:3]
            coordinate = f"{group}:{name}:{version}"
            if coordinate in seen or (resolved is not None and coordinate not in resolved):
                continue
            seen.add(coordinate)
            tree = ET.fromstring(pom.read_bytes())
            ns = {"m": "http://maven.apache.org/POM/4.0.0"}
            licenses = [{"name": item.findtext("m:name", "", ns), "url": item.findtext("m:url", "", ns)}
                        for item in tree.findall("m:licenses/m:license", ns)]
            parent = tree.find("m:parent", ns)
            parent_coordinate = None if parent is None else ":".join(
                parent.findtext("m:" + key, "", ns) for key in ("groupId", "artifactId", "version"))
            android.append({"coordinate": coordinate, "licenses": licenses,
                            "parent_coordinate": parent_coordinate,
                            "license_declaration_status": "declared-in-POM" if licenses else "review-parent-or-upstream-license",
                            "pom_sha256": hashlib.sha256(pom.read_bytes()).hexdigest(),
                            "status": "resolved-runtime-POM-metadata" if resolved is not None else "cache-POM-only-not-confirmed-in-app"})
        if resolved is not None:
            android.extend({"coordinate": coordinate, "licenses": [], "status": "MISSING-POM"}
                           for coordinate in sorted(resolved - seen))
            # Guava publishes the license in its Maven parent. Preserve both the
            # inherited declaration and the original, separately fetched parent POM.
            guava_parent = root / "third_party/metadata/guava-parent-26.0-android.pom"
            engine = next(item for item in components if item["name"] == "Flutter-engine-and-native-libraries")
            for item in android:
                if (not item["licenses"] and item.get("parent_coordinate") == "com.google.guava:guava-parent:26.0-android"
                        and guava_parent.is_file()):
                    parent_tree = ET.fromstring(guava_parent.read_bytes())
                    parent_licenses = [{"name": license.findtext("m:name", "", ns),
                                        "url": license.findtext("m:url", "", ns)}
                                       for license in parent_tree.findall("m:licenses/m:license", ns)]
                    parent_id = ":".join(parent_tree.findtext("m:" + key, "", ns)
                                         for key in ("groupId", "artifactId", "version"))
                    if parent_id != item["parent_coordinate"] or not parent_licenses:
                        raise SystemExit("Guava parent POM identity or license declaration does not match")
                    item["licenses"] = parent_licenses
                    item["license_declaration_status"] = "inherited-from-verified-parent-POM"
                    item["license_evidence"] = [{
                        "file": guava_parent.relative_to(root).as_posix(),
                        "sha256": hashlib.sha256(guava_parent.read_bytes()).hexdigest(),
                        "source": "https://repo.maven.apache.org/maven2/com/google/guava/guava-parent/26.0-android/guava-parent-26.0-android.pom",
                    }]
                group, name, version = item["coordinate"].split(":", 2)
                if (group == "io.flutter" and name in {"arm64_v8a_release", "armeabi_v7a_release", "x86_64_release", "flutter_embedding_release"}
                        and version == "1.0.0-" + engine_version and engine["licenses"]):
                    item["license_declaration_status"] = "no-direct-POM-declaration-matched-upstream-engine-text"
                    item["license_evidence"] = [{**entry, "source": engine["source"],
                                                 "engine_revision": engine_version} for entry in engine["licenses"]]
            for item in android:
                group, name, version = item["coordinate"].split(":", 2)
                archive_directory = args.gradle_cache / group / name / version
                notices = []
                binaries = []

                def collect_archive(archive: zipfile.ZipFile, origin: str) -> None:
                    for entry in archive.infolist():
                        basename = entry.filename.rsplit("/", 1)[-1]
                        if (not re.match(r"(?i)(?:license|licence|notice|copying)(?:[._-].*)?$", basename)
                                or entry.is_dir() or entry.file_size > 2_000_000):
                            continue
                        data = archive.read(entry)
                        try:
                            data.decode("utf-8")
                        except UnicodeDecodeError:
                            continue
                        key = hashlib.sha256((item["coordinate"] + origin + entry.filename).encode()).hexdigest()[:24]
                        target = evidence / f"Android-{key}.txt"
                        target.write_bytes(data)
                        notices.append({"file": target.relative_to(root).as_posix(), "archive_entry": origin + entry.filename,
                                        "sha256": hashlib.sha256(data).hexdigest()})

                for binary in sorted(archive_directory.glob("*/*")):
                    if binary.suffix not in {".aar", ".jar"}:
                        continue
                    binaries.append({"name": binary.name, "sha256": hashlib.sha256(binary.read_bytes()).hexdigest()})
                    with zipfile.ZipFile(binary) as archive:
                        collect_archive(archive, binary.name + "!/")
                        if "classes.jar" in archive.namelist():
                            with zipfile.ZipFile(io.BytesIO(archive.read("classes.jar"))) as nested:
                                collect_archive(nested, binary.name + "!/classes.jar!/")
                item["cached_artifacts"] = binaries
                item["embedded_notices"] = notices
                item["binary_notice_review"] = "evidence-collected-review-required" if notices else "pending-no-embedded-text-collected"
    report = {
        "scope": "Go go.mod + hosted Dart pubspec.lock + SDK licenses; Android POM and available embedded archive notice evidence",
        "android_runtime_graph_complete": resolved is not None,
        "completed_legal_audit": False,
        "components": components,
        "android_metadata": android,
        "pending": ["Review Android runtime metadata and all required AAR/JAR license/NOTICE texts, including missing local evidence",
                    "Preserve Flutter engine, native library and bundled font notices in the shipped APK",
                    "Verify original artwork provenance and custom source-available license compatibility",
                    "Review all exact third-party terms; automated text classification is not legal approval"],
    }
    (root / "THIRD_PARTY_NOTICES.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = ["# 第三方组件声明", "", "此清单根据本机锁定的依赖和许可证文件生成。第三方组件适用各自的许可并保留原版权，项目专用许可不覆盖这些组件。",
             "", "当前已采集本地许可证据，尚未完成全部组件与项目许可的兼容性审阅。Android 记录是否来自实际运行时依赖图，以 JSON 中的 android_runtime_graph_complete 和 status 字段为准。",
             "", "证据来源和发布前待核实事项见 [核查说明](docs/THIRD_PARTY_AUDIT.md) 和 [机器可读清单](THIRD_PARTY_NOTICES.json)。",
             "", "| 类型 | 组件 | 版本 | 本地许可证据 |", "| --- | --- | --- | --- |"]
    for item in components:
        links = "; ".join(f"[{entry['classification']}]({entry['file']})" for entry in item["licenses"]) or "**缺失，发布前需补齐**"
        lines.append(f"| {item['ecosystem']} | [{item['name']}]({item['source']}) | {item['version']} | {links} |")
    lines += ["", f"JSON 清单包含 {len(android)} 条 Android POM 元数据。记录是否属于本应用的实际依赖，以 status 字段为准。",
              "", "更新依赖后，应重新生成清单，保留所需版权声明和 NOTICE，并复核新增组件的许可后再构建发行包。", ""]
    (root / "THIRD_PARTY_NOTICES.md").write_text("\n".join(lines), encoding="utf-8")
    missing = sum(not item["licenses"] for item in components)
    print(f"Collected {len(components)} components ({missing} missing license texts), {len(android)} Android POM records.")


if __name__ == "__main__":
    main()
