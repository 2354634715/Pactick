[简体中文](CHANGELOG.md) | English

# Changelog

## 0.3.0-preview.3 (2026-10-31)

The Android version is `0.3.0-preview.3+8`; the package remains `com.example.pactick`. This version integrates subsequent client, server, and website source. The corresponding Release identifies final artifacts, executed checks, and device limitations.

- Add free focus without a task. First associate an existing/new task from review or history after ending, preserving timing and pauses. The server adds a device- and field-restricted first-association exception; older servers must upgrade.
- Reorder Android phone navigation to Focus, Today, Tasks, Calendar, Statistics, still opening Today. Wider navigation keeps its existing order.
- Add Follow system, Chinese, and English choices for Flutter UI, dates, Android notifications, and errors, with complete English public documents. User content remains unchanged.
- Add an opt-in focus desktop listing Pactick, system apps, and the current whitelist, with ordinary/private focus entry points. It does not replace the launcher or isolate applications.
- Add opt-in Android system calendar connections per workspace: read-only import or two-way ordinary plan title/time updates, with explicit conflict and one-sided deletion choices. Vault data, task deadlines, and focus are excluded.
- Update Material 3 UI and Noto Serif SC display headings with OFL notices. Fix source export corrupting font bytes, and add source/final-APK font integrity checks.
- Rewrite the Chinese/English getting started guides with actual scheduling, reminders, focus policies, vault, desktop, calendar, backup, and sync operations and limits.
- Include Chinese/English static website source and local preview with versioned download/document links. This release does not deploy the website or add prebuilt server assets.

## 0.3.0-preview.2 (2026-10-24)

The Android version is `0.3.0-preview.2+7`, package `com.example.pactick`. This prerelease provides plan editing/deletion, deadline and plan-start reminders, vibration, strict mode, the private vault, and version 2 workspace backups, with local-backup connection and private-state fixes.

That version was checked on one TAS-AL00 running Android 12. Its device results apply only to that artifact and do not validate preview.3 additions or integration.

## 0.3.0-preview.1 (2026-10-11)

The Android version is `0.3.0-preview.1+6`; the package name remains `com.example.pactick`. This version provides full Windows/Linux x86-64 server bundles and a newly signed APK.

- Add a local browser management GUI supporting first-time Docker deployment or local operation connected to existing PostgreSQL, with start/stop, logs, and manual database backups.
- Add a local account management command and one-click GUI account creation without temporarily enabling public registration or generating device registrations or login tokens.
- Merge Android task reminders, a notification permission entry, and priority ordering in general task lists. The reminder switch is stored on this device.
- Fix synchronization recovery after duplicate creation of default focus policies and automatic synchronization recovery after token refresh.
- Server bundles include the API, migration, health-check, account management, and GUI programs, deployment scripts, server source, and licenses. Build outputs are distributed only as release assets.

Results and checks not performed are recorded in the internal `RELEASE_VALIDATION_20261011.md`; this record is not included in public source.

## Historical preparation record for 0.2.0-preview.1

Target version: `0.2.0-preview.1+5` (Android package: `com.example.pactick`).

### Default theme

- Use red accents, near-black text, and an off-white background by default. Dark mode uses a warm-black background and brighter red.
- New installations disable system dynamic color by default. Previously saved dynamic-color and light/dark preferences continue to apply.
- Android deep-guard reminders and adaptive icon backgrounds use the corresponding palette. The main application icon and custom project colors are retained.

### Consistent Pactick naming

- Standardize the product display name as Pactick, the Dart package as `pactick`, and the app entry as `PactickApp`.
- Use the new name for the Android package, native channels, database and session keys, backup format, and server token issuer.
- Update the Go module, deployment environment variables, database examples, service/template filenames, CI artifact names, and documentation references.
- The product had not yet been released; this change establishes separate installation and data spaces using new identifiers.

### Pre-release review fixes

- Serialize synchronization write transactions by account and add a migration to remove historical application identifiers. Read account exports through a single read-only snapshot transaction.
- Upgrade using candidate image configuration and replace production configuration only after a successful release. Restrict subsequent recreation after a post-migration release failure.
- Commit UI state after successful local writes and allow retry on save failure. Allow reopening after the initial database open fails.
- Allow only the originating device to control active focus. Pass session ID and paused state during Android recovery and isolate guard statistics by session.
- Use the same public source snapshot for signed-candidate checks and builds. Verify tag version, licenses, and file hashes, and record the toolchain.
- Extend source scanning to `AUTH_JWT_SECRET` and common assignment formats. Collect Android native dependencies and embedded notices for the current candidate.
- Complete notices for Android native libraries, the Material icon font, CLDR data, and engine acknowledgments. Load a supplemental asset from the offline license entry and compare the full text in the final APK during build checks.
- Replace the focus notification icon with Google Material timer from a fixed upstream version. Preserve Apache-2.0, the original asset, and conversion instructions. Continue using the existing generated Pactick main icon.
- Preserve licenses and copyright notices based on the wrapper JAR's actual Gradle 2.10 origin. The download target remains Gradle 9.4.1.
- Fix the slider range when selecting a four-hour task on the focus page. Use the same upper limit for task estimates and focus targets.
- Compare signed candidates with the pre-archive provenance record. Changing both source files and the manifest still blocks upload.
- Add checks for locked third-party versions, license-evidence hashes, and Android runtime module consistency. Report unsupported dependency origins explicitly.
- The owner confirmed the project license terms, with copyright attribution “王辰昊 Wang Chenhao”. Continue recording third-party and asset license review separately.
- Configure the official repository and security reporting email, and add the Android getting started guide and asset-source inventory. The initial scope provides source and an Android preview; public self-hosting is not yet recommended.

### Transition to public source

- Use local-first client storage, with optional cloud synchronization through a self-hosted server.
- Open a local workspace directly on first launch. Local editing, focus, and export remain available after session expiration or sign-out.
- Configure an HTTPS server at runtime and isolate data by server and account. Connecting defaults to a separate cloud workspace; uploading existing local data requires user selection.
- Add versioned offline backup and the Android system file picker. Restore creates a new workspace transactionally; copying preserves the original workspace.
- Integrate server registration, account export, and deletion APIs. Remove background update checks and mandatory update mechanisms that restrict the entire client.
- Add contribution rules, private security-report configuration instructions, and a third-party license-evidence inventory.
- Add a source snapshot tool that copies only the public allowlist and preserves original private material.
- Add Go, Flutter, and Android debug build checks. Use a separate workflow for signed candidates.
- Provide server self-hosting, backup, and restoration instructions.
- Generate private keys through the deployment entry point and support registration controls, upgrades, pre-migration backups, and scheduled backups. Restore the original HTTPS site on configuration failure. Use locks and unique filenames for backups.

The preceding section records historical preparation before the first APK publication. Later releases are listed above; historical validation does not automatically apply to new artifacts.
