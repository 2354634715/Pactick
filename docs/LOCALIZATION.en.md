# Client language and English documentation

[简体中文](LOCALIZATION.md) | English

## Choose the client language

Open **Settings → Appearance → Language** and choose **Follow system**, **简体中文**, or **English**. The default follows the system: Chinese system locales, including regional variants, use Simplified Chinese; all other system languages use English. An explicit choice updates the interface immediately. Follow system restores language selection from the system locale.

The local global setting `language_preference` stores `system`, `chinese`, or `english`. A missing or unrecognized value uses `system`. Switching workspaces or sync accounts does not change the choice. The setting is not synced and does not travel in workspace backups. A failed save retains the previous choice and exposes a retry action.

Translations cover navigation, task and plan editors, the calendar, focus, statistics, login, settings, the private task vault, and app-generated messages. Dates, weekdays, and compact durations follow the current language. Task titles, notes, project names, tags, saved device names, and user-edited policy names remain as entered. Built-in focus policy names are translated for display only when both their ID and original name match; stored and synced contents remain unchanged.

Android task reminders, focus notifications, channel names, guard messages, and file-operation errors use the same choice. The native layer stores a copy so reminders can resolve the language while Flutter is not running. The app updates this copy at startup, on resume, and when the language changes. A native update failure does not prevent local workspace use; the app retries on the next resume. Android controls the language of system file pickers, permission screens, and system settings pages.

Errors and notices already stored in interface state retain the language in which they were generated. Repeating the related operation generates messages in the new language.

## Maintain interface translations

`client/lib/core/localization/english.dart` combines the mappings from Chinese source messages to English. Features such as system calendars may keep translations in a separate catalog that it imports, such as `system_calendar_english.dart`. UI code uses `context.tr(...)` to establish a Flutter localization dependency and rebuild when the locale changes. Controllers, model display names, and errors use `tr(...)`. Add each new static Chinese source key and its English translation together. A missing English key falls back to the Chinese source; automated checks should catch omissions before merge.

Pass dynamic data through `args` into `{name}` placeholders. Both languages retain the same placeholders. Never use user input as a translation key or run placeholder substitution again on an inserted value. Android messages live in `res/values/strings.xml` and `res/values-zh/strings.xml`; both files must retain the same resource names and format arguments.

Run from the `client` directory:

```sh
flutter analyze
flutter test test/localization_test.dart
flutter test
flutter build apk --debug
```

Localization tests check catalog coverage, placeholders, date formatting, language persistence, failure handling, and page switching. Existing GUI regressions select Chinese explicitly; English tests set their own locale. Check new pages with longer English messages and larger text. Automated tests and a debug build do not replace Android device acceptance for notifications, system language changes, permissions, or accessibility.

## Public documentation scope

Public Markdown documents have `.en.md` companions in the same directories, with language links near the top. The API reference has `api/openapi.en.yaml`; GitHub bug and feature forms have `.en.yml` companions. License terms, original third-party licenses, copyright attributions, commands, configuration keys, and protocol fields remain unchanged. Translation does not change licensing, contribution rules, or historical validation conclusions.

The allowlist in `scripts/prepare_public_source.py` defines publication scope. English files inherit the scope of their Chinese originals and do not automatically include internal reports or deployment records in public source. Review English companions whenever Chinese originals change.

For permissions, data flows, and conflict handling in Android calendar connections, see [system calendar synchronization](SYSTEM_CALENDAR.en.md).
