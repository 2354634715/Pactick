[简体中文](THIRD_PARTY_AUDIT.md) | English

# Third-party license review and distribution-notice verification

2026-10-17 dependency change: the pure Dart package `cryptography 2.9.0` was added. Its original Apache-2.0 license was captured and hashed, and its complete text and package name were checked in this round's debug APK `NOTICES.Z`. The package declares no Flutter native plugin or new AAR/JAR, so native supplemental license assets remain unchanged. Incremental review records are in `third_party/metadata/distribution-notices.json`. This check is not a complete legal review or formal signed-APK acceptance.

Verification date: 2026-10-02. Current source version: `0.2.0-preview.1+4`. This round distributes a public-source preview and Android preview APK only, excluding full SDKs, build-tool distributions, dependency caches, design previews, test screenshots, and server container images.

Source review of the listed license texts, distribution conditions, custom project license, and notice implementation is complete for this round. New signed candidates must still pass final-APK checks; source review does not replace artifact or device-entry verification. This is a scoped license-compliance check, not a professional legal guarantee of all rights ownership, trademark availability, or patent status.

## Evidence and status

| Record | Purpose and limitations |
| --- | --- |
| `THIRD_PARTY_NOTICES.json`, `third_party/licenses/` | Record Go/Dart dependency versions, original LICENSE/NOTICE, and SHA-256 from dependency lists and local evidence. Automatic license classifications are an index only |
| `artifacts/android-runtime-dependencies.json` | Resolves module coordinates and external binaries in this build's `releaseRuntimeClasspath`. Original paths describe the build machine and do not ship with source |
| `ANDROID_NATIVE_EVIDENCE.json` | Captures hashes and embedded notices from actual AAR/JAR files, bound to this APK. Modules without embedded text still require upstream verification |
| [`third_party/metadata/distribution-notices.json`](../third_party/metadata/distribution-notices.json) | Records reviewed supplemental notices, dependency declarations, and original-notice hashes. Current status: `source-reviewed-final-apk-check-required` |
| [`client/assets/licenses/supplemental.json`](../client/assets/licenses/supplemental.json) | Complete supplemental notices read by the client, including native components, fonts, data, asset attribution, and required acknowledgments |
| `DISTRIBUTION_REVIEW.json` | Separate review record for each candidate. After artifact checks, maintainers bind it to the final APK, source, and dependency evidence and explicitly record completed scope and unverified matters |

The collector fixes `completed_legal_audit` to false. It does not perform final distribution-obligation review and does not automatically change that field when a candidate passes. This does not require maintainers to retain an “unreviewed” conclusion permanently. Distribution-compliance status is recorded separately in `DISTRIBUTION_REVIEW.json` and applies only to its bound artifacts. Dependency, license, asset, or notice changes require review again.

Detailed records on the maintenance machine are in `output/license-review-20261002/`. Component review starts with the original candidate's 103 records and adds CLDR 48 data and the official timer asset. Android modules are checked separately against the actual runtime graph. Not all process records enter public source; public contents are determined by the current `SOURCE_MANIFEST.json`.

## Conclusions on license terms

The project [LICENSE](../LICENSE) distinguishes original Pactick code, documents, and assets from separately identified third-party material. Third-party components retain their licenses; Pactick's commercial restrictions do not extend to them, icon fonts, or data. Reviewed runtime terms do not require the entire Pactick project to use GPL, LGPL, or MPL. Apache-2.0 permits different terms for the whole work or modifications while preserving the original components' license, notice, and modification-disclosure obligations. See the [Apache-2.0 text](https://www.apache.org/licenses/LICENSE-2.0).

| License or component | Conditions and handling in this distribution |
| --- | --- |
| MIT, BSD-2-Clause, BSD-3-Clause | Retain applicable copyright, conditions, and disclaimer. BSD-3-Clause also prohibits unauthorized use of holders'/contributors' names to imply endorsement |
| Apache-2.0 | Retain complete text, applicable copyright/patent/attribution notices, and upstream NOTICE. State changes to third-party files. Do not replace original-component licenses with the project license |
| Go `gopkg.in/yaml.v3` | Some files ported from libyaml use MIT; the rest use Apache-2.0. Retain both sets of notices and Canonical NOTICE; this is not a choice of one license for all files |
| Flutter MaterialIcons font | The actual SDK ships CC BY 4.0. Retain Google attribution, font-package source, full text, disclaimer, and explanation that Flutter removes unused glyphs |
| Google Material `timer` SVG | The pinned-commit asset uses Apache-2.0. Retain source, original SVG, license, conversion date, and explanation of conversion to a white Android vector |
| intl CLDR 48-derived data | Separately retain accurate Unicode-3.0 copyright/license notices. Root Dart-package BSD text or engine Unicode notices from other years are not substitutes |
| FreeType, libjpeg-turbo/IJG | Preserve engine licenses; supplemental notices provide affirmative FreeType Team and Independent JPEG Group acknowledgments |
| Native jsr305, Kotlin, and related submaterials | Retain primary licenses and independent attribution, CC BY, BSD, Boost, and other applicable texts for submaterials. Maven POM license names alone are insufficient |

CC BY requires attribution, source, license, and modification disclosure and prohibits extra restrictions that obstruct the asset's licensed rights. The font retains CC BY 4.0 from the actual SDK version; the independent official timer SVG uses Apache-2.0 from its pinned commit. These licenses must not be confused. See [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/legalcode.en).

FreeType follows the engine's retained FTL route with affirmative acknowledgment; its GPL alternative was not selected. See [FreeType licensing](https://freetype.org/license.html). IJG binary distribution requires explicit acknowledgment in product documentation. Displaying upstream text saying an acknowledgment is required does not itself replace the product acknowledgment. See [libjpeg-turbo licensing](https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/LICENSE.md).

The complete Flutter-engine aggregate also includes other platforms, tests, and development tools. Retaining all 1593 notice sections does not mean every item is linked into the Android APK. The Go server is not part of the APK. The Dart lockfile includes development dependencies and other-platform implementations; a license notice does not prove that component runs on Android.

## Gradle wrapper and separate tools

The repository's `gradle-wrapper.jar` hash matches the official Gradle 2.10 wrapper. The JAR contains wrapper and CLI classes only. `gradle-wrapper.properties` configures downloading Gradle 9.4.1. Both versions are recorded separately in [`gradle-wrapper.json`](../third_party/metadata/gradle-wrapper.json); accurate [LICENSE](../third_party/gradle-wrapper/LICENSE) and [NOTICE](../third_party/gradle-wrapper/NOTICE) accompany source. See [official Gradle checksums](https://gradle.org/release-checksums/).

The full Gradle distribution includes separate tools under LGPL, MPL, CDDL, EPL, and other terms. Those tools are absent from the reviewed wrapper/CLI JAR and are not distributed as part of the Android client. This round does not distribute full Gradle, Flutter, Dart, Go, or JDK packages. Changes to that scope require separate checks of actual tool distributions. Container base images are also outside this round's distribution review.

## Packaging and accessing client notices

Flutter's `LicenseCollector` traverses LICENSE/NOTICES in packages from `package_config.json`, including `sky_engine`, and combines them into `assets/flutter_assets/NOTICES.Z`. The framework registers these texts with `LicenseRegistry`. A client copy of the root LICENSE is kept at `client/LICENSE`; CI and APK checks require identical text.

Startup calls `registerSupplementalLicenses()`, registering the supplemental reader once. Only when opening Settings → About Pactick does `LicenseRegistry` load `assets/licenses/supplemental.json` and generate license entries; the main page does not read this asset at startup. An unsupported schema, empty entries, or invalid component names/text causes `FormatException`. Missing or malformed assets must not be treated as complete notices.

The current supplemental asset has 24 entries: 18 native/submaterial notices cover 71 non-Flutter-engine modules, and six others provide the independent-third-party-license note, Material font, CLDR, FreeType, IJG, and Google timer. Four Flutter-engine modules are covered by the full engine statement, matching 75 runtime module coordinates in total. This grouping changes with dependencies; use reviewed metadata and this build's resolved graph.

The license page uses Flutter [`showLicensePage`](https://api.flutter.dev/flutter/material/showLicensePage.html). Three supplemental-license tests cover the real asset/required text, deduplication of repeated registration, and rejection of invalid formats. They do not replace byte checks of the final signed APK or checking the license page on a phone.

The original `0.2.0-preview.1+3` signed candidate contained the project license and all 1593 engine sections but lacked this round's supplemental notices. That historical result does not establish checks for a new `+4` candidate; old APKs cannot validate new assets.

## Checks after every signed build

Prerequisites: generate an independent allowlisted source snapshot, run `flutter pub get` and build a release APK there, and configure a valid Android SDK. Run the commands below from the build snapshot's project root. On Windows, use `gradlew.bat` in `client/android`; elsewhere use `./gradlew`.

First resolve this release's runtime graph:

```sh
cd client/android
./gradlew -I ../../scripts/android-dependencies.init.gradle :app:writeRuntimeDependencyInventory
cd ../..
```

The task writes the complete schema 2 graph and external binary paths to `artifacts/android-runtime-dependencies.json`; no production signing key is needed. Resolution may download dependencies. Unresolved dependencies fail the command; a historical graph must not be presented as a successful current result.

Then verify dependencies, notice sources, and the final APK:

```sh
python3 scripts/verify_third_party_notices.py \
  --android-inventory artifacts/android-runtime-dependencies.json

python3 scripts/verify_supplemental_notices.py \
  --android-inventory artifacts/android-runtime-dependencies.json \
  --apk client/build/app/outputs/flutter-apk/app-release.apk

python3 scripts/verify_apk_notices.py \
  client/build/app/outputs/flutter-apk/app-release.apk
```

`verify_third_party_notices.py` checks locked Go/Dart versions, required SDK/font/wrapper records, original-text SHA-256, and Android coordinates. It rejects missing text, unconfirmed/missing POMs, and paths outside the evidence directory. It does not redownload upstream POMs; POM names/hashes do not replace actual license texts.

`verify_supplemental_notices.py` checks reviewed hashes for the supplemental asset and each text, Go/Dart dependency declarations, runtime graph, coverage of all 71 native modules, required original texts, and affirmative acknowledgments. With `--apk`, it also requires APK asset `assets/flutter_assets/assets/licenses/supplemental.json` to be byte-identical to source. Dependency, module-version, original-text, or asset changes fail the command. Update captured evidence and review records before rebuilding; merely changing hashes cannot bypass review.

`verify_apk_notices.py` extracts NOTICES.Z, checks the complete project license and all engine texts from the current SDK, and invokes supplemental verification. By default it finds `sky_engine/LICENSE` through Flutter on PATH; `--engine-license PATH` overrides it. `--root PATH` selects the project root for supplemental checks, defaulting to the script's project. `--project-license PATH` separately selects the project license to compare, defaulting to that root's LICENSE, and does not change the supplemental asset location. Any missing required text or asset fails the command.

Finally capture evidence from this build's actual native binaries:

```sh
python3 scripts/capture_android_notices.py \
  artifacts/android-runtime-dependencies.json \
  client/build/app/outputs/flutter-apk/app-release.apk \
  artifacts/android-native-evidence
```

The target directory must not exist. The collector accepts only a complete schema 2 release inventory, records APK and actual AAR/JAR SHA-256, preserves LICENSE/NOTICE from archives and one level of nested JARs, and excludes build-machine absolute paths from output. A single notice/nested JAR exceeding 64 MiB, a missing binary, or unreadable archive fails the command. A failed directory is not complete evidence. `no-embedded-text-found-review-upstream` means upstream text and terms are required, not that the module has no license obligations.

After successful commands, save the APK hash, source manifest, version, dependency graph, and notice evidence in a separate distribution record. A phone must also confirm that Settings → About Pactick opens the list and displays native, font, data, and asset entries. File checks establish packaged bytes only, not device access or readability.

## Recapturing after dependency/source changes

Run the generator from the project root, replacing sample paths with actual caches:

```sh
python3 scripts/generate_third_party_notices.py \
  --go-cache /path/to/go/pkg/mod \
  --pub-cache /path/to/pub-cache \
  --flutter-sdk /path/to/flutter \
  --go-sdk /path/to/go \
  --gradle-cache /path/to/gradle/caches/modules-2/files-2.1 \
  --android-inventory artifacts/android-runtime-dependencies.json
```

Without this build's runtime graph, omit the last argument, but generated cached-POM status remains `cache-POM-only-not-confirmed-in-app` and cannot support final distribution acceptance. With an inventory, only a complete schema 2 `releaseRuntimeClasspath` graph containing resolved binaries is accepted. The generator overwrites indexes and updates captured texts but does not automatically delete old license files; remove unused evidence according to the current index after removing components.

Single-line and grouped Go `require` declarations are supported. Dart hosted sources are restricted to `https://pub.dev`; SDK components are captured separately. There is no capture logic yet for Go `replace`/`exclude`, Dart git/path, or other hosted sources. Such declarations fail the command; add provenance capture and version verification before introducing them.

Empty POM licenses require parent-POM or upstream checks. The current Apache-2.0 declaration for `com.google.guava:listenablefuture:1.0` comes from the verified [parent POM](../third_party/metadata/guava-parent-26.0-android.pom). Four Flutter-engine modules map to the complete engine statement after their commit IDs match SDK `engine.stamp`, while retaining the status that they lack direct POM declarations. These mappings establish provenance only and do not replace final notice checks.

After adding a license, upstream NOTICE, asset conversion, or runtime version, maintainers must review applicable terms again, update evidence in the supplemental asset and `distribution-notices.json`, and run all checks for the current candidate. See [client asset sources](ASSET_SOURCES.en.md) for provenance, conversion records, and current distribution scope.
