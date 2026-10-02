import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/sync/sync_models.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/local/workspace_backup.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _account = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _project = '11111111-1111-4111-8111-111111111111';
const _task = '22222222-2222-4222-8222-222222222222';
const _deletedTask = '33333333-3333-4333-8333-333333333333';
final _now = DateTime.utc(2026, 9, 29);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  for (final backend in ['memory', 'sqlite']) {
    group('$backend portable workspace', () {
      late DocumentStore store;
      setUp(() async {
        store = backend == 'memory'
            ? MemoryDocumentStore()
            : LocalDatabase(
                databasePath: inMemoryDatabasePath,
                factory: databaseFactoryFfi,
              );
        await _seed(store);
      });
      tearDown(() async {
        if (store is LocalDatabase) await (store as LocalDatabase).close();
      });

      test('exports settings, tombstones and latest unsynced edits without credentials', () async {
        final json = await WorkspaceBackupService(store).exportJson(_account);
        final archive = WorkspaceArchive.decode(json);
        expect(archive.documents, hasLength(3));
        expect(
          archive.documents
              .singleWhere((value) => value.id == _task)
              .body['title'],
          '离线修改',
        );
        expect(
          archive.documents
              .singleWhere((value) => value.id == _deletedTask)
              .deleted,
          isTrue,
        );
        expect(archive.pendingChanges, hasLength(2));
        expect(archive.settings['theme_preference'], 'dark');
        expect(
          archive.settings['focus_app_whitelists_v1'],
          contains('com.example.app'),
        );
        for (final secret in [
          'private-token',
          'password',
          'server_url',
          'operation_id',
          'base_version',
          'cursor',
          _account,
        ]) {
          expect(json, isNot(contains(secret)));
        }
        // Export is a snapshot and must not count as a sync attempt.
        final operationBefore = (await store.exportWorkspace(_account))
            .pendingChanges
            .first;
        expect(operationBefore.patch?['title'], '离线修改');
      });

      test(
        'offline restore and local copy preserve the source and user content',
        () async {
          final service = WorkspaceBackupService(store);
          final original = await service.exportJson(_account);
          final restoredId = await service.restoreJson(original);
          final copiedId = await service.copyToLocal(_account);
          expect(restoredId, startsWith('__local__:'));
          expect(copiedId, isNot(restoredId));
          for (final id in [restoredId, copiedId]) {
            expect(await store.readSyncCursor(id), 0);
            expect(await store.pendingOperationCount(accountId: id), 0);
            final restored = await store.exportWorkspace(id);
            expect(
              restored.documents.map((doc) => doc.toJson()).toList(),
              WorkspaceArchive.decode(original).documents
                  .map((doc) => doc.toJson())
                  .toList(),
            );
            expect(
              await store.readSetting('focus_app_whitelists_v1', accountId: id),
              contains('com.example.app'),
            );
          }
          expect(await store.readSyncCursor(_account), 3);
          expect(await store.pendingOperationCount(accountId: _account), 2);
          expect(
            (await store.readDocuments(
              'task',
              accountId: _account,
            )).single.body['title'],
            '离线修改',
          );
        },
      );

      test(
        'new server gets fresh full operations, zero versions and zero cursor',
        () async {
          final oldOperations = await store.readPendingOperations(_account);
          await store.copyWorkspace(
            _account,
            'https://other.example|$_account',
            enqueueForSync: true,
          );
          final target = 'https://other.example|$_account';
          final fresh = await store.readPendingOperations(target);
          expect(fresh, hasLength(2));
          expect(fresh.map((op) => op.entityType), [
            SyncEntityType.project,
            SyncEntityType.task,
          ]);
          for (final operation in fresh) {
            expect(operation.baseVersion, 0);
            expect(operation.action, SyncAction.upsert);
            expect(
              oldOperations.map((old) => old.operationId),
              isNot(contains(operation.operationId)),
            );
          }
          expect(fresh.last.patch?['title'], '离线修改');
          expect(fresh.last.patch?['project_id'], _project);
          expect(fresh.last.patch, isNot(contains('tags')));
          expect(await store.readSyncCursor(target), 0);
          expect(
            (await store.readDocuments(
              'task',
              accountId: target,
            )).single.version,
            0,
          );
        },
      );

      test('same-server legacy migration retains queue, versions and original data', () async {
        const target = 'https://original.example|$_account';
        final before = await store.readPendingOperations(_account);
        expect(await store.migrateLegacyAccount(_account, target), isTrue);
        final after = await store.readPendingOperations(target);
        expect(
          after.map((op) => op.toJson()).toList(),
          before.map((op) => op.toJson()).toList(),
        );
        expect(await store.readSyncCursor(target), 3);
        expect(
          (await store.readDocuments('task', accountId: target)).single.version,
          4,
        );
        await store.putDocument(
          'task',
          _task,
          _taskBody('修改副本'),
          accountId: target,
        );
        expect(
          (await store.readDocuments(
            'task',
            accountId: _account,
          )).single.body['title'],
          '离线修改',
        );
        expect(await store.migrateLegacyAccount(_account, target), isFalse);
        expect(await store.listWorkspaceIds(), containsAll([_account, target]));
      });

      test('cross-server history retains links to deleted tasks', () async {
        const blockId = '44444444-4444-4444-8444-444444444444';
        await store.putDocument('plan_block', blockId, {
          'task_id': _deletedTask,
          'title': '历史计划',
          'starts_at': _now.toIso8601String(),
          'ends_at': _now.add(const Duration(hours: 1)).toIso8601String(),
          'status': 'completed',
        }, accountId: _account);
        await store.copyWorkspace(
          _account,
          'history-copy',
          enqueueForSync: true,
        );
        final operations = await store.readPendingOperations('history-copy');
        final historical = operations
            .where((op) => op.entityId == _deletedTask)
            .toList();
        expect(historical.map((op) => op.action), [
          SyncAction.upsert,
          SyncAction.delete,
        ]);
        _verifyBootstrap(operations);
      });

      test(
        'cross-server recurring tasks create the rule before attaching it',
        () async {
          const ruleId = '55555555-5555-4555-8555-555555555555';
          await store.putDocument('task_recurrence_rule', ruleId, {
            'task_id': _task,
            'frequency': 'daily',
            'interval': 1,
            'starts_on': '2026-09-29',
            'time_zone': 'Asia/Shanghai',
          }, accountId: _account);
          await store.putDocument('task', _task, {
            ..._taskBody('周期任务'),
            'recurrence_rule_id': ruleId,
          }, accountId: _account);
          await store.copyWorkspace(
            _account,
            'recurrence-copy',
            enqueueForSync: true,
          );
          final operations = await store.readPendingOperations(
            'recurrence-copy',
          );
          final tasks = operations.where((op) => op.entityId == _task).toList();
          expect(tasks, hasLength(2));
          expect(tasks.first.patch!['recurrence_rule_id'], isNull);
          expect(tasks.last.patch!['recurrence_rule_id'], ruleId);
          expect(tasks.last.baseVersion, 1);
          _verifyBootstrap(operations);
        },
      );

      test(
        'existing target is rejected without changing either workspace',
        () async {
          final archive = await store.exportWorkspace(_account);
          final before = (await store.readDocuments(
            'task',
            accountId: _account,
          )).single;
          await expectLater(
            store.restoreWorkspace(archive, accountId: _account),
            throwsStateError,
          );
          expect(
            (await store.readDocuments(
              'task',
              accountId: _account,
            )).single.body,
            before.body,
          );
          expect(await store.readSyncCursor(_account), 3);
        },
      );

      for (final corruption in [
        'version',
        'reference',
        'duplicate',
        'body',
        'credential',
        'pending',
      ]) {
        test(
          'rejects invalid $corruption before creating a workspace',
          () async {
            final data = (await store.exportWorkspace(_account)).toJson();
            final docs = data['documents']! as List;
            switch (corruption) {
              case 'version':
                data['version'] = 99;
              case 'reference':
                (docs[1] as Map)['body'] = {
                  ...Map<String, Object?>.from((docs[1] as Map)['body'] as Map),
                  'project_id': '99999999-9999-4999-8999-999999999999',
                };
              case 'duplicate':
                docs.add(docs.first);
              case 'body':
                (docs[1] as Map)['body'] = {'title': 42};
              case 'credential':
                data['settings'] = {'access_token': 'secret'};
              case 'pending':
                (data['pending_changes'] as List).add({
                  'entity_type': 'task',
                  'entity_id': '99999999-9999-4999-8999-999999999999',
                  'action': 'delete',
                  'patch': null,
                  'changed_at': _now.toIso8601String(),
                });
            }
            final before = await store.listWorkspaceIds();
            await expectLater(
              WorkspaceBackupService(store).restoreJson(jsonEncode(data)),
              throwsFormatException,
            );
            expect(await store.listWorkspaceIds(), before);
            expect(await store.readSyncCursor(_account), 3);
          },
        );
      }
    });
  }

  test(
    'SQLite failure halfway through restore rolls back all new rows',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'workspace-backup-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final databasePath = '${directory.path}/backup.db';
      final store = LocalDatabase(
        databasePath: databasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(store.close);
      await _seed(store);
      final archive = await store.exportWorkspace(_account);
      final shared = await databaseFactoryFfi.openDatabase(databasePath);
      await shared.execute('''
      CREATE TEMP TRIGGER reject_import BEFORE INSERT ON documents
      WHEN NEW.account_id = 'failed-target' AND NEW.entity_type = 'task'
      BEGIN SELECT RAISE(ABORT, 'injected restore failure'); END
    ''');
      await expectLater(
        store.restoreWorkspace(archive, accountId: 'failed-target'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await store.listWorkspaceIds(), isNot(contains('failed-target')));
      expect(
        await store.readDocuments('project', accountId: 'failed-target'),
        isEmpty,
      );
      expect(await store.readSyncCursor(_account), 3);
      await store.close();
    },
  );
}

Map<String, Object?> _taskBody(String title) => {
  'title': title,
  'project_id': _project,
  'priority': 'medium',
  'status': 'open',
  'rank': 12.5,
  'tags': ['本地标签'],
};

Future<void> _seed(DocumentStore store) async {
  await store.ensureAccount(_account);
  await store.applyPullResponse(
    _account,
    expectedCursor: 0,
    response: SyncPullResponse(
      changes: [
        _change(1, SyncEntityType.project, _project, {
          'name': '项目',
          'color': '#5367A5',
        }, 2),
        _change(2, SyncEntityType.task, _task, _taskBody('原任务'), 4),
        _change(3, SyncEntityType.task, _deletedTask, _taskBody('待删除任务'), 1),
      ],
      nextCursor: 3,
      currentCursor: 3,
      hasMore: false,
    ),
  );
  await store.putDocument(
    'task',
    _task,
    _taskBody('离线修改'),
    accountId: _account,
  );
  await store.deleteDocument('task', _deletedTask, accountId: _account);
  await store.writeSetting(
    'focus_app_whitelists_v1',
    '{"inbox":["com.example.app"]}',
    accountId: _account,
  );
  await store.writeSetting('theme_preference', 'dark');
  await store.writeSetting('password', 'private-token', accountId: _account);
  await store.writeSetting(
    'server_url',
    'https://private.example',
    accountId: _account,
  );
}

void _verifyBootstrap(List<SyncOperation> operations) {
  final bodies = <String, Map<String, Object?>>{};
  final versions = <String, int>{};
  final deleted = <String>{};
  for (final operation in operations) {
    final key = '${operation.entityType.wireName}\u0000${operation.entityId}';
    if (operation.action == SyncAction.delete) {
      expect(versions.containsKey(key), isTrue);
      expect(operation.baseVersion, lessThanOrEqualTo(versions[key]!));
      deleted.add(key);
    } else {
      expect(deleted, isNot(contains(key)));
      expect(operation.baseVersion, versions[key] ?? 0);
      final body = {...?bodies[key], ...operation.patch!};
      final document = ArchiveDocument(
        entityType: operation.entityType.wireName,
        id: operation.entityId,
        body: body,
        updatedAt: _now,
        deleted: false,
      );
      expect(bodies.keys, containsAll(document.referenceKeys));
      bodies[key] = body;
    }
    versions[key] = (versions[key] ?? 0) + 1;
  }
}

SyncChange _change(
  int cursor,
  SyncEntityType type,
  String id,
  Map<String, Object?> body,
  int version,
) => SyncChange(
  cursor: cursor,
  changeId: 'change-$cursor',
  entityType: type,
  entityId: id,
  action: SyncAction.upsert,
  version: version,
  body: body,
  changedFields: body.keys.toList(),
  deviceId: 'old-device',
  changedAt: _now,
);
