[简体中文](FOCUS_MODES.md) | English

# Focus modes, focus desktop, and vibration feedback

Focus can start immediately or with a pending task selected from the current ordinary workspace. Without a task, it is recorded as “Free focus”; creating a task first is unnecessary. The default UI allows 15–240 minutes. Task deadlines, calendar plans, and actual focus records are stored separately. Recording continues after the target time. Select “Complete focus” to save actual time; completing focus does not automatically complete the associated task.

## Free focus and task association

The focus page starts without a selected task. Before starting, choose a pending task under “Linked task (optional)” or switch back to “Free focus (no task yet).” A taskless session still follows the selected flexible, guard, or strict policy. It does not bypass permissions, pause or early-end rules, or restrictions caused by an active session on another device.

After completing free focus, select “Linked task” in the review, or open the record later under History. Only previously unassigned sessions in `completed`, `abandoned`, or `interrupted` state allow a first task association. Select an existing ordinary task or create one, then select “Save link.” Completed tasks are also valid targets. Linking changes only `task_id`: original start and end times, pause history, actual duration, interruption and departure counts, session status, and total focus statistics remain unchanged. Actual time is attributed to the selected task without changing its completion status. An existing association cannot be replaced or cleared; this entry cannot add an association to an active session.

In a synchronized workspace, only the device that started the session can save the association, and the target task must be undeleted and belong to the same account. An offline local copy may associate its terminal history without acquiring timer ownership of the original session. Private tasks are absent from the ordinary focus association list. A save failure preserves the selection for retry. If the workspace changes or the task is deleted, select a valid record and task again. Synchronizing this change requires a server that supports first task association for terminal sessions. A successful local save does not mean an older server has accepted the change; check sync status.

## Default policies

| Policy | Pause | Complete before target | End early | Apps outside the whitelist |
| --- | --- | --- | --- | --- |
| Flexible focus | Allowed | Allowed | Confirm to save as ended early | Not monitored |
| Deep guard | Not allowed | Allowed | Wait 10 seconds on the confirmation page | Show a return reminder; departures after the first two count as interruptions |
| Strict focus | Not allowed | Not allowed | Wait at least 30 seconds and enter a reason on the confirmation page | Show a return reminder; every departure counts as an interruption |

Strict rules are checked in both the UI and `AppController`. Direct calls to pause or complete early are also rejected and leave the original focus session unchanged. Canceling early-end confirmation clears the countdown; confirming again requires a new wait. The wait uses an in-process monotonic clock, so changing system time does not shorten it. A process restart requires confirmation and waiting again.

“End early” records actual time and the reason as `abandoned` and does not complete the task. If saving fails, the confirmation page preserves input and allows retry. Timer or vibration platform failures do not undo saved focus records. When stopping or recovering the system timer service fails, Settings displays a retryable message. Returning to the foreground reconciles state and retries native-service recovery or cleanup.

## Android whitelist and permissions

Guard and strict modes require Usage access and Display over other apps. Grant them on the focus page or under Settings → Focus and permissions before starting. Normal mode needs neither permission. Whitelists are stored locally by workspace and project. Tasks without a project and free focus use the Inbox whitelist; package names are not uploaded.

When the Android foreground service detects a foreground app outside the whitelist, it displays a return reminder at the top of the screen and records the departure count. Returning to a whitelisted app, locking the screen, or pausing hides the reminder. If permissions become invalid, the reminder may be unavailable; the app does not treat that as having blocked other apps.

Strict mode restricts focus operations offered by this app. It provides no device administration, system app lock, or uninstall restriction. System settings, force-stop, restart, and vendor background limits can still interrupt monitoring. Add any necessary phone, map, or authenticator apps that are not already allowed to the current task's whitelist before starting.

## Android focus desktop

Settings → Focus and permissions → Focus desktop is off by default and is shown only in the Android client. The switch is saved in the device-wide `focus_desktop_enabled` setting and retained across workspaces and accounts. A missing value or any value other than `true` disables it. The preference is not synchronized or transferred through workspace backups or copies. A save failure retains the previous value; select “Retry saving focus desktop settings.” If the preference was saved but Android configuration failed, select “Retry applying focus desktop settings.”

When enabled, starting a new local focus session or resuming a paused session opens the desktop automatically. Changing the switch, returning to the foreground, recovering the timer service, or editing the whitelist does not open it automatically. Both ordinary and private focus support the feature. In normal mode it adds no requirement for Usage access, Display over other apps, or selection as the default launcher. Guard and strict modes still require the guard permissions described above.

The desktop shows Pactick, system apps, and apps allowed for the current session. System apps are identified by Android's system or updated-system application flags. The allowed session apps combine the policy's app list with the task project's local whitelist; tasks without a project and free focus use the Inbox whitelist. The list contains only enabled, launchable applications that Android can query for the current user. System services without a launcher entry are omitted. Pactick retains a dedicated entry, and other apps are sorted by their app labels. Labels and icons come from Android; application names are not translated or rewritten.

While the focus desktop is enabled, guard monitoring also allows system apps so that opening a system app from the desktop does not trigger an outside-whitelist reminder. Disabling the desktop restores the previous whitelist monitoring rules. Each launch rechecks the current session and allowed apps. Whitelist changes update the list through the current timer service. Removed, disabled, or unlaunchable apps show a message, and the user can return to the client. If the app list fails to load, the desktop offers a retry action.

The ordinary focus page and the active-focus areas of the private task vault offer “Open focus desktop.” An automatic launch failure does not undo saved focus records: in-app timing continues, and “Retry opening focus desktop” is available. After returning to the client, the same entry opens the desktop again. The desktop opens only while a local timer service exists and the feature is enabled; it does not use a completed session's app list.

The desktop displays the remaining time and running or paused state, with a button to return to Pactick. Reaching the target does not automatically complete an ordinary focus record. After the session ends, the switch is disabled, or a different session takes over, the old desktop closes on its next state check or when it becomes visible again. An external app that is still in the foreground is not forcibly replaced when the session ends.

The focus desktop is a dedicated in-app launcher. It does not register as Android Home, replace the default launcher, or provide a system app lock. Home, recent apps, notifications, and other system controls can still leave the desktop; the feature does not mean Android has prohibited apps outside the whitelist.

## Vibration switch

Settings → Focus and permissions → Focus vibration feedback is enabled by default and stored only on this device. Disabling it stops app-initiated focus vibrations and persists across restart. Save failure retains the original value.

When enabled and the policy's `notification_mode` is `vibrate` or `sound_and_vibrate`, short vibration occurs on start, pause, resume, completion, early end, reaching the target, and the first departure from a whitelisted app. Reaching the target uses a longer segmented pattern. Normal service recovery for the same session does not repeat start feedback or previously delivered target feedback. `silent` and `sound` policies do not invoke vibration. This change adds no policy notification-sound player.

Android declares `VIBRATE` and supplies system vibration attributes for the purpose. Tasks and timing remain usable without vibration hardware, under system suppression, or on call failure. Actual feedback depends on system settings. See [Android haptic APIs](https://developer.android.com/develop/ui/views/haptics/haptics-apis).

## Private tasks and validation scope

The private task vault uses separate locally encrypted focus records. The native service and lock screen receive only generic names such as “Private task”, never private titles, notes, or categories. A private focus desktop receives no private title, task ID, or category and uses the Inbox whitelist from the workspace that owns the session. Switching workspaces does not substitute the new workspace's whitelist. Opening it from a locked private vault does not unlock private content. Desktop text follows the client's language choice, while app labels retain the text provided by Android. See the [private task vault](PRIVATE_TASK_VAULT.en.md) for limits.

Ordinary focus, including free focus, and private focus cannot start simultaneously. Private focus still requires a pending task selected inside the unlocked private vault. Its records do not enter a synchronized workspace through the ordinary focus association entry.

The 2026-10-17 implementation record includes no Android device acceptance. Automated checks cover controller rules, early-end confirmation, feedback preference persistence, and platform failure handling. Actual vibration, lock screen, background recovery, and vendor permission behavior must be assessed against device acceptance for the corresponding final APK. See each release's notes for verified and unverified scenarios.

Focus desktop widget or controller tests do not establish Android device acceptance. Actual app icons and system-app classification, launching and returning from external apps, Home and recent apps, background limits, system language, and large text still require verification on target devices.
