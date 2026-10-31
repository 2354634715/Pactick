# Getting started with Pactick for Android

[简体中文](GETTING_STARTED.md)

Updated: 2026-10-31. Applies to `0.3.0-preview.3+8`. This guide describes the Android client. Check the matching release notes for the actual download, tested devices, and known issues.

Pactick stores tasks, calendar plans, and focus records on your device. No account or server is required to start, and a new workspace contains no sample tasks. Account synchronization, system calendar integration, and the focus desktop are optional. The private vault has a separate password and does not participate in account synchronization.

## Install or update

Android 8.0 (API 26) or later is required. Select a version from [Pactick Releases](https://github.com/2354634715/Pactick/releases), read its support details and known issues, and download its APK. A filename alone does not identify the publisher.

1. Compare the APK's SHA-256 with the value published for that release. On Windows, open PowerShell in your download folder and run `Get-FileHash -LiteralPath '.\pactick.apk' -Algorithm SHA256`, replacing the filename as needed. Download again if it differs; do not install that file. A signing certificate identifies the publisher and update compatibility and is distinct from the file hash. See [Releasing](RELEASING.en.md) for certificate checks.
2. Open the APK in a file manager or browser. If Android requests permission to install from this source, grant it to the app opening the APK and continue. This permission is separate from Pactick's notification and focus permissions.
3. Open Pactick. After an update, check your tasks, plans, history, and unsynchronized changes.

Before updating, export the workspaces you need. For private content, retain both its encrypted backup and the password used when exporting it. An update with the same package name requires a compatible signing certificate and a higher build number. If Android reports a signature conflict or cannot update, check the package sources, free storage, and Android version. Do not uninstall the only copy of your data to resolve an installation problem.

“Settings → About → View releases” opens the build's configured HTTPS release page in the system browser; the app does not automatically download or install updates. The entry is disabled when no page is configured. An invalid address or browser failure produces a message. The old `com.example.planfocus` package and the current `com.example.pactick` package are separate apps and do not migrate data automatically. Keep the old app and its backups until export compatibility has been confirmed.

## Pages, language, and appearance

On an Android phone, the bottom navigation is “Focus, Today, Tasks, Calendar, Statistics.” The app opens Today by default. Wider windows use side navigation. Open Settings with the gear icon at the top of a page.

Under “Settings → Appearance → Language,” choose system language, 简体中文, or English. System language is the default: Chinese language variants use Simplified Chinese, and other system languages use English. Your choice is stored on this device and does not rewrite task names, projects, custom policies, or calendar names. UI text, dates, and app notifications use the selected language. See [Localization](LOCALIZATION.en.md).

Light/dark mode follows the system by default, and dynamic colors are off. Change either under Appearance. The fixed theme uses the brand red with light or dark surfaces; page headings use the bundled serif font, while body text and controls remain sans serif. If dynamic colors are enabled but unavailable, the fixed theme is used. Updates retain saved choices. Native guard messages and the focus desktop use fixed colors following the system's light/dark mode.

## Create tasks and schedule time

1. Open “Tasks → New task,” enter a title, and save it. A task without a project belongs to Inbox. You can create a project from the editor before selecting it.
2. Add notes, priority, a due date and time, estimated duration, and tags as needed. Separate tags with commas or Chinese enumeration commas. Selecting a due date without changing the time sets it to `00:00` that day; also choose a time if you want a daytime reminder.
3. Open Calendar and create a time block. Select a task, date, start time, and planned duration, then add it to the calendar. You can also schedule from unscheduled tasks or task details. A block without a task requires its own title. A task can have multiple blocks.
4. To change an existing block, open its calendar record and select the plan editor, or select it in the task's plan list. Save changes to update the original block without creating a copy. Delete the block and confirm to remove only that plan; the task and recorded focus history remain.

Task deadlines, calendar plans, and actual focus are stored separately. Changing a plan does not change the task deadline or recalculate past focus. Enter planned duration in minutes; decimals are accepted, with a minimum of one second. Enter dates and times in the device's local time zone. Changing the device time zone can change how a saved instant is displayed. System calendar exchange has additional duration limits described below.

Task lists sort by Urgent, High, Medium, Low, and None, retaining the existing order within a priority. Today keeps its scheduled and manual ordering. Filter Tasks by Inbox, project, tag, or completion status, or use search. Tap the task body for full details and then edit it. The checkbox changes completion status, and the completion message offers Undo. Ordinary task deletion and standalone tag management do not currently have complete UI controls.

Closing an ordinary editor with unsaved changes asks whether to discard them. Failed saves retain input for retry. If the workspace changes while an editor is open, close it and reopen the record in the current workspace. Private editors follow the locking rules under “Private vault.”

## Start focus and link a task

1. Open “Focus → Start,” select a task, or leave it as free focus without a task. You can start even when no tasks exist.
2. Choose a target duration and policy. The preparation page defaults to 45 minutes, with presets of 25, 45, 60, and 90 minutes and a 15–240 minute slider. A task's quick-focus action uses its estimated duration, or 25 minutes if no estimate exists.
3. Select Flexible focus and start. This policy allows pausing and resuming; paused time does not count as actual focus. Guard and strict policies have the additional requirements below.
4. Reaching the target does not stop recording. Complete focus or end it early to save the session. Ending focus does not automatically complete a task or create another calendar block. The completion review separately offers task completion or another session.
5. After free focus ends, link it to an existing task or create a task from the review. You can also defer linking and open the record in “Focus → History” later. Linking attributes the recorded time to that task without changing start/end times, pauses, or actual duration, and does not complete the task.

Only an ended session without a linked task can receive its first association. Once linked, it cannot be changed or cleared. In a synchronized workspace, only the originating device can link the session; other devices' records are read-only. Restored local terminal history can be linked without taking control of the source device's timer. End an active session before linking it.

For synchronized task association, upgrade the self-hosted server to the preview.3 source first. Older servers, including the preview.1 prebuilt bundles still offered separately, reject changes to terminal sessions. This release provides updated server source rather than new server binaries; see [server upgrades](SELF_HOSTING.en.md). If an older server rejects synchronization, retain local changes and check synchronization again after upgrading.

Statistics shows planned time, actual focus, and task completions for the last seven days or four weeks. Free focus retains its actual time. Planned time comes from calendar blocks and actual time from saved focus records, so they can differ. Private vault records do not enter ordinary statistics.

## Guard, strict focus, and vibration

| Default policy | Pause | Complete before target | End early | Outside the allowlist |
| --- | --- | --- | --- | --- |
| Flexible focus | Allowed | Allowed | Confirm and save | Not monitored |
| Deep Guard | Not allowed | Allowed | Wait 10 seconds in confirmation | Return reminder; exits after the first two count as interruptions |
| Strict focus | Not allowed | Not allowed | Wait at least 30 seconds and enter a reason | Return reminder; every exit counts as an interruption |

Before using guard or strict focus, set the project or Inbox app allowlist in “Focus → Rules.” Free focus uses the Inbox allowlist. Under “Settings → Focus and permissions,” grant usage access and permission to display over other apps, then return and check the status. Allowlists belong to the local workspace and are not uploaded; local backups include them, so check installed apps after moving to another phone.

Ending early saves actual time and the reason without completing the task. Canceling and reopening confirmation restarts the wait; a process restart also requires confirmation again. Guard policies provide reminders and records, not a system app lock, uninstall restriction, or protection against force-stop. Revoked permissions, process termination, and vendor background policies can interrupt monitoring.

“Settings → Focus and permissions → Focus vibration feedback” is on by default and saved locally. Starting, pausing, resuming, ending, reaching the target, and guard reminders can trigger vibration, subject to the policy, system settings, and hardware. Turning it off stops app-triggered vibration. Missing hardware or a failed platform call does not undo a saved record. Use the retry message in Settings or Focus if the native timer service fails. See [Focus modes](FOCUS_MODES.en.md).

## Use the focus desktop

The focus desktop is off by default. Enable it under “Settings → Focus and permissions.” Starting or resuming local focus then opens it automatically. Changing the switch, returning to the foreground, or restoring the timer service does not navigate there.

The desktop shows remaining time, state, Pactick, launchable system apps, and currently allowed apps. Tap an icon to launch an app; use the return button or Pactick icon to return to the client. Active ordinary and private sessions also offer an action to open the desktop. If automatic opening fails, retry it while the saved session continues. Reaching the target does not automatically end ordinary focus.

The switch is device-local and is not synchronized or restored from workspace backups. Flexible focus requires no extra guard permissions to use the desktop; guard and strict policies still require them. While the desktop is enabled, guard monitoring also permits system apps; disabling it restores the usual allowlist rules. It does not replace Android's default launcher, and Home, Recents, and other system entry points remain available. Private focus uses a generic title and its owning workspace's Inbox allowlist; opening the desktop does not unlock the vault.

## Manage task notifications

“Settings → Task reminders” has two independent, device-local switches, both on by default:

| Switch | When it applies | Content |
| --- | --- | --- |
| Pending task reminder | While the current workspace has open tasks; count changes update the same notification | Silent pending count without task content |
| Due and plan start reminders | When an open task reaches its due time or a scheduled plan reaches its start | One dismissible, generic notification without task names |

Standalone plans can also produce start reminders. Completed, canceled, or deleted tasks no longer schedule their deadline or linked plan reminders. Completed, canceled, or deleted plans no longer schedule a start reminder. Switches retain their values across workspace changes but do not move through synchronization, backups, or workspace copies.

Android 13 and later require notification permission. App notifications and the relevant notification category must also be enabled. An automatic permission request is not repeatedly shown after refusal; use the manual permission action here and check app notification settings and the scheduled reminder category separately. Pending reminders, scheduled reminders, and the foreground timer share app permission but have separate categories. Refusing notifications does not prevent local saves or flexible focus.

Scheduled reminders use inexact alarms. Power saving and vendor restrictions can delay them; they are not suitable for alarms that must fire precisely. Newly loaded events already in the past are not replayed. An event processed while notification permission or its category is off is not replayed after permission is granted. Reboot and package updates restore the latest local snapshot; after a system force-stop, reopen the app. Reminders do not contact the server themselves, so another device's changes must first synchronize locally. See [Scheduling and reminders](TASK_SCHEDULING_AND_REMINDERS.en.md).

## Connect an Android system calendar

This connection is off by default and needs no Pactick account. System events become ordinary plans in the current workspace, and ordinary plans can be written to the selected writable calendar. If account synchronization is enabled for that workspace, imported plans may upload to the Pactick server. The calendar account may also synchronize events to its provider. The private vault does not participate.

1. Prepare an existing calendar in an Android calendar app, then open “Settings → System calendar” and choose a calendar. Grant read permission when requested.
2. Select the calendar, read the data-flow notice, and enable synchronization. Writing or deleting also requires Android write permission and a writable calendar/event. A connection with only read permission can remain read-only.
3. Enabling it runs the first sync. The default window is the past 30 days through the next 180 days; choose 30, 90, 180, or 365 future days. Changes are combined and exchanged while the app is in the foreground, or use the immediate calendar sync action.
4. When both sides change or either side is deleted, choose the client or system version from the conflict list after reading which side will change or be deleted. Choosing the state of a missing side may delete the surviving copy. Closing the page does not resolve it automatically.
5. Disable system calendar synchronization to stop subsequent exchange. Imported plans and previously created system events remain. Choosing a different calendar does not automatically remove old-calendar copies.

Only ordinary plan titles, start/end times, and time zones are exchanged. Task deadlines, focus records, and private content are not exported. Existing system descriptions, locations, reminders, and attendees are not overwritten. Representable plans span at most seven days. Unsupported system events retain their original values and are skipped or shown as conflicts. See [System calendar integration](SYSTEM_CALENDAR.en.md) for recurrence, all-day, time-zone, and read limits.

Immediate exchange is not guaranteed outside the foreground, and a successful Calendar Provider write does not prove the account provider has synchronized over the network. Connections belong to a local workspace and are not transferred in backups or copies; configure them again on another phone. Connecting the same Pactick account to the same system calendar on multiple devices can create duplicates; use one device for that connection. Permission loss or read failure stops exchange and preserves existing plans. Fix access or calendar state, then retry.

## Private vault and independent encrypted backups

1. Tap the lock icon on Tasks, or open “Settings → Backups and workspaces → Private vault.” Set and confirm an independent password of 8–1024 characters. It is unrelated to the account password.
2. Unlock and create private tasks, categories, tags, deadlines, plans, and focus records. Private plan times use `yyyy-MM-dd HH:mm`. View and edit them inside the vault; they do not appear in the ordinary calendar or produce deadline/plan-start reminders.
3. Private focus requires a vault task, defaults to 25 minutes, and accepts 1–1440 minutes. It currently has no pause, guard, or strict policy. Only one ordinary or private session can run at once. The generic timer continues while locked; unlock its original workspace to see content or end it early.
4. Open Encrypted backup and save a private encrypted backup file through the system file picker. Confirm that it exists at the selected destination. Opening the picker locks the vault; that alone is not an export failure. Check the save result.
5. To restore, select “Restore encrypted private backup” on the vault's locked page, or open an encrypted backup file from the unlocked Encrypted backup page. Choose the file, enter the password used when exporting it, and validate/restore to a new local workspace. There is no need to set another vault password on the new device first. Successful validation creates a new workspace and retains the original. Open the restored copy through “Settings → Backups and workspaces → Open a retained workspace,” then unlock it.

Private content does not enter ordinary lists, search, statistics, system calendar exchange, or account synchronization. Notifications and the desktop use a generic “Private task” label. Leaving the foreground or vault page, switching workspaces, or locking manually clears the unlocked state and unsaved private input. Android screenshot protection is enabled before opening the page; if it cannot be enabled, the page does not open.

An independent encrypted backup is limited to 50 MiB and contains the parameters needed to decrypt it, but no password or plaintext key. A wrong password or damaged file leaves existing data unchanged and does not create a restored workspace. Repeated failures increase the retry wait. There is no password bypass. Changing a password requires the old one; existing backups retain the password used for their export.

“More → Move to private vault” is available only for eligible records in the original local workspace that were never attempted for synchronization and have no system-calendar exposure. Relationship constraints also apply. Disconnecting synchronization or a calendar does not erase history or reclaim backups and external copies. Moving a task out of the vault writes it to ordinary storage after confirmation and may upload it in a synchronized workspace. See [Private vault](PRIVATE_TASK_VAULT.en.md) for transfer and deletion rules.

## Full backups, moving phones, and uninstalling

Android automatic backup is disabled. Uninstalling or clearing app data deletes local workspaces, settings, and vault ciphertext. Keep exported files outside the app separately.

1. Under “Settings → Backups and workspaces,” export the current local workspace. After a successful save, confirm the file exists and keep another copy in a trusted location. Export multiple workspaces separately.
2. On the new phone, end local focus, select Restore from local backup, and choose the file. Successful validation creates and opens a new offline workspace, retains the original, and does not sign in or upload automatically.
3. Check tasks, plans, history, and unsynchronized changes. Unlock any private vault with its original password and check it too. Only consider clearing the old phone after confirming recovery and retaining another backup.

Full backups use `pactick-workspace` v2; old v1 backups remain supported. Files must be UTF-8, at most 50 MiB, with at most 100000 ordinary documents. Ordinary tasks, notes, history, and allowlists are plaintext; private content stays encrypted. Full restore validates the private envelope's format, and authentication happens when unlocking. Use independent encrypted restore to authenticate private contents before creating a workspace. Do not upload real backups to public issue reports.

Backups exclude account passwords, login tokens, server addresses, sync cursors, and local timer control. Restored active records do not take over the source timer; private active records become interrupted on first unlock. Configure system calendar connections, reminder switches, language, and the focus desktop for the destination device. Invalid formats, duplicates, or broken references prevent recovery. A failed local restore write rolls back and retains the original workspace. See [Local backups](LOCAL_BACKUPS.en.md).

Copying to a local workspace creates and opens an offline copy, stops current synchronization, and retains the original. Open a retained workspace to inspect earlier data offline. End local focus before restoring, copying, or switching workspaces. Exporting a local backup alone does not require ending ordinary focus.

## Optional account sync, sign-out, and deletion

The maintainer does not provide a public sync service. To exchange ordinary data across devices, prepare an HTTPS server maintained by you or a trusted administrator using [Self-hosting](SELF_HOSTING.en.md). Consult the relevant version's validation for deployment, recovery, and public-network compatibility.

1. End local focus and export the current workspace.
2. Open “Settings → Sync and devices → Sync settings” and enter the server's HTTPS site address, email, and password. For example, `https://sync.example.com` has no API path, credentials, query, or fragment; this example is not a service.
3. Leave copying/uploading local data unchecked by default. The first connection to that server/account opens a separate workspace and preserves the original; existing ordinary server data arrives through sync. Select copy/upload only when intentionally migrating and no workspace for that account exists on this device. It does not append another workspace into an existing one.
4. After signing in, check sync status and use the immediate sync action if needed. Pending or rejected operations mean the server may not have every change. Registration availability is controlled by the administrator; disabling registration does not block existing accounts.

Data, credentials, device registration, and synchronization state are separated by server and account. Export before changing servers; retained workspaces remain available offline. Offline editing/export continues and pending changes remain queued. Check the address, network, and certificate after connection failures, and sign in again after authentication expires. Active sessions from other devices are read-only; their originating device must end and sync them before a new ordinary session can start.

Signing out stops synchronization and retains local data; it does not delete the server account. Read any separate notice that remote revocation could not be confirmed. Exporting server account data requires a network connection, excludes unsent changes, and cannot be directly restored by local backup recovery. Server account deletion requires the current password and `DELETE`; it permanently deletes that account's data on the selected server and retains the local copy. It does not delete accounts elsewhere or clean administrator backups/logs. Revoking a device invalidates its login without remotely clearing its local data.

## Troubleshooting and feedback

| Situation | Action |
| --- | --- |
| Empty list or missing task | Check workspace, project/tag/completion filters, and date; a new installation is empty |
| Save failed | Keep the form, check the error, storage, or network, and retry; locking a private vault clears its unsaved input |
| Missing or delayed notification | Check the switch, app permission, and category; reopen after force-stop; inexact alarms can be late |
| Guard or strict focus cannot start | Check usage access, overlay permission, and existing sessions; flexible focus needs neither permission |
| Desktop did not open | Keep the recorded session and retry opening the desktop instead of starting another session |
| System calendar did not change | Check enabled state, workspace/calendar/window, foreground state, permissions, and conflicts |
| Private password or backup failed | Retain ciphertext and the file; wait before retrying the export-time password; no bypass recovery exists |
| Local workspace cannot open | Retry and record the complete error; do not first uninstall or clear the only copy |

Report ordinary issues in [Issues](https://github.com/2354634715/Pactick/issues) with the app version, device, Android version, steps, expected behavior, and result. Use sample data or redact private details. Do not publish real backups, databases, passwords, or tokens. Report security issues privately using [Security reporting](../SECURITY.en.md).

“Settings → About Pactick” shows app and third-party licenses. The project uses a Source Available license; see the [License FAQ](LICENSE_FAQ.en.md) for distribution terms.
