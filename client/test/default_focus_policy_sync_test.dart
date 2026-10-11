import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/core/sync/sync_models.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/remote/api_client.dart';
import 'package:pactick/data/remote/server_address.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _normalId = '51111111-1111-4111-8111-111111111111';
const _guardId = '52222222-2222-4222-8222-222222222222';
const _unknownPolicyId = '53333333-3333-4333-8333-333333333333';
const _taskId = '61111111-aaaa-4111-8111-111111111111';
const _deviceA = '71111111-aaaa-4111-8111-111111111111';
const _deviceB = '72222222-aaaa-4222-8222-222222222222';
const _user = '81111111-aaaa-4111-8111-111111111111';

final _account = serverWorkspaceId(
  Uri.parse('https://one.example.test'),
  _user,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  for (final backend in ['memory', 'sqlite']) {
    group('$backend default policy collision recovery', () {
      late Directory directory;
      late List<LocalDatabase> databases;
      var databaseNumber = 0;

      setUp(() async {
        directory = await Directory.systemTemp.createTemp(
          'pactick-policy-test-',
        );
        databases = [];
        databaseNumber = 0;
      });

      tearDown(() async {
        for (final database in databases.reversed) {
          await database.close();
        }
        await directory.delete(recursive: true);
      });

      DocumentStore newStore({String? databasePath}) {
        if (backend == 'memory') return MemoryDocumentStore();
        final database = LocalDatabase(
          databasePath:
              databasePath ??
              '${directory.path}/workspace-${databaseNumber++}.db',
          factory: databaseFactoryFfi,
        );
        databases.add(database);
        return database;
      }

      Future<_Client> newClient({String device = _deviceB}) async {
        return _connect(newStore(), device: device);
      }

      test(
        'a second device adopts existing policies and still syncs tasks',
        () async {
          final server = _StrictSyncApi();
          final a = await newClient(device: _deviceA);
          final b = await newClient();

          _expectSettled(await a.repository.syncNow(server));
          final secondLogin = await b.repository.syncNow(server);
          _expectSettled(secondLogin);
          expect(server.duplicateCreates, 2);
          expect(server.livePolicies, hasLength(2));
          expect(secondLogin.workspace.focusPolicies.map((p) => p.id).toSet(), {
            _normalId,
            _guardId,
          });

          await b.repository.saveTask(_task('created on the second device'));
          _expectSettled(await b.repository.syncNow(server));
          final downloaded = await a.repository.syncNow(server);
          _expectSettled(downloaded);
          expect(
            downloaded.workspace.tasks.single.title,
            'created on the second device',
          );
          expect(
            server.history.where((c) => c.entityType == SyncEntityType.task),
            hasLength(1),
          );
        },
      );

      test(
        'simultaneous first logins recover the losing create race',
        () async {
          final server = _StrictSyncApi();
          final a = await newClient(device: _deviceA);
          final b = await newClient();
          final bothPushing = Completer<void>();
          var arrivals = 0;
          server.beforePush = () async {
            if (++arrivals == 2) bothPushing.complete();
            await bothPushing.future;
          };

          final results = await Future.wait([
            a.repository.syncNow(server),
            b.repository.syncNow(server),
          ]);
          for (final result in results) {
            _expectSettled(result);
          }
          expect(server.duplicateCreates, 2);
          expect(server.history, hasLength(2));
          expect(server.livePolicies, hasLength(2));
        },
      );

      test(
        'persisted rejections recover after the cursor caught up and a reopen',
        () async {
          final server = _StrictSyncApi()..seedDefaults();
          server.write(
            SyncEntityType.task,
            _taskId,
            _task('historical server task').toBody(),
          );
          var client = await newClient();
          await _leaveLegacyRejections(client, server);
          final savedCursor = await client.store.readSyncCursor(_account);
          expect(
            await client.store.readRejectedOperations(_account),
            hasLength(2),
          );
          await client.store.putDocument(
            'task',
            _taskId,
            _task('local document must not be replayed').toBody(),
            accountId: _account,
            enqueue: false,
          );

          if (client.store is LocalDatabase) {
            final database = client.store as LocalDatabase;
            final databasePath = database.databasePath!;
            await database.close();
            client = await _connect(newStore(databasePath: databasePath));
          } else {
            client = await _connect(client.store);
          }
          server.pullCursors.clear();

          final result = await client.repository.syncNow(
            server,
            pullPageSize: 1,
          );
          _expectSettled(result);
          expect(server.pullCursors.first, savedCursor);
          expect(server.pullCursors.skip(1), contains(0));
          expect(await client.store.readSyncCursor(_account), savedCursor);
          expect(
            result.workspace.tasks.single.title,
            'local document must not be replayed',
          );
        },
      );

      test(
        'the latest remote policy edits replace untouched local defaults',
        () async {
          final server = _StrictSyncApi()..seedDefaults();
          final client = await newClient();
          await _leaveLegacyRejections(client, server);
          server.write(SyncEntityType.focusPolicy, _normalId, {
            ..._policyBody(_normalId),
            'name': 'remote revision two',
            'notification_mode': 'sound_and_vibrate',
          });
          server.write(SyncEntityType.focusPolicy, _normalId, {
            ..._policyBody(_normalId),
            'name': 'remote revision three',
            'sound_enabled': true,
          });

          final result = await client.repository.syncNow(
            server,
            pullPageSize: 1,
          );
          _expectSettled(result);
          final local = (await client.store.readDocuments(
            'focus_policy',
            accountId: _account,
          )).singleWhere((d) => d.id == _normalId);
          expect(local.body['name'], 'remote revision three');
          expect(local.body['sound_enabled'], isTrue);
          expect(local.version, 3);
          expect(
            server.entity(SyncEntityType.focusPolicy, _normalId).body['name'],
            'remote revision three',
          );
          expect(
            server.history.where((c) => c.entityId == _normalId),
            hasLength(3),
          );
        },
      );

      test(
        'a genuinely edited policy create remains rejected and intact',
        () async {
          final server = _StrictSyncApi()..seedDefaults();
          final client = await newClient();
          await client.store.putDocument('focus_policy', _normalId, {
            ..._policyBody(_normalId),
            'name': 'intentional local policy',
            'notification_mode': 'sound_and_vibrate',
          }, accountId: _account);

          final result = await client.repository.syncNow(server);
          expect(result.rejections, hasLength(1));
          final rejection = result.rejections.single;
          expect(rejection.operation.entityId, _normalId);
          expect(
            rejection.operation.patch!['name'],
            'intentional local policy',
          );
          expect(result.workspace.pendingOperations, 1);
          expect(
            result.workspace.focusPolicies
                .singleWhere((p) => p.id == _normalId)
                .name,
            'intentional local policy',
          );
          expect(
            server.entity(SyncEntityType.focusPolicy, _normalId).body['name'],
            '灵活专注',
          );
          final retried = await client.repository.syncNow(server);
          expect(
            retried.rejections.single.operation.operationId,
            rejection.operation.operationId,
          );
          expect(retried.workspace.pendingOperations, 1);
        },
      );

      test(
        'unknown policies, task collisions, and different errors stay rejected',
        () async {
          final server = _StrictSyncApi()..seedDefaults();
          server.write(SyncEntityType.focusPolicy, _unknownPolicyId, {
            ..._policyBody(_normalId),
            'name': 'existing custom policy',
          });
          server.write(
            SyncEntityType.task,
            _taskId,
            _task('existing task').toBody(),
          );
          server.forcedErrors[_key(SyncEntityType.focusPolicy, _normalId)] =
              'validation_error';
          final client = await newClient();
          await client.store.putDocument('focus_policy', _unknownPolicyId, {
            ..._policyBody(_normalId),
            'name': 'local custom policy',
          }, accountId: _account);
          await client.repository.saveTask(_task('local task'));

          final result = await client.repository.syncNow(server);
          expect(result.rejections, hasLength(3));
          expect(
            result.rejections
                .map((r) => '${r.operation.entityId}:${r.error.code}')
                .toSet(),
            {
              '$_normalId:validation_error',
              '$_unknownPolicyId:entity_exists',
              '$_taskId:entity_exists',
            },
          );
          expect(result.workspace.pendingOperations, 3);
          expect(result.workspace.tasks.single.title, 'local task');
          expect(
            result.workspace.focusPolicies
                .singleWhere((p) => p.id == _unknownPolicyId)
                .name,
            'local custom policy',
          );
        },
      );

      test('repair leaves other accounts and servers untouched', () async {
        final otherAccount = serverWorkspaceId(
          Uri.parse('https://one.example.test'),
          '82222222-aaaa-4222-8222-222222222222',
        );
        final otherServer = serverWorkspaceId(
          Uri.parse('https://two.example.test'),
          _user,
        );
        final store = newStore();
        final target = await _connect(store);
        final server = _StrictSyncApi()..seedDefaults();
        await _leaveLegacyRejections(target, server);
        for (final accountId in [otherAccount, otherServer]) {
          final client = await _connect(store, accountId: accountId);
          await _leaveLegacyRejections(
            client,
            _StrictSyncApi()..seedDefaults(),
          );
        }
        final untouched = <String, List<String>>{};
        for (final accountId in [otherAccount, otherServer]) {
          untouched[accountId] = (await store.readRejectedOperations(accountId))
              .map((r) => r.operation.operationId)
              .toList();
        }
        final selected = await _connect(store);

        _expectSettled(await selected.repository.syncNow(server));
        for (final accountId in [otherAccount, otherServer]) {
          expect(
            (await store.readRejectedOperations(accountId))
                .map((r) => r.operation.operationId),
            untouched[accountId],
          );
          expect(await store.pendingOperationCount(accountId: accountId), 2);
          expect(await store.readSyncCursor(accountId), 2);
        }
      });

      test(
        'adoption retains the local whitelist without uploading it',
        () async {
          final server = _StrictSyncApi()..seedDefaults();
          server.write(SyncEntityType.focusPolicy, _normalId, {
            ..._policyBody(_normalId),
            'name': 'server policy with local whitelist',
          });
          final client = await newClient();
          await client.store.putDocument('focus_policy', _normalId, {
            ..._policyBody(_normalId),
            'allowed_app_ids': ['com.private.application'],
          }, accountId: _account);

          _expectSettled(await client.repository.syncNow(server));
          final local = (await client.store.readDocuments(
            'focus_policy',
            accountId: _account,
          )).singleWhere((d) => d.id == _normalId);
          expect(local.body['allowed_app_ids'], ['com.private.application']);
          expect(local.body['name'], 'server policy with local whitelist');
          expect(
            server.submitted
                .expand((batch) => batch)
                .every(
                  (operation) =>
                      !operation.patch!.containsKey('allowed_app_ids'),
                ),
            isTrue,
          );
        },
      );

      test('an edit arriving during history pagination is retained and later uploaded', () async {
        final server = _StrictSyncApi()..seedDefaults();
        final client = await newClient();
        await _leaveLegacyRejections(client, server);
        final pageWaiting = Completer<void>();
        final continuePage = Completer<void>();
        server.pullOverride = (cursor, limit) async {
          if (cursor == 1) {
            pageWaiting.complete();
            await continuePage.future;
          }
          return null;
        };

        final syncing = client.repository.syncNow(server, pullPageSize: 1);
        await pageWaiting.future;
        try {
          await client.store.putDocument('focus_policy', _normalId, {
            ..._policyBody(_normalId),
            'name': 'edited while fetching history',
          }, accountId: _account);
        } finally {
          continuePage.complete();
        }
        final result = await syncing;
        expect(result.rejections, isEmpty);
        expect(result.workspace.pendingOperations, 1);
        expect(
          result.workspace.focusPolicies
              .singleWhere((p) => p.id == _normalId)
              .name,
          'edited while fetching history',
        );
        expect(
          server.entity(SyncEntityType.focusPolicy, _normalId).body['name'],
          '灵活专注',
        );

        server.pullOverride = null;
        _expectSettled(await client.repository.syncNow(server));
        expect(
          server.entity(SyncEntityType.focusPolicy, _normalId).body['name'],
          'edited while fetching history',
        );
      });

      test(
        'missing history snapshots do not clear duplicate create rejections',
        () async {
          final server = _StrictSyncApi()..seedDefaults();
          final client = await newClient();
          await _leaveLegacyRejections(client, server);
          final before = await _rejectedIds(client);
          server.pullOverride = (cursor, limit) async => SyncPullResponse(
            changes: const [],
            nextCursor: cursor,
            currentCursor: server.cursor,
            hasMore: false,
          );

          final result = await client.repository.syncNow(server);
          expect(result.rejections, hasLength(2));
          expect(await _rejectedIds(client), before);
          expect(result.workspace.pendingOperations, 2);
          expect(await client.store.readSyncCursor(_account), 2);
        },
      );

      test(
        'a latest tombstone is not treated as an existing default policy',
        () async {
          final server = _StrictSyncApi()..seedDefaults();
          final client = await newClient();
          await _leaveLegacyRejections(client, server);
          final before = await _rejectedIds(client);
          server.write(
            SyncEntityType.focusPolicy,
            _normalId,
            _policyBody(_normalId),
            deleted: true,
          );
          server.write(
            SyncEntityType.focusPolicy,
            _guardId,
            _policyBody(_guardId),
            deleted: true,
          );

          final result = await client.repository.syncNow(
            server,
            pullPageSize: 1,
          );
          expect(result.rejections, hasLength(2));
          expect(await _rejectedIds(client), before);
          expect(result.workspace.pendingOperations, 2);
        },
      );

      for (final failure in ['network failure', 'invalid cursor']) {
        test(
          '$failure on a later history page leaves rejection recovery uncommitted',
          () async {
            final server = _StrictSyncApi()..seedDefaults();
            final client = await newClient();
            await _leaveLegacyRejections(client, server);
            final before = await _rejectedIds(client);
            final savedCursor = await client.store.readSyncCursor(_account);
            server.pullOverride = (cursor, limit) async {
              if (cursor != 1) return null;
              if (failure == 'network failure') {
                throw const ApiNetworkException('history request failed');
              }
              return SyncPullResponse(
                changes: [server.history.last],
                nextCursor: 1,
                currentCursor: server.cursor,
                hasMore: false,
              );
            };

            await expectLater(
              client.repository.syncNow(server, pullPageSize: 1),
              throwsA(
                failure == 'network failure'
                    ? isA<ApiNetworkException>()
                    : isA<FormatException>(),
              ),
            );
            expect(await _rejectedIds(client), before);
            expect(
              await client.store.pendingOperationCount(accountId: _account),
              2,
            );
            expect(await client.store.readSyncCursor(_account), savedCursor);
          },
        );
      }
    });
  }
}

Future<_Client> _connect(
  DocumentStore store, {
  String? accountId,
  String device = _deviceB,
}) async {
  final selected = accountId ?? _account;
  final repository = WorkspaceRepository(store);
  await repository.selectAccount(userId: selected, deviceId: device);
  return _Client(store, repository, selected);
}

Future<void> _leaveLegacyRejections(
  _Client client,
  _StrictSyncApi server,
) async {
  final operations = await client.store.readPendingOperations(client.accountId);
  final pushed = await server.pushChanges(operations);
  await client.store.applyPushResults(client.accountId, pushed.results);
  var cursor = await client.store.readSyncCursor(client.accountId);
  while (true) {
    final response = await server.pullChanges(cursor: cursor);
    await client.store.applyPullResponse(
      client.accountId,
      expectedCursor: cursor,
      response: response,
    );
    cursor = response.nextCursor;
    if (!response.hasMore) break;
  }
  expect(
    await client.store.readRejectedOperations(client.accountId),
    hasLength(2),
  );
}

Future<List<String>> _rejectedIds(_Client client) async =>
    (await client.store.readRejectedOperations(client.accountId))
        .map((rejection) => rejection.operation.operationId)
        .toList()
      ..sort();

void _expectSettled(SyncRunResult result) {
  expect(result.rejections, isEmpty);
  expect(result.needsAttention, isFalse);
  expect(result.workspace.pendingOperations, 0);
}

TaskItem _task(String title) => TaskItem(
  id: _taskId,
  title: title,
  priority: TaskPriority.none,
  status: TaskStatus.open,
  rank: 10,
);

Map<String, Object?> _policyBody(String id) {
  final guard = id == _guardId;
  return {
    'name': guard ? '深度守护' : '灵活专注',
    'mode': guard ? 'guard' : 'normal',
    'allow_pause': !guard,
    'early_exit_mode': guard ? 'countdown' : 'allow',
    'early_exit_wait_seconds': guard ? 10 : null,
    'max_app_exits': guard ? 2 : null,
    'emergency_app_categories': ['phone', 'maps', 'authentication'],
    'notification_mode': guard ? 'sound_and_vibrate' : 'vibrate',
  };
}

class _Client {
  const _Client(this.store, this.repository, this.accountId);

  final DocumentStore store;
  final WorkspaceRepository repository;
  final String accountId;
}

String _key(SyncEntityType type, String id) => '${type.wireName}:$id';

// This fake models the create/update distinction that the older permissive
// sync fake omitted. It stores authoritative snapshots and append-only history.
class _StrictSyncApi implements SyncApi {
  final Map<String, SyncSnapshot> _entities = {};
  final Map<String, SyncOperationResult> _applied = {};
  final Map<String, String> forcedErrors = {};
  final List<SyncChange> history = [];
  final List<List<SyncOperation>> submitted = [];
  final List<int> pullCursors = [];
  Future<void> Function()? beforePush;
  Future<SyncPullResponse?> Function(int cursor, int limit)? pullOverride;
  int cursor = 0;
  int duplicateCreates = 0;

  Iterable<SyncSnapshot> get livePolicies => _entities.values.where(
    (entity) =>
        entity.entityType == SyncEntityType.focusPolicy && !entity.deleted,
  );

  SyncSnapshot entity(SyncEntityType type, String id) =>
      _entities[_key(type, id)]!;

  void seedDefaults() {
    write(SyncEntityType.focusPolicy, _normalId, _policyBody(_normalId));
    write(SyncEntityType.focusPolicy, _guardId, _policyBody(_guardId));
  }

  SyncSnapshot write(
    SyncEntityType type,
    String id,
    Map<String, Object?> body, {
    bool deleted = false,
  }) {
    final previous = _entities[_key(type, id)];
    final version = (previous?.version ?? 0) + 1;
    cursor++;
    final timestamp = DateTime.utc(
      2026,
      10,
      3,
      10,
    ).add(Duration(seconds: cursor));
    final snapshot = SyncSnapshot(
      entityType: type,
      entityId: id,
      version: version,
      body: Map.from(body),
      deleted: deleted,
      updatedAt: timestamp,
      cursor: cursor,
    );
    _entities[_key(type, id)] = snapshot;
    history.add(
      SyncChange(
        cursor: cursor,
        changeId:
            '90000000-0000-4000-8000-${cursor.toString().padLeft(12, '0')}',
        entityType: type,
        entityId: id,
        action: deleted ? SyncAction.delete : SyncAction.upsert,
        version: version,
        body: Map.from(body),
        changedFields: body.keys.toList(),
        deviceId: _deviceA,
        changedAt: timestamp,
      ),
    );
    return snapshot;
  }

  @override
  Future<SyncPushResponse> pushChanges(List<SyncOperation> operations) async {
    submitted.add(List.of(operations));
    await beforePush?.call();
    final results = <SyncOperationResult>[];
    for (final operation in operations) {
      final priorResult = _applied[operation.operationId];
      if (priorResult != null) {
        results.add(priorResult);
        continue;
      }
      final entityKey = _key(operation.entityType, operation.entityId);
      final existing = _entities[entityKey];
      var error = forcedErrors[entityKey];
      if (error == null && operation.action == SyncAction.upsert) {
        if (existing?.deleted == true) {
          error = 'entity_tombstoned';
        } else if (existing != null && operation.baseVersion == 0) {
          error = 'entity_exists';
          duplicateCreates++;
        } else if (existing == null && operation.baseVersion != 0) {
          error = 'entity_not_found';
        } else if (existing != null &&
            operation.baseVersion > existing.version) {
          error = 'future_base_version';
        }
      }
      if (error != null) {
        results.add(
          SyncOperationResult(
            operationId: operation.operationId,
            status: SyncOperationStatus.rejected,
            error: SyncError(code: error, message: error),
          ),
        );
        continue;
      }
      final body = <String, Object?>{...?existing?.body};
      for (final entry
          in (operation.patch ?? const <String, Object?>{}).entries) {
        if (entry.value == null) {
          body.remove(entry.key);
        } else {
          body[entry.key] = entry.value;
        }
      }
      final snapshot = write(
        operation.entityType,
        operation.entityId,
        body,
        deleted: operation.action == SyncAction.delete,
      );
      final result = SyncOperationResult(
        operationId: operation.operationId,
        status: SyncOperationStatus.applied,
        snapshot: snapshot,
      );
      _applied[operation.operationId] = result;
      results.add(result);
    }
    return SyncPushResponse(results: results, currentCursor: cursor);
  }

  @override
  Future<SyncPullResponse> pullChanges({
    required int cursor,
    int limit = 500,
  }) async {
    pullCursors.add(cursor);
    final overridden = await pullOverride?.call(cursor, limit);
    if (overridden != null) return overridden;
    final selected = history
        .where((change) => change.cursor > cursor)
        .take(limit)
        .toList();
    final nextCursor = selected.isEmpty ? cursor : selected.last.cursor;
    return SyncPullResponse(
      changes: selected,
      nextCursor: nextCursor,
      currentCursor: this.cursor,
      hasMore: history.any((change) => change.cursor > nextCursor),
    );
  }
}
