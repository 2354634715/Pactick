# Android system calendar synchronization

[简体中文](SYSTEM_CALENDAR.md) | English

A system calendar connection exchanges events between the Android calendar provider and ordinary plan blocks in the current workspace. Connections are off by default and do not require a Pactick account. The private task vault does not participate.

## Before connecting

Each local workspace selects one existing, visible, readable system calendar. The client does not create system calendar accounts, sign in to calendar accounts, or configure their network synchronization.

After connection, system event titles and times become ordinary client plans. If account sync is enabled for the current workspace, those plans follow the existing upload path to the configured Pactick server. System events written by the client may also be synchronized to the calendar account's service provider. Confirm that both data flows are acceptable before connecting.

Reading requires Android `READ_CALENDAR` permission. Writing or deleting system events requires `WRITE_CALENDAR` permission and write access to the selected calendar. Organizer or attendee permissions and the system provider can still make an individual event read-only within a writable calendar. The system permission screen appears only after a user actively connects or requests permission. Refusal does not affect local tasks, plans, focus, or backups.

## Connect and stop a connection

1. Open **Settings → System calendar** and choose **Choose a system calendar**. The client requests system read permission if it is missing.
2. Select an existing calendar. The list shows its name, account display information, and whether it is writable. Only visible, readable system calendars are listed.
3. Review the data-flow explanation and confirm **Enable sync**. If the calendar is writable but write permission is missing, the client requests it. The connection can remain read-only if read access is granted but write access is not. A successful enable immediately runs the first sync and establishes event-to-plan associations.
4. Choose a future range of 30, 90, 180, or 365 days as needed. After an associated record is edited in the client or system calendar, foreground changes are coalesced with a two-second delay. Checks resume when the app returns to the foreground; **Sync calendar now** also starts a check.
5. Turn **System calendar sync** off to stop subsequent reads and writes. An atomic operation already submitted to the system provider may still complete. Imported plans and created system events remain in place.

Changing calendars does not delete old calendar events in bulk. The new connection processes current ordinary plans within its scope and may create corresponding new system events; copies in the old calendar remain. Each workspace stores its own connection and associations; only the current workspace is processed. Restoring or copying a workspace does not inherit the original device's calendar connection. Select a calendar and confirm the connection again; Android permission is checked against its current grant and requested only if missing.

The connection does not start a persistent background service. Immediate exchange is not guaranteed while the app is closed or in the background; checks resume when the app opens or returns to the foreground. Android, the calendar account, and system settings determine when the system calendar exchanges data with its service provider.

## Fields and scope

| Content | Behavior |
| --- | --- |
| Ordinary plan title, start time, end time, and time zone | Updated in both directions. New system events become independent ordinary plans without creating tasks or changing task contents. |
| All-day events | Represented by the corresponding start/end date interval, retaining an exclusive end date. The client still uses plan blocks and does not add separate all-day reminders. |
| Recurring events | Each occurrence in the window has its own association. Events with `RRULE` are changed or canceled through a single-occurrence exception without rewriting the series. Occurrences specified only through `RDATE` are currently read-only unless they already have an independent exception record. |
| Descriptions, locations, reminders, and attendees | Not imported into plans and not overwritten when titles or times are synchronized. |
| Task deadlines and focus history | Not exported as system events. Completing a task does not mean deleting its system event. |
| Private tasks, plans, and focus | Not read, imported, or exported. Their titles and times are not sent to the system calendar. |

The default discovery window spans the past 30 days and the next 180 days, including today and the whole final local date of the future range. The past range is fixed at 30 days; the future range can be 30, 90, 180, or 365 days. New associations cover ordinary plans and system events that intersect the window. Absence from a window scan does not establish deletion; associated events must be checked by identifier.

An ordinary plan must end after it starts and span at most seven days (168 hours). System events with a title longer than 500 UTF-16 code units or an unrepresentable interval are skipped and counted without truncating their times or deleting their originals. If an already associated event becomes unrepresentable, both sides are retained with an unsupported-format conflict rather than overwriting the client plan.

Timed system events use a compatible IANA time-zone identifier. A missing source zone uses the device zone; an unrecognized or fixed-offset zone is represented as UTC at the same instant without shifting the start or end. All-day values use the device's local dates. Edits such as title changes that preserve time-zone semantics retain the provider's original start/end zone metadata.

The configuration API limits the past days, future days, and today together to 400 local dates. The current interface allows at most 396 local dates. Native reads also have a hard limit of 402 × 24 hours to accommodate local-date windows and daylight-saving changes. A read handles at most 10000 events. Exceeding a limit or receiving an incomplete read fails; a partial result must not be treated as a complete snapshot for deletion handling.

## Conflicts and deletion

After a successful exchange, the client stores the confirmed content and compares each side's current content against it on the next run. User-edited titles and other text remain as entered when the interface language changes. An empty system title uses a stable “—” in the client; editing only its time or changing language does not write that placeholder back to the system title.

| Result | Action |
| --- | --- |
| Only the system event changed | Update the associated ordinary plan. |
| Only the client plan changed | Update the associated system event when write access is available. A read-only connection does not overwrite the event. |
| Both sides have the same content | Confirm that content without creating another event. |
| Both sides changed to different content | Preserve both and show a conflict for review. |
| Either side was deleted or canceled | Show a conflict for review without automatically cascading deletion. |
| Both sides were deleted or canceled | Remove that association without recreating either record. |

An associated all-day event also requires review as a both-sides-changed conflict when the client time zone differs from its last confirmed value; it is not automatically converted into a timed event. The all-day property is stored only in the local association. Ordinary cloud plan payloads have no separate all-day field, so identical all-day representation across devices and time zones is not guaranteed.

**Keep client version** uses the current client plan: it recreates a missing system event, or deletes the associated system event if the client plan was deleted. **Keep system version** uses the current system event: it reimports a missing client plan, or removes the associated ordinary plan if the system event was deleted. Handling a plan does not delete its task or historical focus records.

After a conflict choice, the client reads both sides again. A choice is not applied to new content if the previous conflict identifier no longer matches. The selected calendar and event version are also checked before a write. Results that require changing a system event are unavailable without write permission. A failed read, revoked permission, missing calendar, or changed calendar identity stops the exchange; these conditions do not mean all events were deleted. Existing plans and associations remain available after failure. Resolve the cause and retry. The client database and system calendar do not share one transaction: individual updates completed earlier in a run may already be saved. Retry resumes through associations and idempotency markers rather than implying a rollback of the whole run.

## Private tasks and external copies

An ordinary task or exclusive plan that has been imported, associated, or attempted for export through a system calendar leaves local exposure history. Such a task cannot be moved directly into the private vault. Disconnecting, disabling the connection, or deleting a plan does not clear that history. Exposure markers are saved before an exchange is attempted and remain when the write result is uncertain or an operation fails. The system calendar and its service provider may retain the original event; moving content into the vault cannot recall external copies. See [private task vault conversion](PRIVATE_TASK_VAULT.en.md#convert-between-ordinary-and-private-tasks) for migration conditions and transaction checks.

## Local state and maintenance

System events written and marked by another Pactick workspace are not automatically imported into the current workspace, preventing account contents from being mixed.

Connection settings, event identifiers, confirmed content, and idempotency markers are local association state. They do not enter ordinary sync payloads or migrate through workspace backup or copy. Workspace connection state uses `system_calendar_sync_v1`; the local installation identifier uses `system_calendar_installation_v1`, and exposure history uses `system_calendar_exposed_v1`. Ordinary plans retain the existing `plan_block` contract; calendar association adds no cloud event fields. See the [entity contract](ENTITY_SCHEMAS.en.md#plan_block) for field constraints.

Calendar and event identifiers are assigned by each device's calendar provider. Those identifiers cannot reliably match external events without Pactick idempotency tags across devices. Connecting the same calendar on several devices using the same Pactick account can create duplicate ordinary plans or system-event copies. Enable the connection on only one device for a given account and system calendar. Reconfigure after moving to another device or clearing system calendar data. Pactick tags help identify the same exported plan, but third-party providers may discard them; exact deduplication across devices or providers is not guaranteed.

Implementations must read and write local documents using an explicit workspace so late results from an account or workspace switch cannot enter the new workspace. New system events use stable idempotency markers to prevent duplicate insertion after a provider write succeeds but saving the client checkpoint fails. The native layer uses the Android calendar provider and checks original values before updating rather than blindly overwriting changes with the last write.

Both the interface and native errors require Chinese and English translations; see [localization](LOCALIZATION.en.md). Event titles, calendar names, and calendar-account display information retain their system or user-entered text and are not translation keys.

## Validation scope

Sync logic tests should cover first connection, updates in both directions, read-only access, conflicts, explicit deletion resolution, events outside the window, permission failure, retries, workspace switching, and private-data isolation. Android device checks must separately cover denied and revoked permissions, edits in the system calendar, recurrence exceptions, all-day and daylight-saving behavior, account sync timing, and vendor calendar-provider differences.

Unit tests, widget tests, and APK compilation do not prove those device behaviors. Validation records must identify the actual device, permissions, and calendar account type. Successful local provider access must not be reported as completed network synchronization with a calendar service provider.
