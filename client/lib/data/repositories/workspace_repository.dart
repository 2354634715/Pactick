import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../core/models/default_focus_policies.dart';
import '../../core/models/domain_models.dart';
import '../../core/sync/sync_entity_contract.dart';
import '../../core/sync/sync_models.dart';
import '../local/local_database.dart';
import '../local/workspace_backup.dart';
import '../remote/api_client.dart';

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.projects,
    required this.tasks,
    required this.planBlocks,
    required this.focusPolicies,
    required this.focusSessions,
    required this.pendingOperations,
  });

  final List<ProjectItem> projects;
  final List<TaskItem> tasks;
  final List<PlanBlockItem> planBlocks;
  final List<FocusPolicyItem> focusPolicies;
  final List<FocusSessionItem> focusSessions;
  final int pendingOperations;
}

class SyncRunResult {
  const SyncRunResult({
    required this.accountId,
    required this.pushedOperations,
    required this.appliedOperations,
    required this.pulledChanges,
    required this.cursor,
    required this.rejections,
    required this.workspace,
  });

  final String accountId;
  final int pushedOperations;
  final int appliedOperations;
  final int pulledChanges;
  final int cursor;
  final List<RejectedSyncOperation> rejections;
  final WorkspaceSnapshot workspace;

  bool get needsAttention => rejections.isNotEmpty;
}

class _SyncContext {
  const _SyncContext(this.accountId, this.deviceId);

  final String accountId;
  final String deviceId;
}

class WorkspaceRepository {
  WorkspaceRepository(this._store);

  final DocumentStore _store;
  String _accountId = DocumentStore.localAccountId;
  String? _deviceId;
  Future<SyncRunResult>? _activeSync;
  String? _activeSyncAccountId;
  static const _uuid = Uuid();
  static const _legacySampleMigrationKey = 'legacy_sample_content_removed_v1';
  static const _legacySampleProjectIds = {
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
  };
  static const _legacySampleTaskIds = {
    '31111111-1111-4111-8111-111111111111',
    '32222222-2222-4222-8222-222222222222',
    '33333333-3333-4333-8333-333333333333',
    '34444444-4444-4444-8444-444444444444',
    '35555555-5555-4555-8555-555555555555',
  };
  static const _legacySamplePlanBlockIds = {
    '41111111-1111-4111-8111-111111111111',
    '42222222-2222-4222-8222-222222222222',
    '43333333-3333-4333-8333-333333333333',
  };
  static const _legacySampleFocusSessionIds = {
    '61111111-1111-4111-8111-111111111111',
    '62111111-1111-4111-8111-111111111111',
    '63111111-1111-4111-8111-111111111111',
    '64111111-1111-4111-8111-111111111111',
    '65111111-1111-4111-8111-111111111111',
    '66111111-1111-4111-8111-111111111111',
  };

  String get selectedAccountId => _accountId;
  DocumentStore get store => _store;
  WorkspaceBackupService get backups => WorkspaceBackupService(_store);

  bool get hasSyncAccount => _deviceId != null;

  Future<void> waitForSyncIdle() async {
    try {
      await _activeSync;
    } catch (_) {
      /* The original caller reports errors. */
    }
  }

  void pauseSync() {
    _deviceId = null;
  }

  Future<WorkspaceSnapshot> openOfflineWorkspace(String id) async {
    await _store.ensureAccount(id);
    _accountId = id;
    _deviceId = null;
    await writeGlobalSetting('selected_workspace_v2', id);
    return _load(id);
  }

  Future<WorkspaceSnapshot> restoreSelectedWorkspace() async {
    final selected = await readGlobalSetting('selected_workspace_v2');
    if (selected != null) return openOfflineWorkspace(selected);
    // Upgrade keeps the existing account data visible without contacting its server.
    final existing = await _store.listWorkspaceIds();
    final legacy = existing.where((id) => id != DocumentStore.localAccountId);
    return openOfflineWorkspace(
      legacy.isEmpty ? DocumentStore.localAccountId : legacy.first,
    );
  }

  Future<WorkspaceSnapshot> selectAccount({
    required String userId,
    required String deviceId,
    bool claimLocalData = false,
  }) async {
    if (userId.trim().isEmpty || deviceId.trim().isEmpty) {
      throw ArgumentError('A user ID and device ID are required.');
    }
    await _store.ensureAccount(userId, claimLocalData: claimLocalData);
    _accountId = userId;
    _deviceId = deviceId;
    await writeGlobalSetting('selected_workspace_v2', userId);
    await _load(userId);
    // This also queues legacy/default version-zero policies before any focus
    // session that references them is sent.
    await _store.prepareUnsyncedDocuments(userId);
    return _load(userId);
  }

  Future<WorkspaceSnapshot> selectLocalAccount() async {
    await _store.ensureAccount(DocumentStore.localAccountId);
    _accountId = DocumentStore.localAccountId;
    _deviceId = null;
    return _load(DocumentStore.localAccountId);
  }

  Future<WorkspaceSnapshot> load() => _load(_accountId);

  Future<WorkspaceSnapshot> _load(String accountId) async {
    await _removeLegacySampleContent(accountId);
    var focusPolicies = await _readFocusPolicies(accountId);
    await _ensureDefaultFocusPolicies(accountId, focusPolicies);
    focusPolicies = await _readFocusPolicies(accountId);

    return WorkspaceSnapshot(
      projects: await _readProjects(accountId),
      tasks: await _readTasks(accountId),
      planBlocks: await _readPlanBlocks(accountId),
      focusPolicies: focusPolicies,
      focusSessions: await _readFocusSessions(accountId),
      pendingOperations: await _store.pendingOperationCount(
        accountId: accountId,
      ),
    );
  }

  Future<void> saveTask(TaskItem task) {
    return _store.putDocument(
      'task',
      task.id,
      task.toBody(),
      accountId: _accountId,
    );
  }

  Future<void> saveProject(ProjectItem project) {
    return _store.putDocument(
      'project',
      project.id,
      project.toBody(),
      accountId: _accountId,
    );
  }

  Future<void> saveTasks(List<TaskItem> tasks) {
    return _store.putDocuments([
      for (final task in tasks)
        StoredDocument(
          entityType: 'task',
          id: task.id,
          body: task.toBody(),
          version: 0,
          updatedAt: DateTime.now(),
        ),
    ], accountId: _accountId);
  }

  Future<void> savePlanBlock(PlanBlockItem block) {
    return _store.putDocument(
      'plan_block',
      block.id,
      block.toBody(),
      accountId: _accountId,
    );
  }

  Future<void> saveFocusSession(FocusSessionItem session) {
    return _store.putDocument(
      'focus_session',
      session.id,
      session.toBody(),
      accountId: _accountId,
    );
  }

  Future<void> deleteTask(String id) =>
      _store.deleteDocument('task', id, accountId: _accountId);

  Future<int> pendingOperationCount() =>
      _store.pendingOperationCount(accountId: _accountId);

  Future<String?> readSetting(String key) =>
      _store.readSetting(key, accountId: _accountId);

  Future<void> writeSetting(String key, String value) {
    return _store.writeSetting(key, value, accountId: _accountId);
  }

  /// Device-wide preferences (theme, dynamic color and notifications) stay
  /// outside account workspaces so signing out does not reset the app shell.
  Future<String?> readGlobalSetting(String key) {
    return _store.readSetting(key, accountId: DocumentStore.localAccountId);
  }

  Future<void> writeGlobalSetting(String key, String value) {
    return _store.writeSetting(
      key,
      value,
      accountId: DocumentStore.localAccountId,
    );
  }

  Future<List<RejectedSyncOperation>> readRejectedOperations() {
    return _store.readRejectedOperations(_accountId);
  }

  Future<SyncRunResult> syncNow(
    SyncApi api, {
    int pushBatchSize = 200,
    int pullPageSize = 500,
  }) {
    final deviceId = _deviceId;
    if (!hasSyncAccount || deviceId == null) {
      return Future.error(
        StateError('Select an authenticated account before syncing.'),
      );
    }
    final context = _SyncContext(_accountId, deviceId);
    final active = _activeSync;
    if (active != null) {
      if (_activeSyncAccountId == context.accountId) return active;
      return active.then(
        (_) => _startSync(
          context,
          api,
          pushBatchSize: pushBatchSize,
          pullPageSize: pullPageSize,
        ),
        onError: (Object _, StackTrace _) => _startSync(
          context,
          api,
          pushBatchSize: pushBatchSize,
          pullPageSize: pullPageSize,
        ),
      );
    }
    return _startSync(
      context,
      api,
      pushBatchSize: pushBatchSize,
      pullPageSize: pullPageSize,
    );
  }

  Future<SyncRunResult> _startSync(
    _SyncContext context,
    SyncApi api, {
    required int pushBatchSize,
    required int pullPageSize,
  }) {
    late final Future<SyncRunResult> future;
    future = _runSync(
      context,
      api,
      pushBatchSize: pushBatchSize,
      pullPageSize: pullPageSize,
    );
    _activeSync = future;
    _activeSyncAccountId = context.accountId;
    unawaited(
      future.then<void>(
        (_) => _clearActiveSync(future),
        onError: (Object _, StackTrace _) => _clearActiveSync(future),
      ),
    );
    return future;
  }

  void _clearActiveSync(Future<SyncRunResult> future) {
    if (!identical(_activeSync, future)) return;
    _activeSync = null;
    _activeSyncAccountId = null;
  }

  Future<SyncRunResult> _runSync(
    _SyncContext context,
    SyncApi api, {
    required int pushBatchSize,
    required int pullPageSize,
  }) async {
    var pushed = 0;
    var applied = 0;
    var pulled = 0;

    while (true) {
      final storedOperations = await _store.readPendingOperations(
        context.accountId,
        limit: pushBatchSize,
      );
      if (storedOperations.isEmpty) break;
      final outgoing = storedOperations
          .map((operation) {
            if (operation.action == SyncAction.delete) return operation;
            final patch = SyncEntityContract.cloudPatch(
              operation.entityType,
              operation.patch ?? const {},
              deviceId: context.deviceId,
            );
            return operation.copyWith(
              changedFields: patch.keys.toList()..sort(),
              patch: patch,
            );
          })
          .toList(growable: false);
      final response = await api.pushChanges(outgoing);
      _validatePushResponse(outgoing, response);
      await _store.applyPushResults(context.accountId, response.results);
      pushed += outgoing.length;
      applied += response.results
          .where((result) => result.status == SyncOperationStatus.applied)
          .length;
    }

    final policySnapshots = <String, SyncSnapshot>{};
    var cursor = await _store.readSyncCursor(context.accountId);
    while (true) {
      final response = await api.pullChanges(
        cursor: cursor,
        limit: pullPageSize,
      );
      await _store.applyPullResponse(
        context.accountId,
        expectedCursor: cursor,
        response: response,
      );
      pulled += response.changes.length;
      for (final change in response.changes) {
        if (change.entityType == SyncEntityType.focusPolicy &&
            defaultFocusPolicies.any(
              (policy) => policy.id == change.entityId,
            )) {
          policySnapshots[change.entityId] = change.toSnapshot();
        }
      }
      cursor = response.nextCursor;
      if (!response.hasMore) break;
    }

    var rejections = await _store.readRejectedOperations(context.accountId);
    final duplicatePolicyIds = rejections
        .where(
          (value) => isDuplicateDefaultFocusPolicyCreation(
            value.operation,
            value.error.code,
          ),
        )
        .map((value) => value.operation.entityId)
        .toSet();
    if (duplicatePolicyIds.isNotEmpty) {
      // Older clients already advanced past the seed policies while retaining
      // their rejected creates. Read their authoritative history without
      // rewinding the workspace cursor or replaying unrelated documents.
      if (!policySnapshots.keys.toSet().containsAll(duplicatePolicyIds)) {
        policySnapshots.addAll(
          await _readDefaultPolicySnapshots(
            api,
            duplicatePolicyIds,
            pullPageSize,
          ),
        );
      }
      for (final id in duplicatePolicyIds) {
        final snapshot = policySnapshots[id];
        if (snapshot != null) {
          await _store.adoptExistingDefaultFocusPolicy(
            context.accountId,
            snapshot,
          );
        }
      }
      rejections = await _store.readRejectedOperations(context.accountId);
    }
    return SyncRunResult(
      accountId: context.accountId,
      pushedOperations: pushed,
      appliedOperations: applied,
      pulledChanges: pulled,
      cursor: cursor,
      rejections: rejections,
      workspace: await _load(context.accountId),
    );
  }

  Future<Map<String, SyncSnapshot>> _readDefaultPolicySnapshots(
    SyncApi api,
    Set<String> ids,
    int pageSize,
  ) async {
    final snapshots = <String, SyncSnapshot>{};
    var cursor = 0;
    while (true) {
      final response = await api.pullChanges(cursor: cursor, limit: pageSize);
      var previous = cursor;
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
          (response.hasMore && response.nextCursor <= cursor)) {
        throw const FormatException('Pull response has invalid cursor bounds.');
      }
      for (final change in response.changes) {
        if (change.entityType == SyncEntityType.focusPolicy &&
            ids.contains(change.entityId)) {
          snapshots[change.entityId] = change.toSnapshot();
        }
      }
      cursor = response.nextCursor;
      if (!response.hasMore) return snapshots;
    }
  }

  void _validatePushResponse(
    List<SyncOperation> operations,
    SyncPushResponse response,
  ) {
    final expected = operations.map((value) => value.operationId).toSet();
    final actual = response.results.map((value) => value.operationId).toList();
    if (actual.length != expected.length ||
        actual.toSet().length != actual.length ||
        actual.any((operationId) => !expected.contains(operationId))) {
      throw const FormatException(
        'Push response does not match the submitted operation batch.',
      );
    }
  }

  String createId() => _uuid.v4();

  Future<List<ProjectItem>> _readProjects(String accountId) async {
    final documents = await _store.readDocuments(
      'project',
      accountId: accountId,
    );
    return documents
        .map((document) => ProjectItem.fromDocument(document.id, document.body))
        .toList(growable: false)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Future<List<TaskItem>> _readTasks(String accountId) async {
    final documents = await _store.readDocuments('task', accountId: accountId);
    return documents
        .map((document) => TaskItem.fromDocument(document.id, document.body))
        .toList(growable: false)
      ..sort(TaskItem.compareByPriority);
  }

  Future<List<PlanBlockItem>> _readPlanBlocks(String accountId) async {
    final documents = await _store.readDocuments(
      'plan_block',
      accountId: accountId,
    );
    return documents
        .map(
          (document) => PlanBlockItem.fromDocument(document.id, document.body),
        )
        .toList(growable: false)
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  Future<List<FocusPolicyItem>> _readFocusPolicies(String accountId) async {
    final documents = await _store.readDocuments(
      'focus_policy',
      accountId: accountId,
    );
    return documents
        .map(
          (document) =>
              FocusPolicyItem.fromDocument(document.id, document.body),
        )
        .toList(growable: false);
  }

  Future<List<FocusSessionItem>> _readFocusSessions(String accountId) async {
    final documents = await _store.readDocuments(
      'focus_session',
      accountId: accountId,
    );
    return documents
        .map(
          (document) =>
              FocusSessionItem.fromDocument(document.id, document.body),
        )
        .toList(growable: false)
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  Future<void> _removeLegacySampleContent(String accountId) async {
    if (await _store.readSetting(
          _legacySampleMigrationKey,
          accountId: accountId,
        ) ==
        'true') {
      return;
    }

    final taskDocuments = await _store.readDocuments(
      'task',
      accountId: accountId,
    );
    final retainedProjectIds = taskDocuments
        .where((document) => !_legacySampleTaskIds.contains(document.id))
        .map((document) => document.body['project_id'])
        .whereType<String>()
        .toSet();

    for (final document in taskDocuments) {
      if (_legacySampleTaskIds.contains(document.id)) {
        await _store.deleteDocument(
          'task',
          document.id,
          enqueue: false,
          accountId: accountId,
        );
      }
    }

    final planBlockDocuments = await _store.readDocuments(
      'plan_block',
      accountId: accountId,
    );
    for (final document in planBlockDocuments) {
      if (_legacySamplePlanBlockIds.contains(document.id) ||
          _legacySampleTaskIds.contains(document.body['task_id'])) {
        await _store.deleteDocument(
          'plan_block',
          document.id,
          enqueue: false,
          accountId: accountId,
        );
      }
    }

    final focusSessionDocuments = await _store.readDocuments(
      'focus_session',
      accountId: accountId,
    );
    for (final document in focusSessionDocuments) {
      if (_legacySampleFocusSessionIds.contains(document.id) ||
          _legacySampleTaskIds.contains(document.body['task_id'])) {
        await _store.deleteDocument(
          'focus_session',
          document.id,
          enqueue: false,
          accountId: accountId,
        );
      }
    }

    final projectDocuments = await _store.readDocuments(
      'project',
      accountId: accountId,
    );
    for (final document in projectDocuments) {
      if (_legacySampleProjectIds.contains(document.id) &&
          !retainedProjectIds.contains(document.id)) {
        await _store.deleteDocument(
          'project',
          document.id,
          enqueue: false,
          accountId: accountId,
        );
      }
    }

    await _store.writeSetting(
      _legacySampleMigrationKey,
      'true',
      accountId: accountId,
    );
  }

  Future<void> _ensureDefaultFocusPolicies(
    String accountId,
    List<FocusPolicyItem> existingPolicies,
  ) async {
    final existingIds = existingPolicies.map((policy) => policy.id).toSet();
    for (final policy in defaultFocusPolicies) {
      if (existingIds.contains(policy.id)) continue;
      await _store.putDocument(
        'focus_policy',
        policy.id,
        policy.toBody(),
        enqueue: false,
        accountId: accountId,
      );
    }
  }
}
