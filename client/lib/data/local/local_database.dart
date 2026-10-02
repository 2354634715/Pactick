import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/sync/sync_entity_contract.dart';
import '../../core/sync/sync_models.dart';
import 'workspace_archive.dart';

class StoredDocument {
  const StoredDocument({
    required this.entityType,
    required this.id,
    required this.body,
    required this.version,
    required this.updatedAt,
    this.deleted = false,
    this.cursor = 0,
  });

  final String entityType;
  final String id;
  final Map<String, Object?> body;
  final int version;
  final DateTime updatedAt;
  final bool deleted;
  final int cursor;
}

abstract interface class DocumentStore {
  static const localAccountId = '__local__';

  Future<List<StoredDocument>> readDocuments(
    String entityType, {
    String accountId = localAccountId,
  });

  Future<void> putDocument(
    String entityType,
    String id,
    Map<String, Object?> body, {
    bool enqueue = true,
    String accountId = localAccountId,
  });

  /// Commits all documents and their outbox entries in one transaction.
  Future<void> putDocuments(
    List<StoredDocument> documents, {
    bool enqueue = true,
    String accountId = localAccountId,
  });

  Future<void> deleteDocument(
    String entityType,
    String id, {
    bool enqueue = true,
    String accountId = localAccountId,
  });

  Future<int> pendingOperationCount({String accountId = localAccountId});

  Future<String?> readSetting(String key, {String accountId = localAccountId});

  Future<void> writeSetting(
    String key,
    String value, {
    String accountId = localAccountId,
  });

  Future<bool> ensureAccount(String accountId, {bool claimLocalData = false});

  Future<void> prepareUnsyncedDocuments(String accountId);

  Future<List<SyncOperation>> readPendingOperations(
    String accountId, {
    int limit = 200,
  });

  Future<void> applyPushResults(
    String accountId,
    List<SyncOperationResult> results,
  );

  Future<int> readSyncCursor(String accountId);

  Future<void> applyPullResponse(
    String accountId, {
    required int expectedCursor,
    required SyncPullResponse response,
  });

  Future<List<RejectedSyncOperation>> readRejectedOperations(String accountId);

  Future<WorkspaceArchive> exportWorkspace(String accountId);

  Future<void> restoreWorkspace(
    WorkspaceArchive archive, {
    required String accountId,
    bool enqueueForSync = false,
  });

  Future<void> copyWorkspace(
    String sourceAccountId,
    String targetAccountId, {
    bool enqueueForSync = false,
  });

  /// Only for the same server's verified legacy login. Retains the original
  /// account so an upgrade can be rolled back, and refuses to merge targets.
  Future<bool> migrateLegacyAccount(String legacyId, String namespacedId);

  Future<List<String>> listWorkspaceIds();
}

class LocalDatabase implements DocumentStore {
  LocalDatabase({Uuid? uuid, this.databasePath, this.factory})
    : _uuid = uuid ?? const Uuid();

  static const _databaseVersion = 2;

  final Uuid _uuid;
  final String? databasePath;
  final DatabaseFactory? factory;
  Database? _database;
  Future<Database>? _opening;

  Future<Database> get _db async {
    if (_database case final database?) return database;
    final opening = _opening ??= _openDatabase();
    try {
      return await opening;
    } catch (_) {
      // Concurrent callers share this attempt; a later retry starts a new one.
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }

  Future<Database> _openDatabase() async {
    final selectedFactory = factory ?? databaseFactory;
    final selectedPath =
        databasePath ??
        path.join(await selectedFactory.getDatabasesPath(), 'pactick.db');
    final database = await selectedFactory.openDatabase(
      selectedPath,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _createSchema(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _migrateV1(db);
        },
      ),
    );
    _database = database;
    return database;
  }

  Future<void> close() async {
    final database = _database ?? (await _opening);
    await database?.close();
    _database = null;
    _opening = null;
  }

  @override
  Future<List<String>> listWorkspaceIds() async {
    final db = await _db;
    final rows = await db.query('sync_state', columns: ['account_id']);
    return rows.map((row) => row['account_id']! as String).toList()..sort();
  }

  @override
  Future<WorkspaceArchive> exportWorkspace(String accountId) async {
    final db = await _db;
    return db.transaction((tx) async {
      final accounts = await tx.query(
        'sync_state',
        where: 'account_id = ?',
        whereArgs: [accountId],
        limit: 1,
      );
      if (accounts.isEmpty) throw StateError('Workspace does not exist.');
      final documents = await tx.query(
        'documents',
        where: 'account_id = ?',
        whereArgs: [accountId],
        orderBy: 'entity_type, entity_id',
      );
      final pending = await tx.query(
        'pending_operations',
        where: 'account_id = ? AND superseded_at IS NULL',
        whereArgs: [accountId],
        orderBy: 'rowid',
      );
      final settings = <String, String>{};
      // Global presentation preferences also travel in a portable backup.
      for (final id in {DocumentStore.localAccountId, accountId}) {
        final rows = await tx.query(
          'app_settings',
          where: 'account_id = ?',
          whereArgs: [id],
        );
        for (final row in rows) {
          final key = row['setting_key']! as String;
          if (WorkspaceArchive.portableSettings.contains(key) &&
              (id == accountId || _globalPortableSettings.contains(key))) {
            settings[key] = row['setting_value']! as String;
          }
        }
      }
      return _makeArchive(
        documents.map(_documentFromRow),
        settings,
        pending.map(_operationFromRow),
      );
    });
  }

  @override
  Future<void> restoreWorkspace(
    WorkspaceArchive archive, {
    required String accountId,
    bool enqueueForSync = false,
  }) async {
    _validateNewWorkspaceId(accountId);
    final validated = WorkspaceArchive.decode(archive.encode());
    final operations = enqueueForSync
        ? _freshWorkspaceOperations(validated, _uuid)
        : const <SyncOperation>[];
    final db = await _db;
    await db.transaction((tx) async {
      final existing = await tx.query(
        'sync_state',
        where: 'account_id = ?',
        whereArgs: [accountId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw StateError('Target workspace already exists.');
      }
      await _ensureAccountRow(tx, accountId);
      for (final document in validated.documents) {
        await tx.insert('documents', {
          'account_id': accountId,
          'entity_type': document.entityType,
          'entity_id': document.id,
          'body': jsonEncode(document.body),
          'version': 0,
          'updated_at': document.updatedAt.toUtc().toIso8601String(),
          'deleted': document.deleted ? 1 : 0,
          'last_cursor': 0,
        });
      }
      for (final operation in operations) {
        await tx.insert('pending_operations', {
          'account_id': accountId,
          'operation_id': operation.operationId,
          'entity_type': operation.entityType.wireName,
          'entity_id': operation.entityId,
          'action': operation.action.wireName,
          'base_version': operation.baseVersion,
          'changed_fields': jsonEncode(operation.changedFields),
          'patch': operation.patch == null ? null : jsonEncode(operation.patch),
          'created_at': operation.clientChangedAt.toUtc().toIso8601String(),
        });
      }
      for (final entry in validated.settings.entries) {
        await tx.insert('app_settings', {
          'account_id': accountId,
          'setting_key': entry.key,
          'setting_value': entry.value,
        });
      }
    });
  }

  @override
  Future<void> copyWorkspace(
    String sourceAccountId,
    String targetAccountId, {
    bool enqueueForSync = false,
  }) async {
    final archive = await exportWorkspace(sourceAccountId);
    await restoreWorkspace(
      archive,
      accountId: targetAccountId,
      enqueueForSync: enqueueForSync,
    );
  }

  @override
  Future<bool> migrateLegacyAccount(
    String legacyId,
    String namespacedId,
  ) async {
    _validateLegacyMigration(legacyId, namespacedId);
    final db = await _db;
    return db.transaction((tx) async {
      final target = await tx.query(
        'sync_state',
        where: 'account_id = ?',
        whereArgs: [namespacedId],
        limit: 1,
      );
      if (target.isNotEmpty) return false;
      final source = await tx.query(
        'sync_state',
        where: 'account_id = ?',
        whereArgs: [legacyId],
        limit: 1,
      );
      if (source.isEmpty) return false;
      for (final table in [
        'sync_state',
        'documents',
        'pending_operations',
        'app_settings',
      ]) {
        final rows = await tx.query(
          table,
          where: 'account_id = ?',
          whereArgs: [legacyId],
          orderBy: 'rowid',
        );
        for (final row in rows) {
          await tx.insert(table, {...row, 'account_id': namespacedId});
        }
      }
      return true;
    });
  }

  Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE documents (
        account_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        body TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        last_cursor INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (account_id, entity_type, entity_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE pending_operations (
        account_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        action TEXT NOT NULL,
        base_version INTEGER NOT NULL,
        changed_fields TEXT NOT NULL,
        patch TEXT,
        created_at TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        last_attempt_at TEXT,
        rejected_at TEXT,
        superseded_at TEXT,
        error_code TEXT,
        error_message TEXT,
        error_details TEXT,
        PRIMARY KEY (account_id, operation_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE app_settings (
        account_id TEXT NOT NULL,
        setting_key TEXT NOT NULL,
        setting_value TEXT NOT NULL,
        PRIMARY KEY (account_id, setting_key)
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_state (
        account_id TEXT PRIMARY KEY,
        cursor INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX pending_operations_account_created_idx '
      'ON pending_operations(account_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX pending_operations_entity_idx '
      'ON pending_operations(account_id, entity_type, entity_id)',
    );
    await db.insert('sync_state', {
      'account_id': DocumentStore.localAccountId,
      'cursor': 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _migrateV1(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE documents RENAME TO documents_v1');
    await db.execute(
      'ALTER TABLE pending_operations RENAME TO pending_operations_v1',
    );
    await db.execute('ALTER TABLE app_settings RENAME TO app_settings_v1');
    await _createSchema(db);
    await db.execute(
      '''
      INSERT INTO documents (
        account_id, entity_type, entity_id, body, version, updated_at,
        deleted, last_cursor
      )
      SELECT ?, entity_type, entity_id, body, version, updated_at, deleted, 0
      FROM documents_v1
    ''',
      [DocumentStore.localAccountId],
    );
    await db.execute(
      '''
      INSERT INTO app_settings (account_id, setting_key, setting_value)
      SELECT ?, setting_key, setting_value FROM app_settings_v1
    ''',
      [DocumentStore.localAccountId],
    );

    // The v1 client could not sync and generated non-UUID operation IDs.
    // Rebuild one latest valid envelope per queued document without data loss.
    final queuedEntities = await db.rawQuery('''
      SELECT entity_type, entity_id, MIN(created_at) AS created_at
      FROM pending_operations_v1
      GROUP BY entity_type, entity_id
      ORDER BY MIN(created_at)
    ''');
    for (final queued in queuedEntities) {
      final entityTypeName = queued['entity_type'] as String;
      final entityId = queued['entity_id'] as String;
      final documents = await db.query(
        'documents_v1',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [entityTypeName, entityId],
        limit: 1,
      );
      if (documents.isEmpty) continue;
      final document = documents.first;
      final version = document['version']! as int;
      final deleted = document['deleted']! as int != 0;
      if (deleted && version == 0) continue;
      final type = SyncEntityType.fromWire(entityTypeName);
      final body = _decodeMap(document['body']! as String);
      final patch = SyncEntityContract.cloudPatch(type, body);
      if (!deleted && patch.isEmpty) continue;
      await db.insert('pending_operations', {
        'account_id': DocumentStore.localAccountId,
        'operation_id': _uuid.v4(),
        'entity_type': entityTypeName,
        'entity_id': entityId,
        'action': deleted
            ? SyncAction.delete.wireName
            : SyncAction.upsert.wireName,
        'base_version': version,
        'changed_fields': jsonEncode(
          deleted ? const <String>[] : (patch.keys.toList()..sort()),
        ),
        'patch': deleted ? null : jsonEncode(patch),
        'created_at': queued['created_at'] as String,
      });
    }
    await db.execute('DROP TABLE documents_v1');
    await db.execute('DROP TABLE pending_operations_v1');
    await db.execute('DROP TABLE app_settings_v1');
  }

  @override
  Future<List<StoredDocument>> readDocuments(
    String entityType, {
    String accountId = DocumentStore.localAccountId,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'documents',
      where: 'account_id = ? AND entity_type = ? AND deleted = 0',
      whereArgs: [accountId, entityType],
      orderBy: 'updated_at ASC',
    );
    return rows.map(_documentFromRow).toList(growable: false);
  }

  @override
  Future<void> putDocument(
    String entityType,
    String id,
    Map<String, Object?> body, {
    bool enqueue = true,
    String accountId = DocumentStore.localAccountId,
  }) async {
    final db = await _db;
    await db.transaction(
      (tx) => _putDocument(
        tx,
        entityType,
        id,
        body,
        enqueue: enqueue,
        accountId: accountId,
      ),
    );
  }

  @override
  Future<void> putDocuments(
    List<StoredDocument> documents, {
    bool enqueue = true,
    String accountId = DocumentStore.localAccountId,
  }) async {
    final db = await _db;
    await db.transaction((tx) async {
      for (final document in documents) {
        await _putDocument(
          tx,
          document.entityType,
          document.id,
          document.body,
          enqueue: enqueue,
          accountId: accountId,
        );
      }
    });
  }

  Future<void> _putDocument(
    DatabaseExecutor transaction,
    String entityType,
    String id,
    Map<String, Object?> body, {
    required bool enqueue,
    required String accountId,
  }) async {
    final type = SyncEntityType.fromWire(entityType);
    final now = DateTime.now().toUtc().toIso8601String();
    await _ensureAccountRow(transaction, accountId);
    final existing = await transaction.query(
      'documents',
      where: 'account_id = ? AND entity_type = ? AND entity_id = ?',
      whereArgs: [accountId, entityType, id],
      limit: 1,
    );
    final previousBody = existing.isEmpty
        ? null
        : _decodeMap(existing.first['body']! as String);
    final normalizedBody = SyncEntityContract.normalizeLocalBody(
      type,
      body,
      previousBody,
    );
    final version = existing.isEmpty ? 0 : existing.first['version']! as int;
    final cursor = existing.isEmpty ? 0 : existing.first['last_cursor']! as int;
    await transaction.insert('documents', {
      'account_id': accountId,
      'entity_type': entityType,
      'entity_id': id,
      'body': jsonEncode(normalizedBody),
      'version': version,
      'updated_at': now,
      'deleted': 0,
      'last_cursor': cursor,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (!enqueue) return;

    final cloudBody = SyncEntityContract.cloudPatch(type, normalizedBody);
    final previousCloudBody = previousBody == null
        ? const <String, Object?>{}
        : SyncEntityContract.cloudPatch(type, previousBody);
    final changed = _changedValues(previousCloudBody, cloudBody);
    if (previousBody != null && changed.isEmpty) return;
    final patch = version == 0 ? cloudBody : changed;
    if (patch.isEmpty) return;
    await _supersedeRejections(
      transaction,
      accountId: accountId,
      entityType: entityType,
      entityId: id,
      supersededAt: now,
    );
    await _enqueueUpsert(
      transaction,
      accountId: accountId,
      type: type,
      entityId: id,
      baseVersion: version,
      patch: patch,
      fullBody: cloudBody,
      createdAt: now,
    );
  }

  Future<void> _enqueueUpsert(
    DatabaseExecutor db, {
    required String accountId,
    required SyncEntityType type,
    required String entityId,
    required int baseVersion,
    required Map<String, Object?> patch,
    required Map<String, Object?> fullBody,
    required String createdAt,
  }) async {
    final editable = await db.query(
      'pending_operations',
      where: '''account_id = ? AND entity_type = ? AND entity_id = ?
        AND attempt_count = 0 AND rejected_at IS NULL''',
      whereArgs: [accountId, type.wireName, entityId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (editable.isNotEmpty) {
      final row = editable.first;
      final existingPatch = row['patch'] == null
          ? <String, Object?>{}
          : _decodeMap(row['patch']! as String);
      final combined =
          row['action'] == SyncAction.delete.wireName || baseVersion == 0
          ? Map<String, Object?>.from(fullBody)
          : <String, Object?>{...existingPatch, ...patch};
      await db.update(
        'pending_operations',
        {
          'action': SyncAction.upsert.wireName,
          'base_version': baseVersion,
          'changed_fields': jsonEncode(combined.keys.toList()..sort()),
          'patch': jsonEncode(combined),
        },
        where: 'account_id = ? AND operation_id = ?',
        whereArgs: [accountId, row['operation_id']],
      );
      return;
    }
    await db.insert('pending_operations', {
      'account_id': accountId,
      'operation_id': _uuid.v4(),
      'entity_type': type.wireName,
      'entity_id': entityId,
      'action': SyncAction.upsert.wireName,
      'base_version': baseVersion,
      'changed_fields': jsonEncode(patch.keys.toList()..sort()),
      'patch': jsonEncode(patch),
      'created_at': createdAt,
    });
  }

  Future<void> _supersedeRejections(
    DatabaseExecutor db, {
    required String accountId,
    required String entityType,
    required String entityId,
    required String supersededAt,
  }) {
    return db.update(
      'pending_operations',
      {'superseded_at': supersededAt},
      where: '''account_id = ? AND entity_type = ? AND entity_id = ?
        AND rejected_at IS NOT NULL AND superseded_at IS NULL''',
      whereArgs: [accountId, entityType, entityId],
    );
  }

  @override
  Future<void> deleteDocument(
    String entityType,
    String id, {
    bool enqueue = true,
    String accountId = DocumentStore.localAccountId,
  }) async {
    SyncEntityType.fromWire(entityType);
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((transaction) async {
      final existing = await transaction.query(
        'documents',
        where: 'account_id = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: [accountId, entityType, id],
        limit: 1,
      );
      if (existing.isEmpty) return;
      final version = existing.first['version']! as int;
      await transaction.update(
        'documents',
        {'deleted': 1, 'updated_at': now},
        where: 'account_id = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: [accountId, entityType, id],
      );
      if (!enqueue) {
        await transaction.delete(
          'pending_operations',
          where: 'account_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [accountId, entityType, id],
        );
        return;
      }

      await _supersedeRejections(
        transaction,
        accountId: accountId,
        entityType: entityType,
        entityId: id,
        supersededAt: now,
      );

      final attemptedCount =
          Sqflite.firstIntValue(
            await transaction.rawQuery(
              '''
              SELECT COUNT(*) FROM pending_operations
              WHERE account_id = ? AND entity_type = ? AND entity_id = ?
                AND attempt_count > 0
            ''',
              [accountId, entityType, id],
            ),
          ) ??
          0;
      if (version == 0 && attemptedCount == 0) {
        await transaction.delete(
          'pending_operations',
          where: 'account_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [accountId, entityType, id],
        );
        return;
      }
      final editable = await transaction.query(
        'pending_operations',
        where: '''account_id = ? AND entity_type = ? AND entity_id = ?
          AND attempt_count = 0 AND rejected_at IS NULL''',
        whereArgs: [accountId, entityType, id],
        orderBy: 'created_at DESC',
        limit: 1,
      );
      final values = <String, Object?>{
        'action': SyncAction.delete.wireName,
        'base_version': version,
        'changed_fields': '[]',
        'patch': null,
      };
      if (editable.isNotEmpty) {
        await transaction.update(
          'pending_operations',
          values,
          where: 'account_id = ? AND operation_id = ?',
          whereArgs: [accountId, editable.first['operation_id']],
        );
      } else {
        await transaction.insert('pending_operations', {
          'account_id': accountId,
          'operation_id': _uuid.v4(),
          'entity_type': entityType,
          'entity_id': id,
          ...values,
          'created_at': now,
        });
      }
    });
  }

  @override
  Future<int> pendingOperationCount({
    String accountId = DocumentStore.localAccountId,
  }) async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            '''SELECT COUNT(*) FROM pending_operations
              WHERE account_id = ? AND superseded_at IS NULL''',
            [accountId],
          ),
        ) ??
        0;
  }

  @override
  Future<String?> readSetting(
    String key, {
    String accountId = DocumentStore.localAccountId,
  }) async {
    final db = await _db;
    final result = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'account_id = ? AND setting_key = ?',
      whereArgs: [accountId, key],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return result.first['setting_value'] as String;
  }

  @override
  Future<void> writeSetting(
    String key,
    String value, {
    String accountId = DocumentStore.localAccountId,
  }) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await _ensureAccountRow(transaction, accountId);
      await transaction.insert('app_settings', {
        'account_id': accountId,
        'setting_key': key,
        'setting_value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<bool> ensureAccount(
    String accountId, {
    bool claimLocalData = false,
  }) async {
    final db = await _db;
    return db.transaction((transaction) async {
      final existing = await transaction.query(
        'sync_state',
        columns: ['account_id'],
        where: 'account_id = ?',
        whereArgs: [accountId],
        limit: 1,
      );
      if (existing.isNotEmpty) return false;
      await transaction.insert('sync_state', {
        'account_id': accountId,
        'cursor': 0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (!claimLocalData || accountId == DocumentStore.localAccountId) {
        return false;
      }
      for (final table in ['documents', 'pending_operations']) {
        await transaction.update(
          table,
          {'account_id': accountId},
          where: 'account_id = ?',
          whereArgs: [DocumentStore.localAccountId],
        );
      }
      await transaction.update(
        'app_settings',
        {'account_id': accountId},
        where: 'account_id = ? AND setting_key IN (?, ?)',
        whereArgs: [
          DocumentStore.localAccountId,
          'focus_app_whitelists_v1',
          'legacy_sample_content_removed_v1',
        ],
      );
      return true;
    });
  }

  Future<void> _ensureAccountRow(DatabaseExecutor db, String accountId) async {
    await db.insert('sync_state', {
      'account_id': accountId,
      'cursor': 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<void> prepareUnsyncedDocuments(String accountId) async {
    final db = await _db;
    await db.transaction((transaction) async {
      final rows = await transaction.rawQuery(
        '''
        SELECT d.* FROM documents d
        WHERE d.account_id = ? AND d.version = 0 AND d.deleted = 0
          AND NOT EXISTS (
            SELECT 1 FROM pending_operations p
            WHERE p.account_id = d.account_id
              AND p.entity_type = d.entity_type
              AND p.entity_id = d.entity_id
              AND p.superseded_at IS NULL
          )
      ''',
        [accountId],
      );
      for (final row in rows) {
        final type = SyncEntityType.fromWire(row['entity_type']);
        final body = _decodeMap(row['body']! as String);
        final patch = SyncEntityContract.cloudPatch(type, body);
        if (patch.isEmpty) continue;
        await _enqueueUpsert(
          transaction,
          accountId: accountId,
          type: type,
          entityId: row['entity_id']! as String,
          baseVersion: 0,
          patch: patch,
          fullBody: patch,
          createdAt: row['updated_at']! as String,
        );
      }
    });
  }

  @override
  Future<List<SyncOperation>> readPendingOperations(
    String accountId, {
    int limit = 200,
  }) async {
    if (limit < 1 || limit > 200) {
      throw RangeError.range(limit, 1, 200, 'limit');
    }
    final db = await _db;
    return db.transaction((transaction) async {
      final rows = await transaction.rawQuery(
        '''SELECT rowid AS queue_order, * FROM pending_operations
          WHERE account_id = ? AND rejected_at IS NULL
            AND superseded_at IS NULL''',
        [accountId],
      );
      final queued =
          rows
              .map(
                (row) => _QueuedSyncOperation(
                  _operationFromRow(row),
                  row['queue_order']! as int,
                ),
              )
              .toList()
            ..sort(_compareQueuedOperations);
      final selected = queued
          .take(limit)
          .map((value) => value.operation)
          .toList(growable: false);
      if (selected.isNotEmpty) {
        final now = DateTime.now().toUtc().toIso8601String();
        for (final operation in selected) {
          await transaction.rawUpdate(
            '''
            UPDATE pending_operations
            SET attempt_count = attempt_count + 1, last_attempt_at = ?
            WHERE account_id = ? AND operation_id = ?
          ''',
            [now, accountId, operation.operationId],
          );
        }
      }
      return selected;
    });
  }

  @override
  Future<void> applyPushResults(
    String accountId,
    List<SyncOperationResult> results,
  ) async {
    final db = await _db;
    await db.transaction((transaction) async {
      for (final result in results) {
        final rows = await transaction.query(
          'pending_operations',
          where: 'account_id = ? AND operation_id = ?',
          whereArgs: [accountId, result.operationId],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        if (result.status == SyncOperationStatus.rejected) {
          final error = result.error!;
          final newerCount =
              Sqflite.firstIntValue(
                await transaction.rawQuery(
                  '''SELECT COUNT(*) FROM pending_operations
                    WHERE account_id = ? AND entity_type = ? AND entity_id = ?
                      AND rowid > (
                        SELECT rowid FROM pending_operations
                        WHERE account_id = ? AND operation_id = ?
                      )
                      AND superseded_at IS NULL''',
                  [
                    accountId,
                    rows.first['entity_type'],
                    rows.first['entity_id'],
                    accountId,
                    result.operationId,
                  ],
                ),
              ) ??
              0;
          final rejectedAt = DateTime.now().toUtc().toIso8601String();
          await transaction.update(
            'pending_operations',
            {
              'rejected_at': rejectedAt,
              if (newerCount > 0) 'superseded_at': rejectedAt,
              'error_code': error.code,
              'error_message': error.message,
              'error_details': jsonEncode(error.details),
            },
            where: 'account_id = ? AND operation_id = ?',
            whereArgs: [accountId, result.operationId],
          );
          continue;
        }
        await transaction.delete(
          'pending_operations',
          where: 'account_id = ? AND operation_id = ?',
          whereArgs: [accountId, result.operationId],
        );
        await _applySnapshot(transaction, accountId, result.snapshot!);
      }
    });
  }

  @override
  Future<int> readSyncCursor(String accountId) async {
    final db = await _db;
    final rows = await db.query(
      'sync_state',
      columns: ['cursor'],
      where: 'account_id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : rows.first['cursor']! as int;
  }

  @override
  Future<void> applyPullResponse(
    String accountId, {
    required int expectedCursor,
    required SyncPullResponse response,
  }) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await _ensureAccountRow(transaction, accountId);
      final currentRows = await transaction.query(
        'sync_state',
        columns: ['cursor'],
        where: 'account_id = ?',
        whereArgs: [accountId],
        limit: 1,
      );
      final current = currentRows.first['cursor']! as int;
      if (current != expectedCursor) {
        throw StateError(
          'Sync cursor changed from $expectedCursor to $current.',
        );
      }
      var previous = expectedCursor;
      for (final change in response.changes) {
        if (change.cursor <= previous || change.cursor > response.nextCursor) {
          throw const FormatException('Pull changes have invalid cursors.');
        }
        await _applySnapshot(transaction, accountId, change.toSnapshot());
        previous = change.cursor;
      }
      if ((response.changes.isNotEmpty && response.nextCursor != previous) ||
          (response.hasMore && response.changes.isEmpty) ||
          response.nextCursor < previous ||
          response.currentCursor < response.nextCursor ||
          (response.hasMore && response.nextCursor <= expectedCursor)) {
        throw const FormatException('Pull response has invalid cursor bounds.');
      }
      await transaction.update(
        'sync_state',
        {'cursor': response.nextCursor},
        where: 'account_id = ?',
        whereArgs: [accountId],
      );
    });
  }

  Future<void> _applySnapshot(
    DatabaseExecutor db,
    String accountId,
    SyncSnapshot snapshot,
  ) async {
    final rows = await db.query(
      'documents',
      where: 'account_id = ? AND entity_type = ? AND entity_id = ?',
      whereArgs: [accountId, snapshot.entityType.wireName, snapshot.entityId],
      limit: 1,
    );
    final existing = rows.isEmpty ? null : rows.first;
    final existingVersion = existing?['version'] as int? ?? 0;
    if (snapshot.version < existingVersion) {
      if (existing != null &&
          snapshot.cursor > (existing['last_cursor']! as int)) {
        await db.update(
          'documents',
          {'last_cursor': snapshot.cursor},
          where: 'account_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [
            accountId,
            snapshot.entityType.wireName,
            snapshot.entityId,
          ],
        );
      }
      return;
    }
    final existingBody = existing == null
        ? null
        : _decodeMap(existing['body']! as String);
    var body = SyncEntityContract.mergeRemoteBody(
      snapshot.entityType,
      snapshot.body,
      existingBody,
    );
    var deleted = snapshot.deleted;
    final pending = await db.query(
      'pending_operations',
      where: '''account_id = ? AND entity_type = ? AND entity_id = ?
        AND superseded_at IS NULL''',
      whereArgs: [accountId, snapshot.entityType.wireName, snapshot.entityId],
      orderBy: 'rowid ASC',
    );
    for (final operation in pending) {
      if (operation['action'] == SyncAction.delete.wireName) {
        deleted = true;
      } else {
        body = {...body, ..._decodeMap(operation['patch']! as String)};
        deleted = false;
      }
      if ((operation['attempt_count']! as int) == 0 &&
          operation['rejected_at'] == null &&
          (operation['base_version']! as int) < snapshot.version) {
        await db.update(
          'pending_operations',
          {'base_version': snapshot.version},
          where: 'account_id = ? AND operation_id = ?',
          whereArgs: [accountId, operation['operation_id']],
        );
      }
    }
    final localCursor = existing?['last_cursor'] as int? ?? 0;
    await db.insert('documents', {
      'account_id': accountId,
      'entity_type': snapshot.entityType.wireName,
      'entity_id': snapshot.entityId,
      'body': jsonEncode(body),
      'version': snapshot.version,
      'updated_at': snapshot.updatedAt.toUtc().toIso8601String(),
      'deleted': deleted ? 1 : 0,
      'last_cursor': snapshot.cursor > localCursor
          ? snapshot.cursor
          : localCursor,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<RejectedSyncOperation>> readRejectedOperations(
    String accountId,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'pending_operations',
      where: '''account_id = ? AND rejected_at IS NOT NULL
        AND superseded_at IS NULL''',
      whereArgs: [accountId],
      orderBy: 'rejected_at DESC',
    );
    return rows
        .map((row) {
          return RejectedSyncOperation(
            operation: _operationFromRow(row),
            error: SyncError(
              code: row['error_code']! as String,
              message: row['error_message']! as String,
              details: row['error_details'] == null
                  ? const {}
                  : _decodeMap(row['error_details']! as String),
            ),
            rejectedAt: DateTime.parse(row['rejected_at']! as String).toUtc(),
          );
        })
        .toList(growable: false);
  }

  StoredDocument _documentFromRow(Map<String, Object?> row) {
    return StoredDocument(
      entityType: row['entity_type']! as String,
      id: row['entity_id']! as String,
      body: _decodeMap(row['body']! as String),
      version: row['version']! as int,
      updatedAt: DateTime.parse(row['updated_at']! as String),
      deleted: row['deleted']! as int != 0,
      cursor: row['last_cursor']! as int,
    );
  }

  SyncOperation _operationFromRow(Map<String, Object?> row) {
    final patchValue = row['patch'];
    return SyncOperation(
      operationId: row['operation_id']! as String,
      entityType: SyncEntityType.fromWire(row['entity_type']),
      entityId: row['entity_id']! as String,
      action: SyncAction.fromWire(row['action']),
      baseVersion: row['base_version']! as int,
      changedFields: (jsonDecode(row['changed_fields']! as String) as List)
          .cast<String>(),
      patch: patchValue == null ? null : _decodeMap(patchValue as String),
      clientChangedAt: DateTime.parse(row['created_at']! as String).toUtc(),
    );
  }
}

class MemoryDocumentStore implements DocumentStore {
  MemoryDocumentStore({Uuid? uuid}) : _uuid = uuid ?? const Uuid() {
    _accounts[DocumentStore.localAccountId] = _MemoryAccount();
  }

  final Uuid _uuid;
  final Map<String, _MemoryAccount> _accounts = {};

  _MemoryAccount _account(String accountId) =>
      _accounts.putIfAbsent(accountId, _MemoryAccount.new);

  String _documentKey(String entityType, String id) => '$entityType\u0000$id';

  @override
  Future<List<String>> listWorkspaceIds() async =>
      _accounts.keys.toList()..sort();

  @override
  Future<WorkspaceArchive> exportWorkspace(String accountId) async {
    final account = _accounts[accountId];
    if (account == null) throw StateError('Workspace does not exist.');
    final settings = <String, String>{};
    for (final id in {DocumentStore.localAccountId, accountId}) {
      for (final entry in _accounts[id]!.settings.entries) {
        if (WorkspaceArchive.portableSettings.contains(entry.key) &&
            (id == accountId || _globalPortableSettings.contains(entry.key))) {
          settings[entry.key] = entry.value;
        }
      }
    }
    return _makeArchive(
      account.documents.values,
      settings,
      account.pending
          .where((value) => value.supersededAt == null)
          .map((value) => value.operation),
    );
  }

  @override
  Future<void> restoreWorkspace(
    WorkspaceArchive archive, {
    required String accountId,
    bool enqueueForSync = false,
  }) async {
    _validateNewWorkspaceId(accountId);
    final validated = WorkspaceArchive.decode(archive.encode());
    if (_accounts.containsKey(accountId)) {
      throw StateError('Target workspace already exists.');
    }
    // Build separately; publish only after every document has succeeded.
    final account = _MemoryAccount()..settings.addAll(validated.settings);
    for (final document in validated.documents) {
      account.documents[document.key] = StoredDocument(
        entityType: document.entityType,
        id: document.id,
        body: document.body,
        version: 0,
        updatedAt: document.updatedAt,
        deleted: document.deleted,
      );
    }
    if (enqueueForSync) {
      account.pending.addAll(
        _freshWorkspaceOperations(validated, _uuid).map(_MemoryPending.new),
      );
    }
    _accounts[accountId] = account;
  }

  @override
  Future<void> copyWorkspace(
    String sourceAccountId,
    String targetAccountId, {
    bool enqueueForSync = false,
  }) async {
    final archive = await exportWorkspace(sourceAccountId);
    await restoreWorkspace(
      archive,
      accountId: targetAccountId,
      enqueueForSync: enqueueForSync,
    );
  }

  @override
  Future<bool> migrateLegacyAccount(
    String legacyId,
    String namespacedId,
  ) async {
    _validateLegacyMigration(legacyId, namespacedId);
    if (_accounts.containsKey(namespacedId)) return false;
    final source = _accounts[legacyId];
    if (source == null) return false;
    final target = _MemoryAccount()
      ..cursor = source.cursor
      ..settings.addAll(source.settings);
    for (final entry in source.documents.entries) {
      final doc = entry.value;
      target.documents[entry.key] = StoredDocument(
        entityType: doc.entityType,
        id: doc.id,
        body: _decodeMap(jsonEncode(doc.body)),
        version: doc.version,
        updatedAt: doc.updatedAt,
        deleted: doc.deleted,
        cursor: doc.cursor,
      );
    }
    for (final pending in source.pending) {
      final operation = pending.operation;
      target.pending.add(
        _MemoryPending(
            SyncOperation(
              operationId: operation.operationId,
              entityType: operation.entityType,
              entityId: operation.entityId,
              action: operation.action,
              baseVersion: operation.baseVersion,
              changedFields: List.of(operation.changedFields),
              clientChangedAt: operation.clientChangedAt,
              patch: operation.patch == null
                  ? null
                  : _decodeMap(jsonEncode(operation.patch)),
            ),
          )
          ..attemptCount = pending.attemptCount
          ..lastAttemptAt = pending.lastAttemptAt
          ..rejectedAt = pending.rejectedAt
          ..supersededAt = pending.supersededAt
          ..error = pending.error,
      );
    }
    _accounts[namespacedId] = target;
    return true;
  }

  @override
  Future<List<StoredDocument>> readDocuments(
    String entityType, {
    String accountId = DocumentStore.localAccountId,
  }) async {
    return _account(accountId).documents.values
        .where(
          (document) => document.entityType == entityType && !document.deleted,
        )
        .toList(growable: false);
  }

  @override
  Future<void> putDocuments(
    List<StoredDocument> documents, {
    bool enqueue = true,
    String accountId = DocumentStore.localAccountId,
  }) async {
    final account = _account(accountId);
    final originalDocuments = Map<String, StoredDocument>.from(
      account.documents,
    );
    final originalPending = [
      for (final pending in account.pending)
        _MemoryPending(pending.operation)
          ..attemptCount = pending.attemptCount
          ..lastAttemptAt = pending.lastAttemptAt
          ..rejectedAt = pending.rejectedAt
          ..supersededAt = pending.supersededAt
          ..error = pending.error,
    ];
    try {
      for (final document in documents) {
        await putDocument(
          document.entityType,
          document.id,
          document.body,
          enqueue: enqueue,
          accountId: accountId,
        );
      }
    } catch (_) {
      account.documents
        ..clear()
        ..addAll(originalDocuments);
      account.pending
        ..clear()
        ..addAll(originalPending);
      rethrow;
    }
  }

  @override
  Future<void> putDocument(
    String entityType,
    String id,
    Map<String, Object?> body, {
    bool enqueue = true,
    String accountId = DocumentStore.localAccountId,
  }) async {
    final type = SyncEntityType.fromWire(entityType);
    final account = _account(accountId);
    final key = _documentKey(entityType, id);
    final previous = account.documents[key];
    final normalized = SyncEntityContract.normalizeLocalBody(
      type,
      body,
      previous?.body,
    );
    final now = DateTime.now().toUtc();
    account.documents[key] = StoredDocument(
      entityType: entityType,
      id: id,
      body: Map.unmodifiable(normalized),
      version: previous?.version ?? 0,
      updatedAt: now,
      cursor: previous?.cursor ?? 0,
    );
    if (!enqueue) return;
    final cloudBody = SyncEntityContract.cloudPatch(type, normalized);
    final previousCloud = previous == null
        ? const <String, Object?>{}
        : SyncEntityContract.cloudPatch(type, previous.body);
    final changed = _changedValues(previousCloud, cloudBody);
    if (previous != null && changed.isEmpty) return;
    final patch = (previous?.version ?? 0) == 0 ? cloudBody : changed;
    if (patch.isEmpty) return;
    for (final value in account.pending) {
      if (value.operation.entityType == type &&
          value.operation.entityId == id &&
          value.rejectedAt != null &&
          value.supersededAt == null) {
        value.supersededAt = now;
      }
    }
    _memoryEnqueueUpsert(
      account,
      type: type,
      entityId: id,
      baseVersion: previous?.version ?? 0,
      patch: patch,
      fullBody: cloudBody,
      createdAt: now,
    );
  }

  void _memoryEnqueueUpsert(
    _MemoryAccount account, {
    required SyncEntityType type,
    required String entityId,
    required int baseVersion,
    required Map<String, Object?> patch,
    required Map<String, Object?> fullBody,
    required DateTime createdAt,
  }) {
    final editable = account.pending.lastWhereOrNull(
      (value) =>
          value.operation.entityType == type &&
          value.operation.entityId == entityId &&
          value.attemptCount == 0 &&
          value.rejectedAt == null,
    );
    if (editable != null) {
      final combined =
          editable.operation.action == SyncAction.delete || baseVersion == 0
          ? Map<String, Object?>.from(fullBody)
          : <String, Object?>{...?editable.operation.patch, ...patch};
      editable.operation = SyncOperation(
        operationId: editable.operation.operationId,
        entityType: type,
        entityId: entityId,
        action: SyncAction.upsert,
        baseVersion: baseVersion,
        changedFields: combined.keys.toList()..sort(),
        patch: combined,
        clientChangedAt: editable.operation.clientChangedAt,
      );
      return;
    }
    account.pending.add(
      _MemoryPending(
        SyncOperation(
          operationId: _uuid.v4(),
          entityType: type,
          entityId: entityId,
          action: SyncAction.upsert,
          baseVersion: baseVersion,
          changedFields: patch.keys.toList()..sort(),
          patch: Map.unmodifiable(patch),
          clientChangedAt: createdAt,
        ),
      ),
    );
  }

  @override
  Future<void> deleteDocument(
    String entityType,
    String id, {
    bool enqueue = true,
    String accountId = DocumentStore.localAccountId,
  }) async {
    final type = SyncEntityType.fromWire(entityType);
    final account = _account(accountId);
    final key = _documentKey(entityType, id);
    final previous = account.documents[key];
    if (previous == null) return;
    final now = DateTime.now().toUtc();
    account.documents[key] = StoredDocument(
      entityType: entityType,
      id: id,
      body: previous.body,
      version: previous.version,
      updatedAt: now,
      deleted: true,
      cursor: previous.cursor,
    );
    if (!enqueue) {
      account.pending.removeWhere(
        (value) =>
            value.operation.entityType == type &&
            value.operation.entityId == id,
      );
      return;
    }
    for (final value in account.pending) {
      if (value.operation.entityType == type &&
          value.operation.entityId == id &&
          value.rejectedAt != null &&
          value.supersededAt == null) {
        value.supersededAt = now;
      }
    }
    final hasAttempted = account.pending.any(
      (value) =>
          value.operation.entityType == type &&
          value.operation.entityId == id &&
          value.attemptCount > 0,
    );
    if (previous.version == 0 && !hasAttempted) {
      account.pending.removeWhere(
        (value) =>
            value.operation.entityType == type &&
            value.operation.entityId == id,
      );
      return;
    }
    final editable = account.pending.lastWhereOrNull(
      (value) =>
          value.operation.entityType == type &&
          value.operation.entityId == id &&
          value.attemptCount == 0 &&
          value.rejectedAt == null,
    );
    final operation = SyncOperation(
      operationId: editable?.operation.operationId ?? _uuid.v4(),
      entityType: type,
      entityId: id,
      action: SyncAction.delete,
      baseVersion: previous.version,
      changedFields: const [],
      clientChangedAt: editable?.operation.clientChangedAt ?? now,
    );
    if (editable == null) {
      account.pending.add(_MemoryPending(operation));
    } else {
      editable.operation = operation;
    }
  }

  @override
  Future<int> pendingOperationCount({
    String accountId = DocumentStore.localAccountId,
  }) async =>
      _account(accountId).pending
          .where((value) => value.supersededAt == null)
          .length;

  @override
  Future<String?> readSetting(
    String key, {
    String accountId = DocumentStore.localAccountId,
  }) async => _account(accountId).settings[key];

  @override
  Future<void> writeSetting(
    String key,
    String value, {
    String accountId = DocumentStore.localAccountId,
  }) async {
    _account(accountId).settings[key] = value;
  }

  @override
  Future<bool> ensureAccount(
    String accountId, {
    bool claimLocalData = false,
  }) async {
    if (_accounts.containsKey(accountId)) return false;
    if (claimLocalData && accountId != DocumentStore.localAccountId) {
      final local = _accounts[DocumentStore.localAccountId]!;
      final claimed = _MemoryAccount()
        ..documents.addAll(local.documents)
        ..pending.addAll(local.pending);
      for (final key in const [
        'focus_app_whitelists_v1',
        'legacy_sample_content_removed_v1',
      ]) {
        final value = local.settings.remove(key);
        if (value != null) claimed.settings[key] = value;
      }
      local.documents.clear();
      local.pending.clear();
      _accounts[accountId] = claimed;
      return true;
    }
    _accounts[accountId] = _MemoryAccount();
    return false;
  }

  @override
  Future<void> prepareUnsyncedDocuments(String accountId) async {
    final account = _account(accountId);
    for (final document in account.documents.values.toList()) {
      if (document.version != 0 || document.deleted) continue;
      final hasPending = account.pending.any(
        (value) =>
            value.operation.entityType.wireName == document.entityType &&
            value.operation.entityId == document.id &&
            value.supersededAt == null,
      );
      if (hasPending) continue;
      final type = SyncEntityType.fromWire(document.entityType);
      final patch = SyncEntityContract.cloudPatch(type, document.body);
      if (patch.isEmpty) continue;
      _memoryEnqueueUpsert(
        account,
        type: type,
        entityId: document.id,
        baseVersion: 0,
        patch: patch,
        fullBody: patch,
        createdAt: document.updatedAt,
      );
    }
  }

  @override
  Future<List<SyncOperation>> readPendingOperations(
    String accountId, {
    int limit = 200,
  }) async {
    if (limit < 1 || limit > 200) {
      throw RangeError.range(limit, 1, 200, 'limit');
    }
    final account = _account(accountId);
    final values = <_QueuedSyncOperation>[
      for (var index = 0; index < account.pending.length; index++)
        if (account.pending[index].rejectedAt == null &&
            account.pending[index].supersededAt == null)
          _QueuedSyncOperation(account.pending[index].operation, index),
    ]..sort(_compareQueuedOperations);
    final selected = values.take(limit).toList(growable: false);
    for (final value in selected) {
      final pending = account.pending[value.queueOrder];
      pending.attemptCount++;
      pending.lastAttemptAt = DateTime.now().toUtc();
    }
    return selected.map((value) => value.operation).toList(growable: false);
  }

  @override
  Future<void> applyPushResults(
    String accountId,
    List<SyncOperationResult> results,
  ) async {
    final account = _account(accountId);
    for (final result in results) {
      final pending = account.pending.firstWhereOrNull(
        (value) => value.operation.operationId == result.operationId,
      );
      if (pending == null) continue;
      if (result.status == SyncOperationStatus.rejected) {
        pending.error = result.error;
        pending.rejectedAt = DateTime.now().toUtc();
        final pendingIndex = account.pending.indexOf(pending);
        final hasNewer = account.pending
            .skip(pendingIndex + 1)
            .any(
              (value) =>
                  value.operation.entityType == pending.operation.entityType &&
                  value.operation.entityId == pending.operation.entityId &&
                  value.supersededAt == null,
            );
        if (hasNewer) pending.supersededAt = pending.rejectedAt;
        continue;
      }
      account.pending.remove(pending);
      _memoryApplySnapshot(account, result.snapshot!);
    }
  }

  @override
  Future<int> readSyncCursor(String accountId) async =>
      _account(accountId).cursor;

  @override
  Future<void> applyPullResponse(
    String accountId, {
    required int expectedCursor,
    required SyncPullResponse response,
  }) async {
    final account = _account(accountId);
    if (account.cursor != expectedCursor) {
      throw StateError('Sync cursor changed.');
    }
    var previous = expectedCursor;
    for (final change in response.changes) {
      if (change.cursor <= previous || change.cursor > response.nextCursor) {
        throw const FormatException('Pull changes have invalid cursors.');
      }
      previous = change.cursor;
    }
    if ((response.changes.isNotEmpty && response.nextCursor != previous) ||
        (response.hasMore && response.changes.isEmpty) ||
        response.nextCursor < previous ||
        response.currentCursor < response.nextCursor ||
        (response.hasMore && response.nextCursor <= expectedCursor)) {
      throw const FormatException('Pull response has invalid cursor bounds.');
    }
    for (final change in response.changes) {
      _memoryApplySnapshot(account, change.toSnapshot());
    }
    account.cursor = response.nextCursor;
  }

  void _memoryApplySnapshot(_MemoryAccount account, SyncSnapshot snapshot) {
    final key = _documentKey(snapshot.entityType.wireName, snapshot.entityId);
    final existing = account.documents[key];
    if (existing != null && snapshot.version < existing.version) return;
    var body = SyncEntityContract.mergeRemoteBody(
      snapshot.entityType,
      snapshot.body,
      existing?.body,
    );
    var deleted = snapshot.deleted;
    final pending = account.pending
        .where(
          (value) =>
              value.operation.entityType == snapshot.entityType &&
              value.operation.entityId == snapshot.entityId &&
              value.supersededAt == null,
        )
        .toList();
    for (final value in pending) {
      if (value.operation.action == SyncAction.delete) {
        deleted = true;
      } else {
        body = {...body, ...?value.operation.patch};
        deleted = false;
      }
      if (value.attemptCount == 0 &&
          value.rejectedAt == null &&
          value.operation.baseVersion < snapshot.version) {
        value.operation = SyncOperation(
          operationId: value.operation.operationId,
          entityType: value.operation.entityType,
          entityId: value.operation.entityId,
          action: value.operation.action,
          baseVersion: snapshot.version,
          changedFields: value.operation.changedFields,
          patch: value.operation.patch,
          clientChangedAt: value.operation.clientChangedAt,
        );
      }
    }
    account.documents[key] = StoredDocument(
      entityType: snapshot.entityType.wireName,
      id: snapshot.entityId,
      body: Map.unmodifiable(body),
      version: snapshot.version,
      updatedAt: snapshot.updatedAt,
      deleted: deleted,
      cursor: snapshot.cursor > (existing?.cursor ?? 0)
          ? snapshot.cursor
          : existing?.cursor ?? 0,
    );
  }

  @override
  Future<List<RejectedSyncOperation>> readRejectedOperations(
    String accountId,
  ) async {
    final values = _account(accountId).pending
        .where(
          (value) => value.rejectedAt != null && value.supersededAt == null,
        )
        .map(
          (value) => RejectedSyncOperation(
            operation: value.operation,
            error: value.error!,
            rejectedAt: value.rejectedAt!,
          ),
        )
        .toList();
    values.sort((a, b) => b.rejectedAt.compareTo(a.rejectedAt));
    return values;
  }
}

class _MemoryAccount {
  final Map<String, StoredDocument> documents = {};
  final Map<String, String> settings = {};
  final List<_MemoryPending> pending = [];
  int cursor = 0;
}

const _globalPortableSettings = {
  'theme_preference',
  'use_dynamic_color',
  'notifications_enabled',
};

WorkspaceArchive _makeArchive(
  Iterable<StoredDocument> documents,
  Map<String, String> settings,
  Iterable<SyncOperation> operations,
) {
  final archive = WorkspaceArchive(
    createdAt: DateTime.now().toUtc(),
    documents: documents
        .map(
          (document) => ArchiveDocument(
            entityType: document.entityType,
            id: document.id,
            body: document.body,
            updatedAt: document.updatedAt,
            deleted: document.deleted,
          ),
        )
        .toList(),
    settings: settings,
    pendingChanges: operations.map(ArchivePendingChange.fromOperation).toList(),
  );
  return WorkspaceArchive.decode(archive.encode());
}

List<SyncOperation> _freshWorkspaceOperations(
  WorkspaceArchive archive,
  Uuid uuid,
) {
  final byKey = {for (final doc in archive.documents) doc.key: doc};
  final ordered = <ArchiveDocument>[];
  final visiting = <String>{};
  final visited = <String>{};

  void visit(ArchiveDocument document) {
    if (visited.contains(document.key)) return;
    if (!visiting.add(document.key)) {
      throw const FormatException('数据引用形成循环，无法上传到新服务器。');
    }
    // A task and its recurrence rule refer to each other. Create the task
    // first, then the rule, and attach the rule with a separate later patch.
    final deferredRule = document.entityType == 'task'
        ? document.body['recurrence_rule_id']
        : null;
    for (final reference in document.referenceKeys) {
      if (reference == 'task_recurrence_rule\u0000$deferredRule') continue;
      visit(byKey[reference]!);
    }
    visiting.remove(document.key);
    visited.add(document.key);
    ordered.add(document);
  }

  for (final document in archive.documents.where((doc) => !doc.deleted)) {
    visit(document);
  }
  // Include rules referenced by tasks even if a retained historical rule was
  // deleted. Other historical parents are included by the traversal above.
  for (var index = 0; index < ordered.length; index++) {
    final document = ordered[index];
    if (document.entityType == 'task' &&
        document.body['recurrence_rule_id'] != null) {
      visit(
        byKey['task_recurrence_rule\u0000${document.body['recurrence_rule_id']}']!,
      );
    }
  }
  final operations = <SyncOperation>[];
  final deferred = <SyncOperation>[];
  final deletions = <SyncOperation>[];
  for (final document in ordered) {
    // Referenced tombstones need their original content on the target server
    // so historical focus sessions and calendar records retain valid links.
    // Validate the content as a create before beginning the restore transaction.
    if (document.deleted) {
      ArchiveDocument.fromJson({...document.toJson(), 'deleted': false});
    }
    final type = SyncEntityType.fromWire(document.entityType);
    final patch = SyncEntityContract.cloudPatch(type, document.body);
    if (patch.isEmpty) continue;
    SyncOperation operation(
      SyncAction action,
      Map<String, Object?>? patch, {
      int baseVersion = 0,
    }) => SyncOperation(
      operationId: uuid.v4(),
      entityType: type,
      entityId: document.id,
      action: action,
      baseVersion: baseVersion,
      changedFields: patch?.keys.toList() ?? const [],
      patch: patch,
      clientChangedAt: document.updatedAt,
    );
    if (type == SyncEntityType.task && patch['recurrence_rule_id'] != null) {
      deferred.add(
        operation(SyncAction.upsert, {
          'recurrence_rule_id': patch['recurrence_rule_id'],
        }, baseVersion: 1),
      );
      patch['recurrence_rule_id'] = null;
    }
    operations.add(operation(SyncAction.upsert, patch));
    if (document.deleted) {
      // The immediately preceding create produces version one on the target.
      // This value is independent of the old server's versions.
      deletions.add(operation(SyncAction.delete, null, baseVersion: 1));
    }
  }
  return [...operations, ...deferred, ...deletions];
}

void _validateNewWorkspaceId(String accountId) {
  if (accountId.trim().isEmpty || accountId == DocumentStore.localAccountId) {
    throw ArgumentError('A new workspace ID is required.');
  }
}

void _validateLegacyMigration(String legacyId, String namespacedId) {
  _validateNewWorkspaceId(namespacedId);
  if (legacyId == namespacedId ||
      legacyId.startsWith('__local__') ||
      !_legacyAccountId.hasMatch(legacyId)) {
    throw ArgumentError(
      'Migration requires a legacy user ID and a separate namespace.',
    );
  }
}

final _legacyAccountId = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class _MemoryPending {
  _MemoryPending(this.operation);

  SyncOperation operation;
  int attemptCount = 0;
  DateTime? lastAttemptAt;
  DateTime? rejectedAt;
  DateTime? supersededAt;
  SyncError? error;
}

extension _IterableLookup<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }

  T? lastWhereOrNull(bool Function(T value) test) {
    T? result;
    for (final value in this) {
      if (test(value)) result = value;
    }
    return result;
  }
}

Map<String, Object?> _decodeMap(String encoded) {
  final value = jsonDecode(encoded);
  if (value is! Map) throw const FormatException('Expected a JSON object.');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

Map<String, Object?> _changedValues(
  Map<String, Object?> previous,
  Map<String, Object?> current,
) {
  return {
    for (final entry in current.entries)
      if (!previous.containsKey(entry.key) ||
          !_jsonEquivalent(previous[entry.key], entry.value))
        entry.key: entry.value,
    for (final key in previous.keys)
      if (!current.containsKey(key)) key: null,
  };
}

bool _jsonEquivalent(Object? left, Object? right) {
  return jsonEncode(left) == jsonEncode(right);
}

class _QueuedSyncOperation {
  const _QueuedSyncOperation(this.operation, this.queueOrder);

  final SyncOperation operation;
  final int queueOrder;
}

int _compareQueuedOperations(
  _QueuedSyncOperation left,
  _QueuedSyncOperation right,
) {
  final priority = _queuePriority(left.operation)
      .compareTo(_queuePriority(right.operation));
  if (priority != 0) return priority;
  return left.queueOrder.compareTo(right.queueOrder);
}

int _queuePriority(SyncOperation operation) {
  if (operation.entityType == SyncEntityType.task &&
      operation.action == SyncAction.upsert &&
      operation.patch?.length == 1 &&
      operation.patch!.containsKey('recurrence_rule_id')) {
    return 35;
  }
  return SyncEntityContract.dependencyPriority(operation);
}
