[简体中文](LOCAL_BACKUPS.md) | English

# Local backups and workspace migration

Backup export and import both work offline. Import creates a new local workspace and preserves the original without signing in or automatically uploading data.

## Backup contents

Backups are UTF-8 JSON files with format identifier `pactick-workspace`. The current export version is `2`; version `1` is still accepted. The maximum size is 50 MiB. A file contains:

- Projects, tasks, recurrence rules, tags, plans, daily items, focus policies, focus records, interruptions, and reminders.
- The latest locally saved content, deletion markers, and changes not yet synchronized or rejected by the server.
- Portable settings such as theme, dynamic color, legacy notification preference (`notifications_enabled`), and focus app whitelists. Task reminders, deadline and plan-start reminders, focus vibration switches, and native snapshots remain device-local and are excluded. Language selection, system calendar connections, and the focus desktop are covered in the next section.

Backups contain no login passwords, access tokens, refresh tokens, server addresses, synchronization cursors, or synchronization operation IDs from the original server. The imported workspace retains no connection or synchronization credentials for the original server.

Backups omit local active-focus control markers. Restored or copied local workspaces retain original session content. Unfinished original sessions appear as read-only records, do not start a local timer service, and cannot have their state changed locally. A copy can start new local focus. Restoring a copy does not end focus on the source device.

Ordinary tasks, notes, and portable settings are plaintext JSON. Version 2 additionally carries separate private-vault ciphertext without decrypting private content. Store backups in trusted locations. Do not commit real backups to public repositories or attach them to issue reports.

## State retained on the current device

System calendar connection settings, system event IDs, event-to-plan links, confirmed snapshots, idempotency markers, installation IDs, and exposure history are excluded from backups and workspace copies. Imported ordinary plan content is still retained in backups. After restoration, select a calendar and confirm the connection again in the new workspace; permissions are checked against the current device's grants. Restoring, copying, or deleting a workspace does not retract events already written to the system calendar or its provider. See [system calendars](SYSTEM_CALENDAR.en.md) for connection scope and duplicate-copy limitations.

Language selection and the focus desktop switch are preferences of the current installation and are excluded from backups. Import does not overwrite them; copies opened in the same installation continue to use this device's settings. The focus desktop defaults to off in a new installation and must be enabled again. Android permissions and default-app selections are not restored by workspace backups either. Focus records are retained, but the original device's desktop interface, timer service, and control permissions are not restored.

## Import and restoration

Before import, the restoration service validates the format version, field types, record IDs, duplicates, and references. The destination must be a new workspace. All writes use one SQLite transaction: any failure rolls back, leaving no partially written workspace and overwriting no original data.

Restoration uses the latest document state in the file. Old synchronization operations remain only as backup records of unsynchronized changes and are not sent to other servers. Deleted content retains its deletion markers and is omitted from normal lists.

The restored workspace has no synchronization session or queue. Connecting and uploading require separate selection in synchronization settings. Portable display preferences are stored in the restored workspace settings; import itself does not overwrite current global app preferences. When a restored or copied workspace opens, task reminders are recalculated from its `open` count using this device's existing switches. Source-device notification permissions, channel settings, and native snapshots are not inherited.

The ordinary portion has no password protection. The private task vault uses authenticated encryption. Its backup carries password-derivation parameters and ciphertext and remains locked after restoration; only the original password unlocks it. See the [private task vault](PRIVATE_TASK_VAULT.en.md) for wrong passwords, corrupt ciphertext, and standalone private restoration. Private-focus local control markers do not migrate through backup or copying.

## Workspace copying and version migration

“Copy to a local workspace” preserves the source and creates a new offline copy for retaining data before retiring a service or switching servers. The copy can be exported again.

Older clients identified cloud workspaces only by user ID. Before upgrading to server namespaces, confirm that the original signed-in session belongs to the same server as the destination namespace. This migration copies business records, the pending queue, and the original server cursor while preserving the old workspace. An existing destination is neither merged nor overwritten.

Copying to another server creates new synchronization operation IDs and resets document versions and cursors. Deleted parent records referenced by history are first created at the destination and then retained as deleted. Recurring tasks are created together with recurrence rules before rule references are attached. If content cannot be converted into valid references for the new server, copying reports an error before beginning the transaction and leaves the source unchanged.

## Development API and validation

`WorkspaceBackupService` provides:

```dart
final backups = WorkspaceBackupService(documentStore);
final json = await backups.exportJson(selectedAccountId);
final restoredAccountId = await backups.restoreJson(json);
final copiedAccountId = await backups.copyToLocal(selectedAccountId);
```

`DocumentStore.copyWorkspace(sourceId, newTargetId, enqueueForSync: true)` is for uploads to a new server explicitly selected by the user. It does not connect to the network. `migrateLegacyAccount(legacyUserId, namespacedId)` is only for upgrades with verified server identity.

`client/test/workspace_backup_test.dart` runs the same backup, restoration, cross-server operation generation, deleted-reference, recurrence-reference, and input-validation scenarios against memory storage and real SQLite. SQLite triggers inject mid-operation failures to verify full transaction rollback.
