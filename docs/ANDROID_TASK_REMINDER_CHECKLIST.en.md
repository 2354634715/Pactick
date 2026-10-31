[简体中文](ANDROID_TASK_REMINDER_CHECKLIST.md) | English

# Android device checks for default ordering and task reminders

Updated: 2026-10-31. Applies to `0.3.0-preview.3+8`. This checklist records steps to perform, not completed device results. Recheck the final signed candidate for a formal release.

On 2026-10-17, pending checks were added for plan-block editing and deadline/plan-start reminders. Only local automated checks were run for that change; no device testing or Release publication was performed. See [Plan-block editing and scheduled reminders](TASK_SCHEDULING_AND_REMINDERS.en.md) for operations and trigger restrictions.

## Preparation and records

Use a disposable local workspace and demonstration tasks. Do not use a device holding the only copy of personal data for data clearing, uninstallation, or fault testing. Cover Android 8–12 and Android 13 or later separately. Rules for dismissing ongoing notifications also require Android 14 or later. The device operator handles system notification authorization, reboots, force stops, and update installation.

For each run, record the source commit or snapshot identifier, APK SHA-256, signing certificate fingerprint, device model, Android version, notification permission and channel states, operations, results, and exceptions. Use demonstration data in screenshots and obscure private content from other apps in the notification area.

Local automated checks on 2026-10-11 recorded no static-analysis issues, 151 passing Flutter tests, and a successful debug APK build. These are historical results for the older artifact. See [validation scope](PROJECT_STATUS.en.md#compatibility-and-validation-scope) for the current version. These results do not prove that the device checks below passed or that formal signing or publication was completed.

## Default ordering

1. On Tasks, create one task at each priority in this order: None, Low, Medium, High, Urgent. The list must show Urgent, High, Medium, Low, None. Equal priorities retain `rank` order, then task-ID order for equal `rank`. Change one task's priority and confirm immediate reordering. Exit the process and reopen the app; ordering must still apply.
2. Check Inbox, projects, tags, search results, and completed tasks, then the task selectors in Calendar and Focus. They must use the general task ordering without changing task content, deadlines, or plans.
3. Give two tasks different start times today. Confirm that Today orders them by planned time. Moving unplanned tasks up/down or dragging them must continue to work. Raising priority must not override planned time or manual order.

## Task reminder in the notification area

| ID | Operation | Expected result |
| --- | --- | --- |
| REM-01 Defaults and permission | Open a fresh demonstration installation, confirm an empty workspace, then create the first task. Test both allowing and denying permission on versions that require it | The switch is on by default. An empty workspace shows no reminder and does not automatically request permission. With open tasks and notification permission, one silent reminder appears. Denial does not prevent saving tasks; later count changes do not repeatedly show automatic permission prompts. Permission can be requested manually in Settings |
| REM-02 Counts and completion | Create a second task, complete tasks individually, then reopen one completed task | There is always at most one task reminder, with an updated count. Completing all tasks removes it; reopening a task restores it. Only `open` tasks count; existing `completed` or `cancelled` test data is excluded |
| REM-03 Content and tapping | Inspect the notification and lock screen. Tap the notification with the process stopped, the app in the background, and Settings open | The notification contains a generic reminder and count, with no task titles, notes, or project names. Tapping opens Tasks and does not remove the reminder while open tasks remain |
| REM-04 Unsaved forms | Modify a task form without saving, background the app, then tap the task reminder | The existing exit confirmation still applies. Canceling exit keeps the input; confirming discard returns to Tasks. The draft is not discarded without confirmation |
| REM-05 Switch and restart | Turn off the switch under Settings → Task reminders, exit and reopen the app, then enable it again | Turning it off removes the reminder immediately and remains off after reopening. Re-enabling restores it if the system permits. A settings-write failure preserves the previous switch value and shows a retryable error |
| REM-06 System channels | Disable app notifications and the Task reminder channel separately, then return to the app. Restore authorization and return again | Settings reflects the actual restriction and does not treat the enabled app switch as permission. No reminder is shown if app notifications are allowed but the channel is disabled. Returning to the foreground rechecks restored permission. Focus notifications use a separate channel |
| REM-07 Workspaces and backups | Switch between two demonstration workspaces with different open-task counts, then restore or copy a demonstration backup | The old reminder is canceled first and the new workspace's count is shown. Empty workspaces do not retain the old count. Restore/copy preserves the original workspace, does not connect to a server, and uses this device's reminder switch. Backups do not carry the new reminder switch or native snapshots |
| REM-08 System dismissal | Dismiss the reminder on a device that allows ongoing notifications to be dismissed, then change the open-task count or return to the foreground | The same reminder is shown again. Changing only a title or priority without changing the count does not guarantee immediate restoration. For lasting suppression, disable the reminder switch or system channel |
| REM-09 Process and device | With open tasks, exit the process, reboot and unlock the device, then force-stop and reopen the app | Record persistence of already displayed notifications and restoration through startup broadcasts separately. Reboot reads the most recently saved count snapshot. After a force stop, reopening the app is required for restoration. Do not claim continuous operation or server fetching while stopped |
| REM-10 Upgrade and sync | Update using a controlled candidate with the same package name and certificate and a higher build number. While this app is closed, change tasks on another test device, then reopen and sync | The update restores the reminder from the local snapshot and preserves a saved off setting. Local sync then uses the new count. The reminder itself does not connect to the server. Check deadline and plan-start reminders separately below |

Perform REM-05's real storage-failure test only in a disposable environment. If there is no safe, reproducible failure condition, mark it unverified; an automated failure test does not replace a device result. REM-10 requires a candidate with a higher build number. Two APKs both numbered 5 cannot establish update acceptance for this check.

## Plan editing and scheduled reminders

All items below are pending device checks. Inexact alarms may be affected by power saving and system restrictions. Record the difference between actual and configured trigger times; a late notification must not be recorded as precise on-time delivery.

| ID | Operation | Expected result |
| --- | --- | --- |
| SCH-01 Edit and delete | Open an existing plan from Calendar and from task details. Change its date, start time, duration, and linked task, then delete one block | Editing updates the original block without creating a duplicate. Task content, deadlines, and actual focus records remain. Deletion requires confirmation and removes only the selected plan; canceling retains it |
| SCH-02 Defaults and triggers | Allow notifications, set a future task deadline and plan start, and create a standalone event | The scheduled-reminder switch is on by default and independent of the silent-count switch. All three events are scheduled locally. Generic notifications do not show titles, notes, or project names; tapping opens Tasks |
| SCH-03 Changes and cancellation | Before an alarm fires, change its deadline or start time, then complete, cancel, and delete tasks and plans separately | Changing time prevents the old time from firing. Completing or canceling a task removes its deadline and linked-plan reminders. Deleting a plan cancels only that plan's reminder. Title-only or priority-only changes do not reschedule due notifications |
| SCH-04 Permission and switches | Deny notification permission, disable the Deadline and plan reminders channel, and disable the local scheduled-reminder switch separately. Restore and reopen | Local saves still succeed, and Settings reflects channel restrictions. Events blocked at delivery time are not delivered retroactively after authorization is restored; new times can still be scheduled. The off setting survives restart. Silent-count reminders use an independent switch |
| SCH-05 Reboot and clock | Register future events, exit the process, reboot and unlock, then change the device time and time zone | The next alarm is rebuilt from the local snapshot. Each event timestamp is processed at most once. Time-zone changes affect local display only and do not move stored instants. After a force stop, reopening is required for restoration |
| SCH-06 Workspaces and delay | Switch from a workspace with pending events to an empty one. Separately, register several nearby events under power saving and wait | Switching immediately cancels the old snapshot, alarms, and notifications, including when an old permission request has not returned. Delayed delivery merges due events into one notification, then registers the next time |
| SCH-07 Expired events | Load overdue tasks when first enabling reminders, move a future time into the past, then observe a previously registered future event after it becomes due | Newly loaded overdue events and times moved into the past are not immediately delivered retroactively. Previously registered, unprocessed due events are handled when the system actually triggers them. A timestamp does not notify twice |

## Results and failure handling

Record Passed, Failed, or Unverified and supporting evidence for every item. Unverified items remain incomplete. If a notification is missing, first check the workspace count, reminder switch, app notification permission, channel, and whether the app was force-stopped. Retry platform-update failures from Settings. Once a local task save succeeds, do not create duplicate tasks to work around a notification failure.

Record notification display, lock-screen behavior, startup broadcasts, and background restrictions separately for each model. One device passing does not establish compatibility with every Android version. For product operations, see the [getting-started guide](GETTING_STARTED.en.md); for native/client data flow, see [project architecture](PROJECT_ARCHITECTURE.en.md#task-reminders-in-the-notification-area); for formal-package conditions, see the [release process](RELEASING.en.md#android-preview-apk).
