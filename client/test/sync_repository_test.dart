import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/sync/sync_entity_contract.dart';
import 'package:pactick/core/sync/sync_models.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/remote/api_client.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';

const _userA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _userB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _device = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _projectId = '11111111-aaaa-4111-8111-111111111111';
const _taskId = '22222222-aaaa-4222-8222-222222222222';
const _policyId = '33333333-aaaa-4333-8333-333333333333';
const _sessionId = '44444444-aaaa-4444-8444-444444444444';

void main() {
  group('sync entity contract', () {
    test('parses an already-absent delete tombstone with null body', () {
      final result = SyncPushResponse.fromJson({
        'results': [
          {
            'operation_id': '77777777-aaaa-4777-8777-777777777777',
            'status': 'applied',
            'snapshot': {
              'entity_type': 'task',
              'entity_id': _taskId,
              'version': 0,
              'body': null,
              'deleted': true,
              'updated_at': '2026-09-19T08:00:00Z',
              'cursor': 0,
            },
          },
        ],
        'current_cursor': 0,
      });

      expect(result.results.single.snapshot!.body, isEmpty);
      expect(result.results.single.snapshot!.deleted, isTrue);
    });

    test('never uploads device-local task and focus policy fields', () async {
      final store = MemoryDocumentStore();
      await store.ensureAccount(_userA);
      await store.putDocument(
        'task',
        _taskId,
        _taskBody(rank: 42, tags: const ['private-label']),
        accountId: _userA,
      );
      await store.putDocument(
        'focus_policy',
        _policyId,
        _policyBody(allowedAppIds: const ['com.private.app']),
        accountId: _userA,
      );

      final operations = await store.readPendingOperations(_userA);
      final task = operations.singleWhere(
        (operation) => operation.entityType == SyncEntityType.task,
      );
      final policy = operations.singleWhere(
        (operation) => operation.entityType == SyncEntityType.focusPolicy,
      );

      expect(task.patch, isNot(contains('rank')));
      expect(task.patch, isNot(contains('tags')));
      expect(policy.patch, isNot(contains('allowed_app_ids')));
      expect(task.changedFields, isNot(contains('rank')));
      expect(policy.changedFields, isNot(contains('allowed_app_ids')));
    });

    test('maps device ID and records a valid active pause interval', () async {
      final store = MemoryDocumentStore();
      await store.ensureAccount(_userA);
      final startedAt = DateTime.utc(2026, 9, 19, 8);
      final pausedAt = startedAt.add(const Duration(minutes: 5));
      await store.putDocument(
        'focus_session',
        _sessionId,
        _sessionBody(startedAt: startedAt),
        enqueue: false,
        accountId: _userA,
      );
      await store.putDocument('focus_session', _sessionId, {
        ..._sessionBody(startedAt: startedAt),
        'status': 'paused',
        'pause_started_at': pausedAt.toIso8601String(),
      }, accountId: _userA);
      final operation = (await store.readPendingOperations(_userA)).single;
      final outgoing = SyncEntityContract.cloudPatch(
        operation.entityType,
        operation.patch!,
        deviceId: _device,
      );

      expect(outgoing['started_device_id'], _device);
      expect(outgoing['pause_intervals'], [
        {'started_at': pausedAt.toIso8601String(), 'ended_at': null},
      ]);
    });

    test('orders parent upserts before dependent records', () async {
      final store = MemoryDocumentStore();
      await store.ensureAccount(_userA);
      final now = DateTime.utc(2026, 9, 19, 8);
      await store.putDocument(
        'focus_session',
        _sessionId,
        _sessionBody(startedAt: now),
        accountId: _userA,
      );
      await store.putDocument('task', _taskId, _taskBody(), accountId: _userA);
      await store.putDocument(
        'focus_policy',
        _policyId,
        _policyBody(),
        accountId: _userA,
      );
      await store.putDocument(
        'project',
        _projectId,
        _projectBody(),
        accountId: _userA,
      );

      final operations = await store.readPendingOperations(_userA);
      final types = operations.map((value) => value.entityType).toList();
      expect(
        types.indexOf(SyncEntityType.project),
        lessThan(types.indexOf(SyncEntityType.task)),
      );
      expect(
        types.indexOf(SyncEntityType.focusPolicy),
        lessThan(types.indexOf(SyncEntityType.focusSession)),
      );
      expect(
        types.indexOf(SyncEntityType.task),
        lessThan(types.indexOf(SyncEntityType.focusSession)),
      );
      for (final operation in operations) {
        expect(
          operation.operationId,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
      }
    });

    test(
      'freezes attempted envelopes and keeps their UUID for retries',
      () async {
        final store = MemoryDocumentStore();
        await store.ensureAccount(_userA);
        await store.putDocument(
          'task',
          _taskId,
          _taskBody(title: 'first'),
          accountId: _userA,
        );
        final firstAttempt = (await store.readPendingOperations(_userA)).single;

        await store.putDocument(
          'task',
          _taskId,
          _taskBody(title: 'second'),
          accountId: _userA,
        );
        final retryBatch = await store.readPendingOperations(_userA);
        final retried = retryBatch.singleWhere(
          (operation) => operation.operationId == firstAttempt.operationId,
        );
        final newer = retryBatch.singleWhere(
          (operation) => operation.operationId != firstAttempt.operationId,
        );

        expect(retryBatch, hasLength(2));
        expect(retried.patch!['title'], 'first');
        expect(newer.patch!['title'], 'second');
      },
    );
  });

  group('account workspaces', () {
    test('claims local data once without moving global preferences', () async {
      final store = MemoryDocumentStore();
      final repository = WorkspaceRepository(store);
      await repository.load();
      await store.putDocument('project', _projectId, _projectBody());
      await repository.writeGlobalSetting('theme_preference', 'dark');
      await repository.writeSetting(
        'focus_app_whitelists_v1',
        '{"__inbox__":["com.private.app"]}',
      );

      final accountA = await repository.selectAccount(
        claimLocalData: true,
        userId: _userA,
        deviceId: _device,
      );
      expect(accountA.projects.map((value) => value.id), contains(_projectId));
      expect(
        await repository.readSetting('focus_app_whitelists_v1'),
        contains('com.private.app'),
      );
      expect(await repository.readGlobalSetting('theme_preference'), 'dark');

      final local = await repository.selectLocalAccount();
      expect(local.projects, isEmpty);
      expect(await repository.readSetting('focus_app_whitelists_v1'), isNull);
      expect(await repository.readGlobalSetting('theme_preference'), 'dark');

      final accountB = await repository.selectAccount(
        userId: _userB,
        deviceId: _device,
        claimLocalData: false,
      );
      expect(accountB.projects, isEmpty);
      final restoredA = await repository.selectAccount(
        userId: _userA,
        deviceId: _device,
      );
      expect(restoredA.projects.map((value) => value.id), contains(_projectId));
    });
  });

  group('snapshot and rejection persistence', () {
    test(
      'preserves local-only fields while applying snapshot and tombstone',
      () async {
        final store = MemoryDocumentStore();
        await store.ensureAccount(_userA);
        await store.putDocument(
          'task',
          _taskId,
          _taskBody(rank: 70, tags: const ['local']),
          enqueue: false,
          accountId: _userA,
        );
        await store.applyPullResponse(
          _userA,
          expectedCursor: 0,
          response: SyncPullResponse(
            changes: [
              _change(
                cursor: 1,
                type: SyncEntityType.task,
                entityId: _taskId,
                body: _taskBody(title: 'server', includeLocalFields: false),
              ),
            ],
            nextCursor: 1,
            currentCursor: 2,
            hasMore: true,
          ),
        );
        final updated = (await store.readDocuments(
          'task',
          accountId: _userA,
        )).single;
        expect(updated.body['title'], 'server');
        expect(updated.body['rank'], 70);
        expect(updated.body['tags'], ['local']);
        expect(await store.readSyncCursor(_userA), 1);

        await store.applyPullResponse(
          _userA,
          expectedCursor: 1,
          response: SyncPullResponse(
            changes: [
              _change(
                cursor: 2,
                type: SyncEntityType.task,
                entityId: _taskId,
                body: _taskBody(title: 'server', includeLocalFields: false),
                action: SyncAction.delete,
                version: 2,
              ),
            ],
            nextCursor: 2,
            currentCursor: 2,
            hasMore: false,
          ),
        );
        expect(await store.readDocuments('task', accountId: _userA), isEmpty);
        expect(await store.readSyncCursor(_userA), 2);
      },
    );

    test(
      'a corrected edit supersedes rejection without replaying stale patch',
      () async {
        final store = MemoryDocumentStore();
        await store.ensureAccount(_userA);
        await store.putDocument(
          'task',
          _taskId,
          _taskBody(projectId: _projectId),
          accountId: _userA,
        );
        final rejected = (await store.readPendingOperations(_userA)).single;
        await store.applyPushResults(_userA, [
          SyncOperationResult(
            operationId: rejected.operationId,
            status: SyncOperationStatus.rejected,
            error: const SyncError(
              code: 'validation_error',
              message: 'project_id is invalid',
            ),
          ),
        ]);
        expect(await store.pendingOperationCount(accountId: _userA), 1);
        expect(await store.readRejectedOperations(_userA), hasLength(1));

        await store.putDocument(
          'task',
          _taskId,
          _taskBody(projectId: null),
          accountId: _userA,
        );
        final corrected = (await store.readPendingOperations(_userA)).single;
        await store.applyPushResults(_userA, [
          SyncOperationResult(
            operationId: corrected.operationId,
            status: SyncOperationStatus.applied,
            snapshot: SyncSnapshot(
              entityType: SyncEntityType.task,
              entityId: _taskId,
              version: 1,
              body: _taskBody(projectId: null, includeLocalFields: false),
              deleted: false,
              updatedAt: DateTime.utc(2026, 9, 19, 9),
              cursor: 1,
            ),
          ),
        ]);

        final document = (await store.readDocuments(
          'task',
          accountId: _userA,
        )).single;
        expect(document.body['project_id'], isNull);
        expect(await store.pendingOperationCount(accountId: _userA), 0);
        expect(await store.readRejectedOperations(_userA), isEmpty);
      },
    );

    test('invalid pull page does not advance memory-store cursor', () async {
      final store = MemoryDocumentStore();
      await store.ensureAccount(_userA);
      await expectLater(
        store.applyPullResponse(
          _userA,
          expectedCursor: 0,
          response: SyncPullResponse(
            changes: [
              _change(
                cursor: 2,
                type: SyncEntityType.project,
                entityId: _projectId,
                body: _projectBody(),
              ),
            ],
            nextCursor: 1,
            currentCursor: 1,
            hasMore: false,
          ),
        ),
        throwsFormatException,
      );
      expect(await store.readSyncCursor(_userA), 0);
      expect(await store.readDocuments('project', accountId: _userA), isEmpty);
    });
  });

  group('sync runner', () {
    test('coalesces concurrent runs and follows has_more pages', () async {
      final store = MemoryDocumentStore();
      final repository = WorkspaceRepository(store);
      await repository.selectAccount(
        userId: _userA,
        deviceId: _device,
        claimLocalData: false,
      );
      final gate = Completer<void>();
      final api = _FakeSyncApi(
        pushGate: gate,
        pullPages: [
          SyncPullResponse(
            changes: [
              _change(
                cursor: 10,
                type: SyncEntityType.project,
                entityId: _projectId,
                body: _projectBody(name: 'one'),
              ),
            ],
            nextCursor: 10,
            currentCursor: 11,
            hasMore: true,
          ),
          SyncPullResponse(
            changes: [
              _change(
                cursor: 11,
                type: SyncEntityType.project,
                entityId: '55555555-aaaa-4555-8555-555555555555',
                body: _projectBody(name: 'two'),
              ),
            ],
            nextCursor: 11,
            currentCursor: 11,
            hasMore: false,
          ),
        ],
      );

      final first = repository.syncNow(api);
      final second = repository.syncNow(api);
      expect(identical(first, second), isTrue);
      gate.complete();
      final result = await first;

      expect(api.pushCalls, 1);
      expect(api.pullCursors, [0, 10]);
      expect(result.cursor, 11);
      expect(result.pulledChanges, 2);
      expect(result.workspace.projects, hasLength(2));
      expect(result.rejections, isEmpty);
    });
  });
}

Map<String, Object?> _projectBody({String name = 'project'}) => {
  'name': name,
  'color': '#123456',
  'archived': false,
  'sort_order': 10,
};

Map<String, Object?> _taskBody({
  String title = 'task',
  String? projectId,
  double rank = 10,
  List<String> tags = const [],
  bool includeLocalFields = true,
}) => {
  'title': title,
  'note': null,
  'project_id': projectId,
  'priority': 'none',
  'due_at': null,
  'estimated_duration_seconds': null,
  'status': 'open',
  'completed_at': null,
  'recurrence_rule_id': null,
  if (includeLocalFields) 'rank': rank,
  if (includeLocalFields) 'tags': tags,
};

Map<String, Object?> _policyBody({List<String> allowedAppIds = const []}) => {
  'name': 'policy',
  'mode': 'normal',
  'allow_pause': true,
  'early_exit_mode': 'allow',
  'early_exit_wait_seconds': null,
  'max_app_exits': null,
  'allowed_app_ids': allowedAppIds,
  'emergency_app_categories': const ['phone'],
  'notification_mode': 'vibrate',
};

Map<String, Object?> _sessionBody({required DateTime startedAt}) => {
  'task_id': _taskId,
  'plan_block_id': null,
  'focus_policy_id': _policyId,
  'planned_duration_seconds': 1500,
  'started_at': startedAt.toIso8601String(),
  'ended_at': null,
  'pause_started_at': null,
  'pause_intervals': const <Object?>[],
  'paused_duration_seconds': 0,
  'actual_duration_seconds': 0,
  'started_device_id': 'android-local',
  'status': 'running',
  'termination_reason': null,
  'time_zone': 'Asia/Shanghai',
  'app_exit_count': 0,
  'interruption_count': 0,
};

SyncChange _change({
  required int cursor,
  required SyncEntityType type,
  required String entityId,
  required Map<String, Object?> body,
  SyncAction action = SyncAction.upsert,
  int version = 1,
}) => SyncChange(
  cursor: cursor,
  changeId: '99999999-aaaa-4999-8999-${cursor.toString().padLeft(12, '0')}',
  entityType: type,
  entityId: entityId,
  action: action,
  version: version,
  body: body,
  changedFields: body.keys.toList(),
  deviceId: _device,
  changedAt: DateTime.utc(2026, 9, 19, 10).add(Duration(seconds: cursor)),
);

class _FakeSyncApi implements SyncApi {
  _FakeSyncApi({this.pushGate, required this.pullPages});

  final Completer<void>? pushGate;
  final List<SyncPullResponse> pullPages;
  int pushCalls = 0;
  int _pullIndex = 0;
  int _serverCursor = 0;
  final List<int> pullCursors = [];

  @override
  Future<SyncPushResponse> pushChanges(List<SyncOperation> operations) async {
    pushCalls++;
    if (pushGate != null && !pushGate!.isCompleted) await pushGate!.future;
    final results = <SyncOperationResult>[];
    for (final operation in operations) {
      _serverCursor++;
      results.add(
        SyncOperationResult(
          operationId: operation.operationId,
          status: SyncOperationStatus.applied,
          snapshot: SyncSnapshot(
            entityType: operation.entityType,
            entityId: operation.entityId,
            version: operation.baseVersion + 1,
            body: operation.patch ?? const {},
            deleted: operation.action == SyncAction.delete,
            updatedAt: DateTime.utc(2026, 9, 19, 9),
            cursor: _serverCursor,
          ),
        ),
      );
    }
    return SyncPushResponse(results: results, currentCursor: _serverCursor);
  }

  @override
  Future<SyncPullResponse> pullChanges({
    required int cursor,
    int limit = 500,
  }) async {
    pullCursors.add(cursor);
    if (_pullIndex < pullPages.length) return pullPages[_pullIndex++];
    return SyncPullResponse(
      changes: const [],
      nextCursor: _serverCursor,
      currentCursor: _serverCursor,
      hasMore: false,
    );
  }
}
