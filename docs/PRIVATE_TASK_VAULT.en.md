[简体中文](PRIVATE_TASK_VAULT.md) | English

# Local private task vault

The private task vault uses a separate password to store private tasks, categories, tags, plans, and focus records for the current workspace.
These records reside in local ciphertext tables, outside ordinary task tables, synchronization queues, and server APIs.
The vault requires no synchronization account or network. Each workspace has its own password.

## Set a password and lock the vault

Open the vault with the lock icon at the top right of Tasks, or through Settings → Data backup and workspaces → Private task vault.
Initial setup requires entering the same password twice, with a length of 8–1024 characters.
Create or import private tasks only after setup succeeds. This password is independent of the synchronization account password.

The vault is locked when the process starts. The following actions immediately clear private UI content and the unlocked state:

- Selecting the lock icon at the top right of the vault.
- Leaving the foreground, including opening the system file picker or another app.
- Switching workspaces.
- Leaving the vault page.

Locking closes private editors and category menus and discards unsaved input.
Ordinary tasks, search, project/tag filters, Today, the calendar, focus selectors, and statistics always use ordinary data.
They do not read private content or categories even when the vault is unlocked.
View private schedules and focus records within the vault.

On an incorrect password or ciphertext authentication failure, the vault remains locked and retains the original ciphertext.
Retry delay starts at 2 seconds, doubles with each failure, and is capped at 256 seconds. The failure count and next retry time are stored locally;
restarting the app does not immediately clear the wait. The UI does not distinguish an incorrect password from corrupt ciphertext.

## Private tasks, plans, and focus

Inside the vault, create, edit, complete, and delete tasks and set priority, notes, tags, deadline, estimated duration, and private categories.
Tasks sort by priority and then internal order within a priority.
Deleting a task also deletes its exclusive associated plans, focus records, reminders, and other records. A task currently in focus cannot be deleted or moved out.

“Schedule time” uses local time with input format `yyyy-MM-dd HH:mm`. The end must be after the start.
Select an existing plan to change its start and end. Private plans are encrypted and do not appear in the ordinary calendar.
They currently generate no system deadline or plan-start reminders.

The vault provides normal-mode focus, defaulting to 25 minutes and configurable from 1 to 1440 minutes.
Only one ordinary or private focus session can start at a time. Private focus does not use ordinary task policy selection or whitelists.
It currently offers no pause, guard mode, or strict mode option.

After relocking, an already started private session continues timing against its end time.
Android service, notification, lock-screen, and recovery data use only generic names such as “Private task”.
Viewing task content or ending early requires unlocking the original workspace's vault.
When timing completes while locked, only generic timing ends. The completion result is written to ciphertext on the next unlock.
If updating the system timer notification fails, the UI retains a message and offers “Retry notification”. Saved private records do not become ordinary records.

Local timing control markers are excluded from backups. Copying a workspace or restoring a backup does not grant control over the source device's focus.
A running session in restored content is marked interrupted on first unlock and does not automatically start the new device's timer service.

## Convert between ordinary and private tasks

Use an ordinary task's More → Move to private task vault, or “Move local task in” within the vault, to migrate an ordinary task.
Currently, only tasks in the original local workspace `__local__` that have never attempted synchronization are eligible:

- Server versions and cursors for the task and its exclusive associated records must be 0.
- Associated synchronization changes must never have been read into a sending batch by the synchronizer and must have no send attempts or rejections.
- The task and its exclusive plans must have no exposure record from system-calendar import, association, or attempted export. Disconnecting a calendar or deleting a plan does not remove this restriction.
- The task must not be in focus or share exclusive records requiring migration with other ordinary tasks.
- Synchronization workspaces, copied workspaces, and restored workspaces cannot directly move ordinary tasks into the vault.

Migration updates vault ciphertext, removes the ordinary task and exclusive associated records,
and deletes all pending, rejected, and superseded synchronization changes for those entities in one SQLite transaction.
If content or the queue changes before commit, or any write fails, the transaction rolls back and preserves the original ordinary data and vault ciphertext.
Shared metadata such as ordinary projects, tags, and focus policies is copied into ciphertext; the original shared records remain in the ordinary workspace.

Moving a task does not remove historical backups, filesystem snapshots, or external copies previously produced by the app.
For tasks uploaded or attempted for upload, server history and other devices may retain original content; direct conversion is therefore currently rejected.
The system calendar and its service provider may also retain events already exchanged. Moving content into the vault cannot recall those copies.
Calendar synchronization records local exposure markers before attempting an exchange. Markers remain when the write result is uncertain or an operation fails. Conversion checks them before migration and again in the commit transaction,
so concurrent synchronization and encryption cannot treat already shared content as never shared. See [system calendar synchronization](SYSTEM_CALENDAR.en.md) for connection rules.

Select “Move out of vault” under a private task and confirm ordinary storage to write the task and associated records back into the ordinary workspace.
Records moved out in a synchronized workspace may enter its synchronization queue. Ordinary writes and the private ciphertext update share one transaction.
An ID conflict or write failure preserves the original private records. After conversion, the client reloads ordinary lists and updates system task reminders.

## Encrypted backup and password changes

Private task vault → Encrypted backup exports a standalone `pactick-private-vault.json` file.
It includes the format version, password-derivation parameters, random salt, ciphertext, and authentication tag,
but no password, plaintext content, or decryption key. Maximum file size is 50 MiB.

To restore a standalone private backup, choose its file and enter the password used at export.
The client validates format, authentication tag, and content references before creating a new offline workspace.
The original workspace is preserved and the restored vault remains locked. Open the restored workspace through Settings → Data backup and workspaces → Open retained workspace, then unlock again.
Unsupported new formats, corrupt ciphertext, or incorrect passwords create no restored workspace.
A new device needs only the file and original password, without relying on the source device's system secure storage.

Full local backups use `pactick-workspace` v2 and carry the vault as the ciphertext field `private_vault`,
without decrypting it into ordinary documents. Older v1 ordinary backups remain restorable.
Workspace copying also copies vault ciphertext and preserves the original workspace.
Full workspace restoration validates only the private field's format; private authentication occurs at unlock.
Use standalone private-backup restoration to validate private content before creating a workspace.

Changing a password requires unlocking and verifying the old password. The client generates a new random salt,
reencrypts the entire vault with the new password, and atomically replaces ciphertext. On write failure, the old password and data remain usable.
Old backups still require their export-time password; changing the current password does not rewrite exported files.
There is currently no reset that reads content while bypassing the original password. Content cannot be recovered if the password is forgotten.

## Storage and content protection

The implementation uses the maintained Dart package [cryptography](https://pub.dev/packages/cryptography), with these parameters:

| Item | Current parameter |
| --- | --- |
| Password derivation | PBKDF2-HMAC-SHA256, 600000 iterations, 256-bit output |
| Random salt | New 32-byte random salt on setup or password change |
| Content encryption | AES-256-GCM |
| Random nonce | New 12-byte nonce on every save |
| Authentication tag | 16 bytes; authenticates format, algorithm parameters, and generic timer metadata as well |
| Plaintext capacity | Up to 35 MiB and 100000 entities per vault; encrypted backups up to 50 MiB |

SQLite schema v3 adds `private_vaults`, storing only workspace identifiers, ciphertext, and retry metadata.
Ordinary `documents` and `pending_operations` tables neither read nor store private content.
Salt, ciphertext size, failure counts, and generic timer random session IDs and start/end times are not hidden metadata.
Local focus-control markers bind the workspace, session, and SHA-256 of the entire ciphertext.
They do not migrate with backups or workspace copies. An unauthenticated header without a matching local marker cannot start timing.

Android sets `FLAG_SECURE` before entering private pages to block system screenshots and retention of the page in recent-app previews.
The page does not open if setting it fails. Other platforms provide no system screenshot protection.
Locking releases decrypted content and destroys key bytes held by the app. Historical strings in Dart-managed memory cannot be guaranteed physically zeroed.
This feature does not protect an already unlocked app process or erase operating-system backups, manually copied content, or old copies made before conversion.

## Maintenance and validation

Main implementation locations:

- `client/lib/core/state/private_vault_controller.dart`: sole unlocked-access entry, locking, conversion, and private focus.
- `client/lib/data/local/private_vault_crypto.dart`: versioned ciphertext envelope, standard password derivation, and authenticated encryption.
- `client/lib/data/local/private_vault_storage.dart` and `local_database.dart`: ciphertext storage and transactional conversion.
- `client/lib/features/tasks/pages/private_vault_page.dart`: private-content UI and cleanup of input and menus on lock.
- `client/test/private_vault_test.dart`: real SQLite, memory storage, encrypted backup, synchronization isolation, fault rollback, and UI locking tests.

Run `flutter test test/private_vault_test.dart` in `client`.
Tests cover storage isolation, database plaintext inspection, conversion in both directions, failed password changes, corrupt backups, restoration across storage implementations,
legacy format compatibility, local timer control, and asynchronous races while locked.
Desktop unit and widget tests do not establish background timing, screenshot restrictions, notifications, or vendor process-management behavior on Android hardware.
These require separate device acceptance.
