[简体中文](TASK_SCHEDULING_AND_REMINDERS.md) | English

# Plan-slot editing and timed reminders

## Change a task's schedule

Open a plan slot in the calendar and select “Edit plan slot”, or select its record in the task details' plan-slot list. The editor can change the date, start time, duration, and associated task. Removing the association requires a standalone event title.

Saving retains the original plan ID and updates the corresponding synchronization document without creating a duplicate slot. Task deadlines, task content, and actual focus records are stored separately. Plan edits do not recalculate historical focus duration. “Schedule time” still creates new slots; a task may have multiple slots.

Selecting and confirming “Delete slot” deletes only that plan. The associated task and actual focus records are preserved, including the original plan ID in historical focus. A storage failure retains editor input and the original plan for retry. If the workspace changes after the editor opens, saving and deletion fail; close it and reopen it in the current workspace.

Plan duration is entered in minutes and may contain decimals, but must be at least one second. Dates and times are entered in the device's local time zone and stored as fixed instants. A time-zone change changes the local display; it does not move a saved plan to the same wall-clock time in the new zone.

## Android local reminders

Settings → Task reminders provides two independent local switches, both enabled by default:

| Switch | Trigger and content |
| --- | --- |
| Task reminders | One silent ongoing notification shows only the pending count when the current workspace has tasks with status `open` |
| Deadline and plan-start reminders | One dismissible generic notification appears when an unfinished task reaches `due_at`, or a `scheduled` plan reaches `starts_at` |

Standalone events also generate plan-start reminders. Completing, canceling, or deleting an associated task cancels both its deadline reminder and associated plan reminders. Completing, canceling, or deleting a plan cancels that plan's start reminder. After removing a task association, the standalone event continues to remind at its own start time.

The task editor's deadline includes a time. Selecting only a date without changing the time uses `00:00`. Select a deadline time as well for daytime reminders. Deadline reminders trigger at the deadline; there is currently no configurable advance notice.

Both switches affect only the current device and survive sign-out and workspace changes. They do not transfer through synchronization, workspace backup, or workspace copying. The Android native component stores only the current workspace ID, event IDs, times, reminder types, and processed-event records. It stores no task titles, notes, or project names and does not connect to the server itself.

Notifications require app notification permission and the relevant notification channel. Android 13 and later require notification permission. Automatic prompting occurs at most once; after denial, use “Check / request notification permission” to request it explicitly. The system channels are “Task reminders” and “Deadline and plan reminders”. “Timed reminder channel settings” opens the latter. Disabling one channel does not affect the other. Local tasks and plans can still be saved when notifications are unavailable.

## Timing, recovery, and limits

Timed reminders use `AlarmManager.setAndAllowWhileIdle`, registering only the next pending trigger time with the system. After triggering, due events are combined into one notification and the next time is registered. The current implementation requests no exact-alarm permission and uses no background polling. Android may batch or delay inexact alarms; battery saving, background restrictions, and vendor policies can also affect delivery time. This feature is unsuitable for alarms requiring strict punctuality. See the [Android alarm documentation](https://developer.android.com/develop/background-work/services/alarms).

Each event/time pair is processed only once. Newly loaded overdue events are not replayed when first enabling reminders, loading old tasks, or changing a time into the past. Previously registered unprocessed events may be combined after system delay or restart recovery. If notification permission or the channel is disabled when an event becomes due, it is recorded as processed and is not replayed after permission is granted.

After device boot, an in-place app update, or system time/time-zone changes, the receiver rebuilds the nearest reminder from the local snapshot. Saving tasks or plans, completing tasks, receiving synchronized data, and changing workspaces update the snapshot and cancel reminders from the old workspace. New data not synchronized to this client does not affect its local alarms.

Reopen the app after system force-stop to recover reminders. Uninstalling or clearing data deletes local reminder settings and snapshots. The notification tray retains only the latest timed reminder. Tapping it opens Tasks; notification content includes no corresponding task name.

## Validation scope

Automated checks cover plan ID retention, reassociation, preserving tasks and history after deletion, write failure, event filtering, time changes, cancellation on completion/deletion, local switch persistence, and platform-failure retry. Actual Android delivery time, boot broadcasts, notification permissions, vendor battery policies, and notification display must be assessed against device acceptance for the corresponding final APK. The 2026-10-17 implementation record includes no device testing or release publication. See the corresponding release notes for each version's results.
