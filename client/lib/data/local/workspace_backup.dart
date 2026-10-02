import 'package:uuid/uuid.dart';

import 'local_database.dart';
import 'workspace_archive.dart';

export 'workspace_archive.dart';

class WorkspaceBackupService {
  WorkspaceBackupService(this.store, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final DocumentStore store;
  final Uuid _uuid;

  Future<String> exportJson(String accountId) async =>
      (await store.exportWorkspace(accountId)).encode();

  /// Always creates a separate offline workspace. Existing data remains intact.
  Future<String> restoreJson(String encoded) async {
    final archive = WorkspaceArchive.decode(encoded);
    final accountId = '__local__:${_uuid.v4()}';
    await store.restoreWorkspace(archive, accountId: accountId);
    return accountId;
  }

  Future<String> copyToLocal(String sourceAccountId) async {
    final accountId = '__local__:${_uuid.v4()}';
    await store.copyWorkspace(sourceAccountId, accountId);
    return accountId;
  }
}
