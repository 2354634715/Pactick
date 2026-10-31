[简体中文](README.md) | English


Choose Follow system, 简体中文, or English in **Settings → Appearance → Language**. The choice is saved on this device. See [language support](../docs/LOCALIZATION.en.md).
# Pactick Android client

The client uses Flutter and Material 3 and provides tasks, a calendar, focus sessions, and statistics. First use opens a local workspace without connecting to a server. For synchronization across devices, configure your own HTTPS server in Settings and sign in.

The current source version is `0.3.0-preview.3+8`. Android phone navigation is Focus, Today, Tasks, Calendar, Statistics, opening Today. Start free focus without a task and first associate one from review or history after ending. General task lists default to Urgent → High → Medium → Low → None, with ascending `rank` and then stable task ID order within a priority. Today continues to use the day's schedule and manual order.

Android task reminders are enabled by default. When unfinished tasks exist and the system allows notifications, one silent notification displays only the pending count. Changes update the same notification; completing all tasks or disabling the switch removes it. Tapping it opens Tasks. Manage the switch and notification permission under Settings → Task reminders. The switch is stored on this device and does not migrate through synchronization or backup. Deadline/plan-start reminders, the private vault, a focus desktop, and system calendar connections are implemented. The desktop and calendar connections are disabled by default, and the interface supports Chinese and English. See the [getting started guide](../docs/GETTING_STARTED.en.md#manage-task-notifications) for operations and system limits and the [acceptance checklist](../docs/ANDROID_TASK_REMINDER_CHECKLIST.en.md) for device checks.

## Development

Run from the repository's `client` directory:

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug
```

These commands fetch dependencies using the lockfile, run static checks and tests, and build a debug APK. The output is `build/app/outputs/flutter-apk/app-debug.apk`, relative to the client directory.

See [building](../docs/BUILDING.en.md) for toolchains, dependency versions, and production signing requirements. Use the project's debug options when local development requires HTTP. Production self-hosted addresses use HTTPS.

## Data and migration

Local use does not depend on a maintainer-operated server. Workspaces, tokens, and synchronization state are managed separately by server and account when switching servers or accounts. Signing out preserves local data. Deleting server data and deleting a local copy are different operations.

Export a backup and verify restoration before changing signatures or reinstalling. Production packages must use a stable production certificate; see `android/key.properties.example`. Keys, passwords, `key.properties`, and `local.properties` must not be included in source distributions.

## Releases and licensing

The About page opens the build-time `RELEASES_URL` in an external browser. If it is not configured, the entry is unavailable; consult the distributor's instructions. The repository is `2354634715/Pactick`; verify the actual release location and build parameters for each candidate. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.en.md) for third-party notices and [RELEASING.md](../docs/RELEASING.en.md) for release acceptance requirements.

The project uses a Source Available license. See [LICENSE](../LICENSE) and the [FAQ](../docs/LICENSE_FAQ.en.md) for its scope.
