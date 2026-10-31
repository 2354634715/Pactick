[简体中文](BUILDING.md) | English

# Build from source

This document describes building the Android client, Go API, and Windows/Linux local server tools. The current candidate source version is `0.3.0-preview.3+8`; use `client/pubspec.yaml` from the selected release commit when building.

Current Android source includes priority sorting, plan editing, count and timed reminders, free focus with task association after ending, focus vibration, strict mode, the private task vault, language selection, system calendar connections, and the optional focus desktop. `flutter pub get` fetches locked dependencies including the vault's `cryptography` package. Display headings use Noto Serif SC from the source tree, without a runtime font download. Building requires no external notification or calendar service. A debug build verifies compilation and packaging only; it does not prove reminders, permissions, calendar providers, the focus desktop, vibration, screenshot protection, or background recovery.

Local server management and administrator tools have separate Go build entry points. See [server management](SERVER_MANAGEMENT.en.md) for the four targets and dependencies. See [project status](PROJECT_STATUS.en.md) and the [roadmap](../PROJECT_PLAN.en.md) for feature status and acceptance limits.

## 1. Check the build environment

| Tool | Currently verified baseline |
| --- | --- |
| Go | CI uses 1.26.4; `go.mod` declares 1.25.0 and dependencies may require a newer version |
| Flutter | 3.47.4 stable, Dart 3.13.3; pubspec requires Dart ≥3.13.2 |
| Java | JDK 21 |
| Android | Android SDK, platform tools, and accepted SDK licenses; minimum Android 8.0 (API 26), with compile and target SDKs determined by Flutter and Gradle configuration |
| Python | 3.10+, standard library only |
| PostgreSQL / Docker | See [SELF_HOSTING.md](SELF_HOSTING.en.md) for self-hosting and integration environments |

Check installed versions using `go version`, `flutter doctor -v`, and `java -version`. Initial dependency and Android toolchain downloads require network access. `go.sum`, `pubspec.lock`, and Gradle configuration constrain dependency versions. Lockfiles do not replace the final resolved Android dependency inventory.

## 2. Build the server

Run from the repository root:

```sh
go mod download
go mod verify
go test ./...
go vet ./...
go build ./cmd/...
```

PostgreSQL integration tests read `PACTICK_TEST_DATABASE_URL`. Without it, `TestPostgres` tests skip. When set, connection, permission, or migration failures fail the tests. Each scenario creates and later drops a separate schema; the connection user needs schema create/drop permission. Use a dedicated test database, never a production connection.

With a temporary PostgreSQL instance available, run the following from the repository root. Match the example address and credentials to that instance:

```sh
PACTICK_TEST_DATABASE_URL='postgres://pactick:pactick@localhost:5432/pactick_test?sslmode=disable' go test -count=1 ./internal/account ./internal/auth ./internal/database ./internal/sync
```

In PowerShell, first run `$env:PACTICK_TEST_DATABASE_URL = 'postgres://pactick:pactick@localhost:5432/pactick_test?sslmode=disable'`, then the same `go test` command. Tests control real transaction ordering to check account cursor commit order, mutual exclusion of migration and synchronization writes, historical application-ID cleanup, concurrent changes during export, originating-device control restrictions, first task association for a terminal focus session, and login/device-registration state after local account provisioning. The GitHub Checks workflow uses a PostgreSQL 17 service and sets this variable. A local pass without it does not mean database scenarios were verified.

Start the server and create an account using the [self-hosting guide](SELF_HOSTING.en.md).

## 3. Build an Android development package

```sh
cd client
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug
```

The output is `client/build/app/outputs/flutter-apk/app-debug.apk`. Debug packages use a development certificate and are for testing only. First launch opens a local workspace; configure a self-hosted server under synchronization settings when needed.

The repository excludes `android/local.properties`; Flutter generates local SDK paths before building. If characters such as `&` in Windows paths cause Gradle startup failures, copy the source to a clean directory without those characters and build there.

## 4. Build a production package

If no long-term signing key exists, first complete key generation and independent backup verification under [creating and backing up a signing key on Windows](ANDROID_SIGNING.en.md), then configure the build.

On the local build machine, configure `key.properties` and a long-term production keystore using `client/android/key.properties.example`, then run:

```sh
cd client
flutter build apk --release --dart-define=RELEASES_URL=https://github.com/OWNER/REPOSITORY/releases
python3 ../scripts/verify_apk_notices.py build/app/outputs/flutter-apk/app-release.apk
```

Replace `OWNER/REPOSITORY` with the reviewed release repository. Missing signing configuration fails the release build. A self-signed version cannot directly replace an official version signed by another certificate. Export and verify a backup before migration. Preserve a recoverable copy before resolving signing conflicts; do not first uninstall the client holding the only data copy.

The APK check above also verifies the bundled font's original bytes and the `PactickDisplay` mapping to its regular 400 weight. Missing fonts/manifests or mismatched hashes fail. If Flutter is not on PATH, provide the engine license with `--engine-license /actualFlutterSDK/bin/cache/pkg/sky_engine/LICENSE`. See [asset sources](ASSET_SOURCES.en.md#framework-icons-and-fonts) for font provenance and licensing.

See [releasing](RELEASING.en.md) for the signed-candidate workflow, checksums, certificate fingerprints, and device acceptance. Every source change affecting binaries requires a new snapshot, build, and signature from a fixed commit. An old APK paired with a new source archive is not a replacement. See Flutter's official [Build and release an Android app](https://docs.flutter.dev/deployment/android) for signing documentation.

Gradle defaults to a maximum 2 GiB heap, 1 GiB metaspace, and two workers. Builds also start Dart, Kotlin, and other tools requiring additional memory. For JVM native-memory allocation failures, inspect available memory and swap. Override parameters for the current build through `-Dorg.gradle.jvmargs="..."` in `GRADLE_OPTS`. See [Gradle build environment](https://docs.gradle.org/current/userguide/build_environment.html) for precedence.

## 5. Generate a public source snapshot

```sh
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/verify_third_party_notices.py
python3 scripts/verify_supplemental_notices.py
python3 scripts/prepare_public_source.py --check
python3 scripts/prepare_public_source.py ../pactick-public
```

The destination must not exist. The tool copies allowlisted source, tests, migrations, lockfiles, public documentation, and templates without deleting or modifying the source directory. `SOURCE_MANIFEST.json` records each file's size and SHA-256. Eligible text is normalized to LF; PNGs, JARs, TTFs, and other files whose original bytes are preserved by the script do not undergo newline replacement. Executable permissions are retained.

Only `client/assets/fonts/NotoSerifSC.ttf` is allowed as a font export, with exact SHA-256 `050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9`. `.gitattributes` marks TTF files as binary. Copies, snapshots, and archives must preserve their bytes. CRLF-to-LF replacement corrupts this font's original bytes; updating manifest or review hashes must not admit an unreviewed replacement. Replacing or subsetting this font requires reviewing its provenance, license, notices, and the corresponding export/APK verification rules.

`verify_third_party_notices.py` reads only source and evidence. It checks Go/Dart versions in notices, local license-text hashes, required SDK/font/Gradle-wrapper records, and completeness of Android POM records. On failure, recollect and review evidence according to [third-party review](THIRD_PARTY_AUDIT.en.md); do not change hashes merely to bypass differences. This command confirms neither legal compatibility, asset rights, nor every final-APK notice obligation. Both Checks and signed-candidate workflows run it.

`verify_supplemental_notices.py` checks reviewed supplemental assets, component versions, full original notices, required acknowledgments, and icon/font/wrapper source hashes. `verify_apk_notices.py` additionally checks the final APK's project license, all Flutter engine text, supplemental asset bytes, and the font binary/family mapping when source declares or provides Noto Serif SC. Missing content or differences fail. When dependencies or assets change, recheck the relevant version's terms, update assets and review records, then rebuild. Updating hashes alone does not replace terms review. See [third-party review](THIRD_PARTY_AUDIT.en.md) for runtime-dependency-graph verification parameters.

The tool scans known credential forms, real public IPv4 addresses, and private Windows user paths, and extracts prohibited addresses from local historical deployment instructions. Sensitive configuration assignment rules cover the actual `AUTH_JWT_SECRET`, database passwords, token hash keys, and Android signing passwords/Base64 keys. They recognize values at least 32 characters long, shell/env and YAML assignments, quotes, whitespace, and LF/CRLF. Declared development examples and replacement placeholders are exempt; short passwords and other forms may still escape detection. Add one private prohibited value per line through `--private-terms /path/to/local-only-terms.txt`. Scan errors report only file and rule, without echoing credentials. These are heuristic checks and cannot recognize all credentials. Before publication, manually review images, the Gradle wrapper JAR, potentially missed credentials, and all public text.

In the new directory, rerun the Go and Flutter checks, verify the manifest, and initialize a new Git repository. Update the script's allowlist when adding source directories or public documents.
