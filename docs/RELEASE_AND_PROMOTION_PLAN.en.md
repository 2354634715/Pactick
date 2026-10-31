[简体中文](RELEASE_AND_PROMOTION_PLAN.md) | English

# Pactick release acceptance and social-media promotion plan

Updated: 2026-10-31. Current source: `0.3.0-preview.3+8`. Android application ID: `com.example.pactick`. Historical candidates/checks retain their own versions and do not establish results for current artifacts.

This plan records validation operations and completion criteria for new candidates, and the information, assets, channels, and feedback arrangements needed for social-media promotion. It is intended for maintainers and acceptance testers.

Tasks and recommendations here do not mean the work has been performed. Record the corresponding source commit, artifact hash, environment, date, and logs for acceptance results. Reassess applicability after version, artifact, or important configuration changes.

The first round is a source preview and Android preview APK; public-network self-hosting is not yet recommended. The official repository is [2354634715/Pactick](https://github.com/2354634715/Pactick), distribution uses its [Releases](https://github.com/2354634715/Pactick/releases), and private security reports go to `w66610@outlook.com`. Links and email are documented, but reachability and receipt still require live verification. Source, APKs, and future self-hosting recommendations follow separate conditions in the [release process](RELEASING.en.md).

## 1. Historical results and execution order

The following early-stage records refer to their dated artifacts, not the current candidate. Current integrated features are listed in [project status](PROJECT_STATUS.en.md). New candidates must pass their own checks and retain unverified device/deployment items; old counts and APK hashes are not reusable results.

As of 2026-10-11, current source adds default priority ordering and default-on task reminders in the notification area. General task lists use Urgent → High → Medium → Low → None; Today retains planned times and manual order. With open tasks and notification permission, one ongoing silent reminder displays the count. It does not schedule by deadline or plan block. The private task vault, Windows/Linux x86 server GUI, and one-click administrator account creation were planned at that time and are now implemented; see [project status](PROJECT_STATUS.en.md).

Local static analysis reported no issues, 151 client tests passed, and a complete Android debug APK build passed. This `0.2.0-preview.1+5` package uses the Android Debug certificate and SHA-256 `87FD2A10C5B475E670F2AB532BE4CC3795C9456EE4AC2D9CE0E68789522D47B5`. See the [roadmap](../PROJECT_PLAN.en.md) for source/build scope. This round did not connect devices, rebuild a production-signed candidate, or publish publicly. [Device checks](ANDROID_TASK_REMINDER_CHECKLIST.en.md) for new ordering/notifications remain pending. Older signed candidates lack these features and do not cover modified source.

The following 2026-10-01 and 2026-10-02 records describe their historical source, candidates, and environments. Test counts, signatures, hashes, and license reviews must not be transferred to the `+5` debug package or later formal candidates.

The 2026-10-01 fixes addressed seven confirmed review issues: sync cursor commit ordering, cleanup of historical app-identifier copies, upgrade-configuration commit timing, UI state after save failure, database-open retry, consistent account export, and sensitive-configuration scanning. Originating-device focus restrictions, native-service recovery, and signed-candidate/source correspondence checks were also implemented.

These were existing local results recorded that day, not new acceptance performed by this document:

| Check | Recorded result | What it does not establish |
| --- | --- | --- |
| Go | Dependency verification, full tests, vet, and command builds passed in an independent source snapshot | Real PostgreSQL scenarios |
| PostgreSQL | Six top-level integration tests compiled but skipped without a test connection | Actual database transaction ordering, migration, and export results |
| Flutter | Independent snapshot analyze clean; 104 tests passed | Device behavior and complete candidate APK |
| Python release scripts | 14 regressions and allowlist scan passed | Manual privacy review of all files |
| Deployment scripts | Syntax, simulated installation, and upgrade-failure cases passed | Real Linux installation, upgrade, and restore |
| Kotlin | Native-code compilation passed while skipping Flutter build tasks | Complete APK build/installation |
| Android native dependencies | 75 modules and 74 selected binaries resolved; seven embedded texts captured | Full final-signed-APK license review; 67 binaries still needed upstream review |
| Source snapshot | That day's snapshot included 337 allowlisted files plus a manifest | Final file set after later changes and actual Git staging |

The native-notice capture drill then used an old debug APK; its hash does not establish a later signed candidate. Specialized Kotlin compilation does not replace a full Flutter APK build. As of 2026-10-01, there was no validated production-signed APK, public repository, or public-network deployment result.

Progress before the 2026-10-02 signed-candidate build:

| Item | Result | Remaining limitation |
| --- | --- | --- |
| Project license | Owner confirmed existing terms/public attribution; both copies synchronized and FAQ status updated | Not third-party compatibility review |
| Distribution entry | Repository, Releases, Issues, and reporting email documented. GitHub connector confirmed access; repository was private and empty | No public source/artifacts uploaded; no test email or receipt verification |
| Client | Four-hour task-slider issue fixed; new GUI analyze clean, 135 tests passed, debug APK built; local GUI implementation records kept in maintenance workspace | Signed-candidate and device acceptance recorded separately |
| Backend | Dependency verification, full tests, vet, and command builds passed in an independent copy | Six real PostgreSQL tests/database subcases skipped; related operations stopped after Docker startup failure |
| Release tooling | 26 Python regressions passed after adding interactive local signing setup; earlier syntax checks passed for two workflow YAML files and 14 Bash steps | Remote CI not run |
| Distribution evidence | Fixed provenance comparison before/after builds, locked dependency and original-license hash checks added; current 103 components/75 Android metadata records verified | Existing local runtime-graph matches do not establish this signed APK; legal/notice review pending |
| User material/assets | Getting started updated for new GUI; 13 PNGs/7 drawable XML files inventoried, branding generation/conversion verified | Focus notification author/upstream unconfirmed; inventory is not final license review |
| Signing preparation | Maintainer created long-term JKS; `pactick` is a private-key entry; [local configuration script/guide](ANDROID_SIGNING.en.md) provided | Independent backup, passwords, final signed-APK verification pending |

Local logs are under `output/release-validation-20261002/` and do not ship with public source. Check copies were generated at different times; regenerate the final snapshot and compare runtime-affecting files against test subjects. Earlier file counts are historical, not fixed final totals.

A later signed candidate was built, still version `0.2.0-preview.1+3`. Fixed provenance was an independent 362-file snapshot at local commit `f40065691bd2c1e9581cf93d3d4acafd8333b9a6`; commit/tag had not been pushed. Its signing certificate matched the maintainer's long-term key. Post-build provenance comparison, 135 Flutter tests, 26 Python regressions, and complete packaged project/engine license checks passed.

An isolated local PostgreSQL 17.11 completed six real integration groups, with 10 passing test nodes and no skips. Full Go tests with the database had 74 passing nodes; only the Windows upgrade shell harness was expected to skip, and its simulated cases passed through Git Bash. Nineteen real loopback API HTTP checks covered registration/login, sync between two device registrations, conflicts, tombstones, account isolation, and sign-out. Temporary API/database were stopped. No Docker repair or personal database connection was attempted. These results do not replace formal-APK phone HTTPS/WSS or two-device checks.

Candidate artifacts, fixed source, and local evidence are under `output/signed-candidate-20261002/`. Final APK SHA-256: `5a74b141e7723dd865f721718e38557a65cb9d2905acebe893682e23ace14f90`. As of 2026-10-02, this candidate still required phone acceptance, independent signing-key backup, actual client sync, focus-notification provenance/final notices, remote CI, and public release. The source archive retains build-time contents. Later maintenance-document changes are not source already built into that APK. Current tasks follow this document's active checklist.

Suggested order:

1. Confirm licensing, copyright, and asset provenance; decide repository/feedback entries.
2. Review clean source; run PostgreSQL and remote CI checks.
3. Build a signed candidate and review final third-party notices.
4. Perform Android-device, Linux deployment, upgrade, backup, and restore acceptance.
5. Complete user guides, promotion material, and a unified entry, then run a limited trial.
6. Update acceptance status, publish reviewed source and matching artifacts, then expand promotion channels.

Account preparation, demonstration material, and development-progress content can proceed alongside acceptance. A source preview may be published once its own conditions are met; APK downloads must still satisfy the [release process](RELEASING.en.md). Real Linux installation, restore, and public-network verification remain prerequisites for later self-hosting recommendations.

## 2. Remaining release work and procedures

### 2.1 Confirm the formal project license

On 2026-10-02, the owner confirmed retaining the current [LICENSE](../LICENSE) terms with attribution “王辰昊 Wang Chenhao”. Root and `client/LICENSE` now contain synchronized final text. Source Available positioning is unchanged.

Later changes to terms/copyright require reconfirming rights and contributions, updating both copies and the [license FAQ](LICENSE_FAQ.en.md). Release scripts check text consistency.

Project-license confirmation and third-party compatibility review are separate records. This confirmation does not establish all asset rights, dependency compatibility, or professional legal review. Those still follow the items below.

Current result: project terms/attribution confirmed and both texts match; third-party/asset review proceeds separately.

### 2.2 Confirm icon, illustration, font, and other asset sources

Existing files alone do not prove distribution rights. Inventory assets actually included in final source/APKs, recording path, author/source, original link, license, attribution requirements, and authorization evidence.

The 2026-10-02 [asset-source check](ASSET_SOURCES.en.md) confirmed current branding came from image generation and later conversion. The current client distributes 13 PNGs and seven drawable XML files. Focus-notification author/upstream records were still missing. Old launcher vectors were removed; historical snapshots do not ship in this release.

Prioritize Android launcher sizes and actual illustrations, fonts, screenshots, and sample data. Retain original projects or author confirmation for original assets and the applicable acquisition-time license for third-party assets. Replace unconfirmed sources with clearly licensed files or exclude them.

Recreate screenshots with demo accounts/data and inspect notification bars, personal tasks, server addresses, and image metadata. Include necessary attribution, copyright, and licenses in corresponding distributions.

Completion: every shipped asset has verifiable provenance and complete notices, and public screenshots contain no personal data.

### 2.3 Configure the official repository and security-reporting entry

Repository, email, and Releases addresses are set in this introduction and [SECURITY.md](../SECURITY.en.md). External availability has not been verified; no push has been performed.

1. Verify ownership, visibility, default branch, and actual contents of `2354634715/Pactick`; use an independent private repository for private acceptance if needed.
2. Verify [Issues](https://github.com/2354634715/Pactick/issues) and [Releases](https://github.com/2354634715/Pactick/releases) access; configure security reporting under [SECURITY.md](../SECURITY.en.md).
3. Manually verify email receipt and maintainer notifications using demo content only, without real vulnerabilities or sensitive data.
4. Confirm the distribution entry is the actual repository's `/releases`. The signing workflow derives `RELEASES_URL` from the repository name; local builds require it explicitly.
5. Once public, enable GitHub Private vulnerability reporting and security notifications if appropriate. It targets public repositories; do not assume private acceptance repositories provide it. See [GitHub guidance](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository).

Completion: correct documented links, deliverable private reports, and the final APK's View releases opens the correct page.

### 2.4 Review final public source and Git files

Automated scans do not replace manual review of all public text, images, and JARs. Regenerate snapshots after licensing, documentation, or distribution changes. The previous 337-file scope is not a future fixed total.

Run from the original project root with Python 3.10+:

```powershell
python scripts/prepare_public_source.py --check
python scripts/prepare_public_source.py output/public-source-release
```

The target must not exist. Use `python3` on Linux. Resolve reported files/rules and regenerate after scan failure; do not bypass checks.

1. Review every distribution file against the new directory's `SOURCE_MANIFEST.json`.
2. Check example configuration, comments, documentation, images, and Gradle wrapper JAR for real keys, private deployment addresses, and personal details.
3. Initialize Git only in the clean snapshot. Do not copy historical archives, caches, deployment configuration, or other Git history.
4. After staging, inspect actual contents and authorship:

```bash
# Run in the newly generated clean source directory
git init -b main
git add .
git diff --cached --name-only
git diff --cached --stat
git diff --cached
```

Initialization/staging supports review; this step does not push. Create a distribution commit only after checks. Copies containing test caches/build outputs cannot serve directly as distribution directories.

Completion: manifest, manual-review scope, and actual Git files agree. Results do not extend to unreviewed old APKs, archives, remotes, or history.

### 2.5 Actually run PostgreSQL integration tests and remote CI

Requires Docker, Go, and a dedicated test database permitting schema creation/deletion. Never use production credentials. The following test password is only for a temporary loopback-bound instance.

Start PostgreSQL 17 on the Linux acceptance host:

```bash
docker run --detach --rm --name pactick-pg-integration \
  --publish 127.0.0.1:15432:5432 \
  --env POSTGRES_DB=pactick_test \
  --env POSTGRES_USER=pactick \
  --env POSTGRES_PASSWORD=pactick \
  postgres:17

docker exec pactick-pg-integration pg_isready \
  -U pactick -d pactick_test
```

If not ready, wait and retry. Once accepting connections, run from release-source root:

```bash
export PACTICK_TEST_DATABASE_URL='postgres://pactick:pactick@127.0.0.1:15432/pactick_test?sslmode=disable'

go test -count=1 -v -run '^TestPostgres' \
  ./internal/database ./internal/sync ./internal/account

go test -count=1 ./...
```

In PowerShell:

```powershell
$env:PACTICK_TEST_DATABASE_URL = 'postgres://pactick:pactick@127.0.0.1:15432/pactick_test?sslmode=disable'
go test -count=1 -v -run '^TestPostgres' ./internal/database ./internal/sync ./internal/account
go test -count=1 ./...
```

The six top-level tests cover:

- App-identifier cleanup in historical policies, sync logs, idempotent results, and conflict copies.
- Same-account cursor commit ordering and pagination completeness.
- Migrations waiting for in-progress sync writes.
- One consistent snapshot for user, devices, and entities during export.
- Errors when exporting a nonexistent account.
- Focus control restricted to the originating device.

After testing, remove only this dedicated container:

```bash
docker rm --force pactick-pg-integration
```

Then run Checks from `.github/workflows/checks.yml` in the private acceptance repository. Confirm Go, deployment scripts, Flutter analyze/test, and complete debug APK builds pass. The workflow already has PostgreSQL 17 and a test connection, but configuration is not successful execution.

Completion: all six tests PASS without missing-connection SKIP, remote Checks succeeds, and full logs, tool versions, and commit are saved.

### 2.6 Build and verify a formally signed candidate APK

Requires a reviewed distribution commit, Android toolchain, and long-term production signing key. Continue using an existing key; create one only for the first release. Keep it outside the repository, independently backed up in protected storage, and verify readability. Certificate identity information ships with the APK and must be reviewed on creation. See [Android signing](https://developer.android.com/studio/publish/app-signing).

In GitHub Settings → Environments, create `android-release`, restrict the default branch, and set review rules according to available features. Configure four environment secrets:

| Secret | Content |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 of production keystore |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Production key alias |
| `ANDROID_KEY_PASSWORD` | Key password |

Private-repository environment/review capabilities depend on the GitHub plan; do not assume all accounts support them. Check actual capabilities against [GitHub environment documentation](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments). If the required environment is unavailable, build on a controlled Linux host following the [build guide](BUILDING.en.md) and retain equivalent evidence. This does not authorize early publication of unreviewed source.

Candidate workflow:

1. Verify version and positive build number in `client/pubspec.yaml`. Current version is `0.2.0-preview.1+5`; an example tag is `v0.2.0-preview.1`, without `+5`. Do not overwrite/reuse existing tags or released build numbers.
2. Tag a commit with passing Checks; never overwrite a released tag.
3. Manually run Build signed Android candidate from the default branch using the reviewed tag.
4. Download the artifact and verify APK, source tar.gz, commit/version data, toolchain, third-party evidence, certificate fingerprint, and checksums.

Before signing injection, the workflow validates versions, root/client licenses, and manifest; checks/builds in one snapshot; then compares source files again. The source archive precedes signing configuration. Private keystores and temporary `key.properties` must not enter it.

For local builds, configure signing from `client/android/key.properties.example`. Run from the candidate snapshot's `client` directory:

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --release \
  --dart-define=RELEASES_URL=https://github.com/OWNER/REPOSITORY/releases
```

Replace `OWNER/REPOSITORY`. Local builds must use the distributed-source snapshot and retain equivalent provenance, version, toolchain, and signing evidence. For Windows paths with `&` or similar characters, use a clean directory without them or a Linux build host.

Verify the final APK with Android SDK tools:

```bash
apksigner verify --verbose --print-certs pactick.apk
sha256sum pactick.apk
```

`pactick.apk` is the final upload file. Local builds default to `client/build/app/outputs/flutter-apk/app-release.apk`. See [apksigner](https://developer.android.com/tools/apksigner).

Completion: valid signing, certificate matching the production key, matching artifacts/source, and recorded final APK SHA-256/certificate fingerprint.

### 2.7 Review final-APK third-party licenses and NOTICE

Captured evidence does not replace review of terms for actually distributed components. Resolve runtime dependencies again for the final signed candidate and capture its binaries/notices.

After Flutter dependency resolution, run from the candidate source's `client/android`:

```bash
./gradlew -I ../../scripts/android-dependencies.init.gradle \
  :app:writeRuntimeDependencyInventory
```

Return to source root and run; the capture target must not exist:

```bash
python3 scripts/capture_android_notices.py \
  artifacts/android-runtime-dependencies.json \
  client/build/app/outputs/flutter-apk/app-release.apk \
  artifacts/android-native-evidence

python3 scripts/verify_apk_notices.py \
  client/build/app/outputs/flutter-apk/app-release.apk
```

1. Check licenses, copyrights, and NOTICE for actual versions; POM license names alone are insufficient.
2. Obtain applicable evidence from official source/distributions for `no-embedded-text-found-review-upstream` items.
3. Confirm required notices are available in the APK license page or accompany the package as terms require. Existing APK verification checks the complete project license and Flutter engine text, not every Maven component obligation.
4. Review special terms against the custom project license; replace components or obtain suitable authorization where necessary.
5. On a device, open Settings → About Pactick and confirm access to the license page. Current code calls `showLicensePage` directly, without an intermediate View licenses step.
6. Review build-tool/container-base-image obligations separately according to actual distribution scope.

To update notices, regenerate with cache arguments from the [third-party audit](THIRD_PARTY_AUDIT.en.md). Generators/collectors fix `completed_legal_audit` to false. Write a separate human record with date, reviewed scope, APK hash, and conclusions rather than editing that field as a substitute for review.

Fill missing/incomplete evidence and recapture. If supplemental notices change source/APKs, rebuild the candidate and verify every artifact. Completion: current dependencies, terms, notice distribution locations, and human conclusions are traceable.

### 2.8 Accept real Linux installation and upgrades with data

Requires an independent Ubuntu/Debian acceptance host, Docker Engine, Compose v2, systemd, and dependency-download access. Source is fixed at `/opt/pactick/app`; configuration/backups stay outside source. HTTPS additionally requires Nginx, Certbot, curl, OpenSSL, gettext-base, and other prerequisites in the [self-hosting guide](SELF_HOSTING.en.md).

Run from `/opt/pactick/app`:

```bash
sudo bash deploy/scripts/install.sh install --local-only
sudo bash deploy/scripts/install.sh status
sudo systemctl status pactick-backup.timer
sudo bash deploy/scripts/install.sh registration open
```

Create a test account through the client or API, then close registration:

```bash
sudo bash deploy/scripts/install.sh registration close
```

Confirm new registrations are rejected while existing accounts can log in. Default configuration: `/opt/pactick/config`; backups: `/var/backups/pactick`; API: `127.0.0.1:8080`; PostgreSQL publishes no host port. Remote Android devices cannot access server loopback and need an HTTPS entry.

With custom configuration, add `--config-dir /actual-directory` to every `install.sh` command. `--backup-dir` and `--port` are installation parameters; `backup` takes no positional file/directory argument. Repeated installation reuses existing configuration, passwords, port, and backup path. Update source with `upgrade`.

Upgrade with data:

1. Obtain an actual old source/image/deployment and create tasks, projects, plans, and focus history in isolation. Record counts, IDs, exports, and the migration ledger.
2. Keep old source, images, configuration, and backups. Stop other administrator-started writers using the database; the upgrade script controls only its Compose API.
3. Update source in the same directory, preserving configuration/database volumes, then run:

```bash
sudo bash deploy/scripts/install.sh upgrade
sudo bash deploy/scripts/install.sh status
```

4. Confirm production image configuration changes only after success, `.release-pending` is cleared, `pre-deploy/` contains this backup, and the ledger includes new cleanup migrations.
5. Verify old-account login, entity counts/content, two-device sync, and isolation of a second account.
6. In a disposable environment, exercise build, backup, migration, and API-readiness failures. Build/backup failures must retain the old API/configuration. Failures after migration begins must retain the pending marker and prevent registration toggles from recreating the API.
7. Fix causes and retry upgrade. Old-image configuration does not mean the database rolled back. Do not start an old API incompatible with the new database. Restoring a pre-migration backup discards later writes.

Completion: clean install and actual old-data upgrade both pass, failure handling meets the contract, and real container/migration/business logs exist.

### 2.9 Accept backups, isolated restore, and new-host recovery

Run from `/opt/pactick/app` on the acceptance server:

```bash
sudo bash deploy/scripts/install.sh backup

sudo bash deploy/scripts/install.sh restore-check \
  /var/backups/pactick/daily/实际生成的文件.dump

sudo journalctl -u pactick-backup.service --since yesterday
```

Select the file actually printed by backup, retain its `.dump.sha256`, and verify it. Defaults retain seven daily, four weekly, six monthly, and ten pre-migration copies. Also wait for and verify at least one normal scheduled backup.

Successful isolated restore prints `restore check passed`, cleans temporary containers/volumes, and leaves the original database unchanged. The script checks a checksum file when present; this acceptance requires retaining and checking it. It checks restore success and existence of the migration ledger/users table only, not account/entity counts or business content.

To inspect the temporary database, retain resources with `PACTICK_KEEP_RESTORE=true`. Afterwards clean only resources named by this invocation, not other deployment volumes:

```bash
sudo env PACTICK_KEEP_RESTORE=true \
  bash deploy/scripts/install.sh restore-check \
  /var/backups/pactick/daily/实际生成的文件.dump
```

New-host recovery requires a second isolated server:

1. Install a compatible PostgreSQL major/application version, keep registration closed, and do not expose service before acceptance.
2. Copy `.dump`/`.dump.sha256` into a private directory on the new host, stop its API, and confirm that the acceptance database may be overwritten.
3. Run below in the new host's root shell. Examples use default configuration and `/root/pactick-recovery`; directory, filename, and configuration paths must match reality.

```bash
set -euo pipefail
cd /opt/pactick/app
compose=(docker compose --project-directory /opt/pactick/app \
  --env-file /opt/pactick/config/compose.env \
  -f /opt/pactick/app/compose.production.yaml)

"${compose[@]}" stop api

cd /root/pactick-recovery
sha256sum --check 实际文件.dump.sha256

"${compose[@]}" exec -T postgres sh -eu -c \
  'exec pg_restore --clean --if-exists --no-owner --no-privileges --exit-on-error --username="$POSTGRES_USER" --dbname="$POSTGRES_DB"' \
  < /root/pactick-recovery/实际文件.dump

cd /opt/pactick/app
"${compose[@]}" --profile maintenance run --rm --no-deps migrate
"${compose[@]}" up -d --no-deps --force-recreate \
  --wait --wait-timeout 90 api

bash deploy/scripts/install.sh backup
bash deploy/scripts/install.sh status
```

`pg_restore --clean` deletes existing objects affected by restore and may target only an explicitly overwrite-approved database. See [PostgreSQL pg_restore](https://www.postgresql.org/docs/17/app-pgrestore.html). On restore/migration failure, stop subsequent startup steps, inspect logs/ledger, and do not expose service.

After restoring historical backups, run current migrations before exposing service. New migrations do not rewrite historical app identifiers in old backups. Database backups exclude server configuration/JWT secrets. Maintainers must choose private configuration migration or new keys requiring users to log in again.

4. Verify `/readyz`, old-account login, entity counts/content, post-restore two-device sync, and new backups. Actually test old client cursors against the restored database; automatic sync recovery cannot be assumed.
5. Switch the domain/client address only after acceptance, keeping the old host for fallback. Copying backups elsewhere and actually restoring them establishes recovery independent of the original host/disk.

Completion: isolated and new-host restores both pass, business content is correct, and backups are usable without the original host.

### 2.10 Accept actual HTTPS, renewal, and public WSS

Requires a maintainer-controlled domain, ACME contact email, and a decision to accept ACME terms. A/AAAA must point to the target with public TCP 80/443 reachable; remove invalid AAAA records. The installer does not change firewalls.

Run from `/opt/pactick/app`, replacing example domain/email:

```bash
sudo bash deploy/scripts/install.sh install \
  --domain api.example.com \
  --email admin@example.com \
  --accept-acme-terms

sudo env PACTICK_PUBLIC_URL=https://api.example.com \
  bash deploy/scripts/verify-deployment.sh

sudo certbot renew --dry-run
sudo systemctl status certbot.timer
sudo bash /etc/letsencrypt/renewal-hooks/deploy/pactick-nginx.sh
```

For custom configuration, use `--config-dir` with installation; invoke direct verification with `sudo env PACTICK_CONFIG_DIR=/actual-directory PACTICK_PUBLIC_URL=https://actual-domain ...`.

Acceptance:

- Certbot actually issues the target certificate with correct domain/trusted chain. Issuance failure preserves the old Nginx site.
- Verification checks container health, loopback API, no database host port, health endpoints, and backup freshness; public `/readyz` and HTTP redirects work.
- Renewal dry-run succeeds, timer is enabled, and Nginx reload hook actually succeeds.
- Access HTTPS from another network/device, not just the server.
- Two Android devices log in/sync over public HTTPS; authenticated `/v1/ws` establishes WebSocket and delivers change hints.

`renew --dry-run` does not run deploy hooks by default. Verify reload separately or use `--run-deploy-hooks` on supporting versions. A successful drill is not a naturally occurring renewal. See [Certbot documentation](https://eff-certbot.readthedocs.io/en/stable/using.html).

Completion: separate real evidence for issuance, renewal drill, reload, public HTTPS, and WSS. Redact tokens, passwords, and personal data in retained logs.

### 2.11 Accept Android devices, two-device operation, and migration

Prepare at least two devices with the same final signed candidate, covering different Android versions/actual permission states. Current minimum Android SDK is 26; recheck support against the final APK.

| Scenario | Operations and passing criteria |
| --- | --- |
| First offline use | Without configuring a server, create/edit tasks, projects, and plans; restart and confirm persistence |
| Default priority ordering | General/filtered lists and pickers use priority order after editing/restart; Today retains plans/manual order |
| Task reminder notification | Use the [specialized checklist](ANDROID_TASK_REMINDER_CHECKLIST.en.md) for default-on, counts, silent content, permissions, disabling, workspace changes, tapping, reboot, and updates; record every result |
| Offline focus/statistics | Start, pause, resume, and finish focus; verify task associations, duration, and statistics |
| Local backups | Export and import offline into a new workspace; verify content, preserved original workspace, and no automatic upload |
| Invalid backups | Import corrupt, unsupported-version, and over-50-MiB files; show errors without changing original data or leaving partial restore |
| Focus recovery | Exit, force-stop, and reboot separately in running/paused states, then reopen; session, timing, notifications, and statistics agree |
| Permission changes | Deny/revoke notifications, Usage Access, and overlay permission; limitations are accurate and local tasks remain available |
| Two-device focus | A starts focus; after B syncs it can view but not pause/end A's session, and B's old counts are not mixed in |
| Sync/conflicts | Edit offline on both devices, reconnect, concurrently edit the same record, test deletion/references; results meet contracts |
| Network/service faults | Offline, expired tokens, unavailable service, and version incompatibility still permit local edits and preserve pending changes |
| Two-server isolation | Construct matching user IDs in two isolated databases and switch servers; data/tokens/queues/cursors remain separate; copy-and-upload requires explicit choice |

For save-failure/initialization-retry checks, use reproducible faults with disposable data and verify retained input, errors, and retry. Existing SQLite fault tests do not replace device storage-error usability checks.

Migration from old `com.example.planfocus`:

1. Obtain the actual old APK, create test data, and identify real export entry/format.
2. The new package currently supports `pactick-workspace` version 1 up to 50 MiB. Old-package compatibility is unconfirmed; changing filenames/format labels cannot be assumed sufficient.
3. If incompatible, develop conversion from the actual old format and verify fields, references, deleted records, and unsynced changes.
4. Install independently, import, and compare tasks, projects, plans, history, and unsynced content individually. The new package does not automatically obtain old SQLite/settings/credentials.
5. Keep the old app/original backup until checks finish. Server connection/upload remains a separate user choice.

Later same-package, same-signature in-place updates:

1. Install the previous `com.example.pactick` and create local/unsynced data.
2. Update with the same production certificate and higher build number; verify data/settings/pending changes remain.
3. For signature mismatch, check certificates before uninstalling the only data-bearing app. Verify backup restoration first.
4. Without a previous formal same-signature artifact, a controlled simulated update is possible but must be labeled accordingly. Keep this formal artifact as the next update-test baseline.

Completion: record APK hash, device model, Android version, operations, and results for each case. Unknown old formats or unverified conversion leave migration incomplete. See [local backups and migration](LOCAL_BACKUPS.en.md).

### 2.12 Update acceptance and actually publish

1. Check documentation against the actual interface. Settings → About Pactick directly opens licenses; third-party documents reflect this entry.
2. Write candidate acceptance records with commit, APK hash, version, environment, date, logs, and unverified items. Do not label local tests as real-environment acceptance.
3. If source-preview/APK/self-hosting order changes, update [release-process](RELEASING.en.md) conditions.
4. Regenerate snapshots after final edits. APK-affecting changes require rebuild/reverification; checksums refer to final upload files.
5. Publish the reviewed clean repository and APK, corresponding source, SHA-256, certificate fingerprint, third-party notices, and changes.
6. Redownload public artifacts, verify checksums, and test installation. Explain that the client opens releases externally and does not automatically verify APK integrity/certificates.
7. Retirement of a personal old server is separate and requires completed personal-data migration/restore checks first.

Completion: public artifacts match accepted objects, corresponding source/feedback entries work, and notes accurately describe current behavior/limits.

## 3. Social-media promotion preparation

Promotion adds ordinary-user material, assets, and maintenance arrangements to the release requirements above. The first round should target Chinese-speaking Android users through organic posts and voluntary trials. Paid promotion, app-store listing, and overseas promotion require separate assessment. The current roadmap excludes a first-version app-store launch.

### 3.1 Define audiences and the product description

Prioritize:

- Android users wanting tasks, calendar scheduling, and focus records together.
- Developers/tool enthusiasts interested in local data, source code, and self-hosted sync.

Explain use to ordinary users and implementation/deployment to technical communities. Use Pactick consistently and accurately label Android preview status, account-free local use, optional self-hosted sync, and Source Available licensing. Sync requires the user's own server; maintainers provide no public sync service. Other client platforms are outside the first version.

Organize product content around Create task → Schedule in Calendar → Focus → Review actual time. State when implemented behavior still lacks device acceptance. Do not promise unverified compatibility, effects, or maintenance duration.

Completion: profiles, videos, articles, downloads, and FAQ agree on product name, functions, version, and license.

### 3.2 Complete user onboarding and data information

The [Android getting-started guide](GETTING_STARTED.en.md) now covers initial operations, data, and permissions in the current interface. Testers must still verify these subjects against the actual candidate before promotion:

- Official downloads, current version, and artifact verification.
- APK installation, Android prompts, and common installation failures.
- First task, scheduling, starting focus, and viewing statistics.
- Data storage, backup export/restore, phone replacement, and pre-uninstallation handling.
- Normal versus guard mode.
- Usage Access, overlay, and notification permissions, including refusal limitations.
- Default-on reminders, system permission, and channel disabling. Ongoing counts and deadline/plan-time notifications have separate switches; the latter uses inexact alarms.
- Local use versus self-hosted sync and whether a server is needed initially.
- Known issues, applicability, maintenance, and feedback.

The current implementation uses Usage Access to identify foreground apps, overlays for guard reminders, and a focus foreground service for ongoing notifications. Verify permission descriptions against the final candidate. Backups are unencrypted business-data files; never demonstrate public feedback with real files.

Add new public documents to `scripts/prepare_public_source.py`'s allowlist. Completion: a tester uninvolved in development can download/install, complete first operations, and export a backup using only the guide.

### 3.3 Establish a unified, maintainable download entry

Every platform should point to one project entry with at least version, release date, support scope, APK, corresponding source, SHA-256, certificate fingerprint, getting started, known issues, changelog, and feedback.

Start with the official repository/Releases; decide later whether an introductory site is needed. Actually test access, download, and installation on Chinese mobile networks. If a mirror is necessary, provide the identical APK, matching source/checksums, and explicit version. After updates, check all entries so differing packages in old posts do not persist indefinitely.

Completion: users arriving from any promotional content can identify the official current entry/version and obtain the same verifiable artifact.

### 3.4 Unify accounts and visual material

Prepare a consistent product name, avatar, profile, and contact entry; keep names aligned across platforms where possible. Profiles identify authors/maintainers and distinguish official/repost accounts. Enable two-factor authentication and retain recovery methods after registration.

Prepare a kit for reposters/reviewers: icons, introduction, screenshots, download address, current limits, and reuse terms. Those terms require confirmation from someone authorized for the assets.

Completion: account ownership and asset provenance are clear, and maintainers control access/recovery.

### 3.5 Produce actual demonstrations

Suggested initial assets follow. Counts/durations are production recommendations, not platform requirements:

| Asset | Suggested content |
| --- | --- |
| Five to six screenshots | Tasks, Calendar, Focus, Statistics, backup, and light/dark interfaces |
| 30–60-second portrait video | One concrete operation and its result |
| 3–5-minute landscape video | First use, core functions, and current limits |
| Illustrated article | Use cases, steps, and intended audiences |
| FAQ | Installation, permissions, backups, sync, licensing, feedback |

Each clip should explain one scenario, with interface text legible on phones. Use demo data and disable private notifications. Capture actual candidate interfaces; label concept designs. Music, fonts, and other assets require appropriate usage rights.

Completion: assets trace to a candidate, contain no private information, match current functions, and are readable in portrait/landscape formats.

### 3.6 Arrange content by platform

These are suggested content roles, not guarantees of traffic or external-link acceptance. Recheck account/community rules before posting.

| Platform | Suggested content |
| --- | --- |
| Bilibili | Full demonstrations, development process, version updates |
| Xiaohongshu | Illustrated posts/short videos about daily scheduling, focus, or review |
| Douyin, Kuaishou, WeChat Channels | Short operation/result videos with legible interface text |
| Zhihu | Problems addressed, local use, sync, and concrete examples |
| Weibo | Release notices, update summaries, short demos, pinned current entry |
| WeChat Official Accounts | Getting started, FAQ, and update references |
| Coolapk and other Android communities | Installation experience, permission explanations, device compatibility, test feedback |
| Juejin, V2EX, other technical communities | Flutter/Go implementation, local storage, sync architecture, deployment |
| YouTube, X, Reddit, other overseas platforms | After English introductions, installation guides, and feedback support are ready |

Initially choose one demonstration platform and one feedback community, such as Bilibili plus an Android community. Expand after content/maintenance stabilizes. Adapt length, visuals, and subject per platform instead of copying whole promotional posts mechanically.

### 3.7 Check platform rules

External links, QR codes, commercial cooperation, verification, and disclosure rules change. Check the rule center and actual account capabilities on posting day.

- Introduce the product as its author; base functionality/experience on actual demonstrations. Xiaohongshu's current convention emphasizes authentic sharing and recommends describing AI involvement in content creation. See its [community convention](https://pgy.xiaohongshu.com/help/detail?id=1eda0a065dd894063c2e029a49e8f6a1&userType=4).
- Zhihu content should help with the actual question/topic and avoid repeated promotion or irrelevant answers. See the [creator manual](https://www.zhihu.com/knowledge-plan/manual).
- Bilibili submissions follow the [community convention](https://member.bilibili.com/studio/convention/) and actual submission requirements.
- Check whether each overseas community accepts author promotion. Reddit restricts repetitive mass posting and unsolicited bulk interaction. See [Reddit Spam rules](https://support.reddithelp.com/hc/en-us/articles/360043504051-Spam).

Use platform-permitted posting methods when external links are restricted; do not evade restrictions with disguised links or bulk private messages. Preserve reviewers' independent evaluations rather than requiring uniform praise. Disclose paid/other cooperation under applicable platform rules.

These rule links were checked on 2026-10-01 and do not replace posting-day checks. Completion: submissions, download directions, and cooperation labels comply with rules applicable to the actual accounts.

### 3.8 Limited trials and publication pace

Advance by completion criteria and postpone when acceptance fails; do not promise a fixed public date prematurely.

| Stage | Operation | Condition for advancing |
| --- | --- | --- |
| Preparation | Complete entry, onboarding, assets, feedback, and release acceptance | Consistent information and explicit candidate/test scope |
| Limited trial | Voluntarily invite about 10–20 testers across phones/Android versions | Feedback on installation, first use, backup, and priority scenarios |
| Correction | Prioritize installation failures, permission confusion, difficult operations, data issues; update guide | Critical blockers fixed/retested |
| Public release | After release conditions, publish preview notes/full demonstration and gradually add topics | Public downloads/feedback work |
| Continued updates | Summarize common questions, publish fixes/version changes/new validation | Sustainable feedback handling/material maintenance |

10–20 testers is a suggested scale, not statistical reliability. Invitations state version, preview status, requested tests, feedback method, and treatment of quoted feedback. Obtain consent before publicly quoting user reviews/screenshots.

### 3.9 Feedback and maintenance after promotion

Before release, prepare a feedback template collecting app version, phone model, Android version, reproduction steps, expected/actual results, and necessary screenshots. Tell users not to submit actual backups, tokens, databases, or private-server information publicly. Security issues use private reporting.

Observe especially:

- Whether users find the entry and install successfully.
- Whether they create a first task and start focus.
- Which permission, sync, or documentation details repeatedly confuse them.
- Which problems recur and which fixes are most urgent.
- Whether testers want to continue and the reasons they volunteer.

Use platform statistics and voluntary feedback. Do not add task-content tracking by default for promotion. Without in-app analytics, feedback estimates must not be presented as precise retention rates.

Maintain current known-issue information and schedule comments/issues according to available time. Prioritize data loss/security, then core defects, usability, and new functions. Do not promise fixed response times unsupported by maintenance resources.

Completion: feedback has a clear destination, common questions/limits are findable, and future fixes correspond to public records.

## 4. Deliverables and task tracking

### Release acceptance

Checked `+4` items below belong to the historical 2026-10-02 candidate. Current `+5` source must not inherit them before formal signing, notice/asset review, devices, and final provenance comparison.

- [x] Formal terms/attribution confirmed and root/client licenses match (2026-10-02; third-party compatibility separate).
- [x] Historical `0.2.0-preview.1+4` source/APK asset provenance and notices checked (2026-10-02; generated branding, official Material timer; historical assets excluded).
- [ ] Official repository, Issues, private security reporting, and Releases entries work.
- [ ] Final manifest, manual privacy review, and Git files agree.
- [ ] Six PostgreSQL top-level tests actually PASS and remote Checks passes.
- [x] Production-signed candidate built with matching source/version/hash/certificate (2026-10-02; `+4`; phone acceptance separate).
- [x] Historical `+4` native dependencies/licenses/NOTICE passed scoped terms/distribution-notice review (2026-10-02; 105 components, 75 modules, 74 binaries; not professional legal advice).
- [ ] Current source's final signed candidate, provenance, dependency/asset reviews repeated; `+5` debug build is no substitute.
- [ ] Default ordering/task-reminder specialized device checks complete.
- [ ] Linux clean install, data upgrade, and failures pass.
- [ ] Actual backup, isolated restore, and new-host recovery pass.
- [ ] HTTPS issuance, renewal drill, reload, public WSS pass.
- [ ] Android offline, focus recovery, two-device, and failure scenarios pass.
- [ ] Old-package migration actually verified; same-package update records actual/simulated scope.
- [ ] Document status, changes, and final upload artifacts rechecked.

### Promotion preparation

- [ ] Product introduction, audience, initial platforms, maintenance capacity defined.
- [ ] Official entry, onboarding, data/permission information, FAQ available.
- [ ] Official accounts, avatar/profile, two-factor authentication, recovery configured.
- [ ] Screenshots, landscape/portrait videos, illustrated posts, reusable kit produced.
- [ ] Posting-day platform rules, external links, cooperation labels checked.
- [ ] Limited trial, feedback handling, and critical-issue retesting complete.
- [ ] Known issues, feedback templates, and future maintenance arrangements available.

For each completed item, record date, responsible person, corresponding commit/APK hash, evidence location, and remaining limitations. Public documents contain only publishable information. Keys, real backups, personal logs, and private deployment configuration remain protected.

The 2026-10-02 `+4` records are in maintenance directory `output/license-review-20261002/candidate/`, with separate compliance results in `DISTRIBUTION_REVIEW.json` and summary in `RELEASE_CANDIDATE.md`. APK SHA-256: `33f62ce1f93a041ab3ad80befd033c7c40842a4cef9003259dcb323abaef5e40`. Local allowlisted-source commit: `8cbe0d42c94da33d4a260bcc081c3ac5b9e243a7`, not pushed. This maintenance status was updated after artifact generation and does not change sealed source archives/manifests. The candidate contains its own independent final records.
