[简体中文](RELEASING.md) | English

# Releasing source and Android candidates

The official repository is [2354634715/Pactick](https://github.com/2354634715/Pactick). Release artifacts are distributed through its [Releases](https://github.com/2354634715/Pactick/releases); see [SECURITY.md](../SECURITY.en.md) for security reporting. Published `v0.3.0-preview.1` includes an Android APK and Windows/Linux x86-64 server packages. Later releases' actual platforms and attachments are determined by their own Release pages; they do not automatically inherit a previous artifact scope. Preview distribution does not yet constitute a recommendation for public-network self-hosting.

Source previews, APK downloads, and self-hosting recommendations proceed under their separate completion conditions below. Public source must state unverified database, APK, device, and deployment scenarios. Publishing source does not establish that these checks are complete.

Agents preparing or performing Release tasks must read and strictly follow the [Agent Release specification](AGENT_RELEASE_SPEC.en.md), including authorization, source provenance, attachments, and publication state. Release bodies and attachments contain only its standard content. Other items require the user's explicit instruction that the specific item must be included in this Release. Raw JSON is not published directly by default.

## 1. Review public source

1. Update `CHANGELOG.md` and the client version/build number; confirm that database migrations are compatible with the previous version.
2. Update [third-party notices](../THIRD_PARTY_NOTICES.en.md) and resolve unfinished items in the [audit checklist](THIRD_PARTY_AUDIT.en.md).
3. Run `python3 scripts/prepare_public_source.py NEW_DIRECTORY` and manually review everything listed by `SOURCE_MANIFEST.json`.
4. Run the [complete build checks](BUILDING.en.md) in the new directory and confirm that builds do not depend on files or configuration in the original private workspace.
5. Before publication, confirm the project license text and copyright ownership, official repository address, private security-reporting route, and release page. Historical deployment and commercialization materials stay in the original private directory.

Do not upload the entire old workspace first and then rely on `.gitignore` to exclude private material. New ignore rules do not remove tracked files from Git history.

## 2. Configure signing

Maintainers creating a key for the first time must follow the [Windows signing guide](ANDROID_SIGNING.en.md), generating it and verifying a backup on their own computer. Keys and passwords must not be supplied through chat or a public repository.

Create the GitHub Environment `android-release` in the actual release repository, restrict it to the default branch, set required reviewers, and configure:

| Secret | Content |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the stable production keystore file |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Production signing key alias |
| `ANDROID_KEY_PASSWORD` | Key password |

Maintain a key backup in a separate protected location. Do not put it in the repository, issues, logs, source snapshots, or ordinary PR environments. Do not casually regenerate an existing app's production key; doing so may change its signature.

Ordinary `.github/workflows/checks.yml` runs Go checks and Flutter analyze/test/debug build; PRs do not use signing keys. `.github/workflows/android-release.yml` can only be manually triggered from the default branch, uses an existing version tag, and builds a signed candidate after environment approval. Maintainers must first review the tagged source and build scripts. See GitHub's [manual workflow documentation](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).

## 3. Generate candidate artifacts

Create a version tag for a checked commit, for example `v0.2.0-preview.1`. Manually run **Build signed Android candidate** from the default branch with that tag.

After checking out the tag, the workflow creates an allowlisted snapshot. `verify_third_party_notices.py` checks notices against current locked Go/Dart versions and verifies the SHA-256 of listed local license texts, upstream evidence, and embedded notices. Missing text, stale versions, or unconfirmed Android POM records stop the build. This does not establish asset rights or license compatibility.

Before injecting signing keys, `verify_release_source.py` checks that the tag matches the version in `client/pubspec.yaml` (without `+buildNumber`), the Android build number is positive, root and client license files are byte-identical, and every manifest file's size and SHA-256 match. After Flutter checks it runs again with `--expected-metadata artifacts/RELEASE_SOURCE.json`, comparing every item with provenance metadata recorded before archiving. Failure stops the workflow before signing.

The source tar.gz is generated before dependency tools or signing configuration enter the build directory. Flutter checks, signed builds, and APK notice checks run in the same snapshot. After building, manifest files and pre-archive provenance metadata are verified again. Candidates are not uploaded if source files, lockfiles, or the manifest changed. The keystore stays outside the snapshot, and temporary `key.properties` is excluded from the already generated source archive. Both are cleaned when the workflow exits.

The generated Actions artifact contains the APK, source tar.gz, `SOURCE_COMMIT.txt`, `RELEASE_SOURCE.json`, `SHA256SUMS.txt`, signing certificate fingerprint, toolchain version records, original third-party licenses, and change notes. `RELEASE_SOURCE.json` records the commit, tag, client version, build number, and license/manifest hashes. Toolchain records include actual Flutter, Dart, Java, Go, and `apksigner` versions; dependency lockfiles accompany source. The workflow uploads candidate artifacts only and does not create a public Release.

Actions artifacts support candidate review; their complete contents are not the Release attachment list. Agents must select standard attachments under the [Release specification](AGENT_RELEASE_SPEC.en.md) and regenerate `SHA256SUMS.txt` for the final uploaded names and file set. Provenance, toolchain, runtime-dependency, and distribution-review JSON stays in maintenance materials by default and is not pasted into the Release body or uploaded separately. Required JSON and the manifest inside source archives retain their existing structure. Additional files or descriptions may be published only when the user explicitly requires that particular item for this Release.

After signing, the workflow resolves `releaseRuntimeClasspath` again, compares current module coordinates with third-party notices and reviewed supplemental assets, and captures current modules, AAR/JAR hashes, and embedded LICENSE/NOTICE into `android-native-evidence/`, associated with the final APK SHA-256. `verify_apk_notices.py` checks the project license, every Flutter engine notice, and supplemental assets. `verify_supplemental_notices.py --android-inventory ... --apk ...` additionally requires current modules to match the reviewed list. Version changes, missing original text, or mismatched APK assets fail checks and prevent candidate upload.

`completed_legal_audit: false` in captured files means the collector supplies evidence only. After reviewing terms, attribution, and exclusions from the project license, maintainers record applicable distribution scope, source commit, final APK SHA-256, certificate, corresponding runtime binaries, and notice-check results in a separate `DISTRIBUTION_REVIEW.json`. This record applies only to the listed artifacts. Changes to dependencies, assets, or distribution scope require another review. AAR/JAR files without embedded text still require upstream verification; their licenses cannot be omitted on that basis. See the [third-party audit](THIRD_PARTY_AUDIT.en.md) for terms and evidence requirements.

Before publishing, verify the APK using the Android SDK's `apksigner verify --verbose --print-certs`. Put its SHA-256 and certificate SHA-256 fingerprint in the Release description. Checksums must refer to the exact final uploaded file. The client opens the release page in an external browser; it does not automatically verify APK integrity or signing certificates. Release notes must describe that limitation accurately.

## 4. Android installation and data migration

The current application ID is `com.example.pactick`. The former `com.example.planfocus` uses separate Android data storage. The new package installs independently and cannot obtain the old package's SQLite database, settings, or credentials automatically through an in-place update.

If the old package still runs, export a backup there and keep the old app, then import into the new package. Import creates an independent local workspace without server addresses, credentials, cursors, or device registration and does not upload automatically. Verify tasks, projects, plans, focus history, and unsynced changes against the original before separately choosing whether to connect a server. See [local backups](LOCAL_BACKUPS.en.md) for formats and limits. If the old package has no compatible export entry or the backup format is unsupported, keep the old app and the only copy of its data until migration tooling and restore verification are complete. Installing the new package does not complete migration.

Later in-place updates of `com.example.pactick` require the same package name and production signing certificate and a higher Android build number. Acceptance must install the previous same-package artifact, create local data and unsynced changes, install the candidate over it, and verify retention. Android normally rejects an update signed with a different certificate. Verify a backup before migrating through restore; uninstalling deletes the original app's data.

## 5. Staged release acceptance

### Source preview

- [x] The owner confirmed the current license terms; root and client copies match and attribution is “王辰昊 Wang Chenhao”.
- [ ] Public files, asset sources, and corresponding third-party notices have been reviewed. Icons with unconfirmed sources must not be marked passed.
- [ ] Go, Flutter, Python, and third-party evidence checks pass in the final clean snapshot; the manifest and actual Git file set are checked.
- [ ] The repository, Issues, Releases, and private reporting email work; author information and private content have been manually checked.
- [ ] Preview notes list unverified scenarios, known limits, and Source Available conditions, without claiming APK or public-network deployment acceptance.

### Android preview APK

Complete these checks in addition to the source-preview conditions. APKs may be published after source. A successfully built candidate artifact is not authorization for public distribution.

- [ ] Go/Flutter checks and clean-source builds pass.
- [ ] PostgreSQL integration scenarios actually run and pass, and remote Checks pass. Skips caused by an unset test connection are not database acceptance.
- [ ] Device first launch, offline tasks/focus/statistics, backup export, and restore work.
- [ ] Default priority ordering, Today exceptions, and default-on task reminders, counts, permissions, channels, workspace changes, notification tapping, reboot, and updates pass the [specialized checklist](ANDROID_TASK_REMINDER_CHECKLIST.en.md).
- [ ] Independent installation and export/restore migration from the old package to `com.example.pactick` pass. Keep the original app and backups until verification finishes.
- [ ] Later same-package, same-signature in-place updates preserve data and unsynced changes. Package/certificate changes use backup-restore migration.
- [ ] Identical user IDs on two self-hosted servers do not mix data, tokens, sync queues, or cursors.
- [ ] Disconnection, token expiry, service failure, and incompatible sync versions do not block local functions.
- [ ] Two-device sync, deletion, and conflict scenarios meet the contracts.
- [ ] APK source tags, signing certificate fingerprint, SHA-256, and third-party notices are present.
- [ ] Actual Android runtime dependencies, embedded licenses, fonts, and icon sources have been reviewed.
- [ ] The production repository URL, Releases entry, and private vulnerability-reporting address are configured and verified.
- [ ] All public files and images have passed manual privacy review.

Maintainers publish the corresponding source or artifacts after each stage meets its conditions. See the [Android getting-started guide](GETTING_STARTED.en.md) for operations and current limits and [asset-source verification](ASSET_SOURCES.en.md) for asset evidence.

On 2026-10-11, `0.2.0-preview.1+5` passed local static analysis, 151 client tests, and a debug APK build. These results do not check off formal signing, device, or public-distribution conditions. The `+3` and `+4` signed candidates from 2026-10-02 retain their original-version results and exclude the current sorting/reminder changes. Later final signed packages must be rechecked with accurate provenance, build number, hash, and certificate.

### Self-hosting recommendation

The first round does not promise that public-network deployment is ready to recommend. Before adding that scope, complete clean installation, upgrades with existing data, failure handling, scheduled backup, isolated restore, and new-host restore on real Ubuntu/Debian. HTTPS additionally requires actual certificate issuance, renewal drills, reload, and public HTTPS/WSS results. See the [release acceptance plan](RELEASE_AND_PROMOTION_PLAN.en.md) for operations and completion conditions. Client two-device and server-isolation checks remain part of the APK acceptance above.

Retiring a personal server is a separate operation and must follow completed personal-data migration and successful restore verification.
