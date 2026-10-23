import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/domain_models.dart';
import '../sync/sync_models.dart';
import '../../data/platform/focus_platform_gateway.dart';
import '../../data/platform/task_reminder_platform_gateway.dart';
import '../../data/remote/api_client.dart';
import '../../data/repositories/workspace_repository.dart';
import 'private_vault_controller.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.focusPlatform,
    this.taskReminderPlatform = const TaskReminderPlatformGateway(),
    this.apiClient,
    this.syncInterval = const Duration(minutes: 1),
  }) {
    privateVault = PrivateVaultController(
      store: repository.store,
      canStartFocus: () =>
          !focusSessions.any((session) => session.isActive) &&
          !_ordinaryFocusStarting &&
          !isSwitchingSyncAccount,
      onFocusRuntimeChanged: _restorePrivateFocusRuntime,
    );
    privateVault.addListener(notifyListeners);
    addListener(_onTaskReminderDataChanged);
  }

  final WorkspaceRepository repository;
  final FocusPlatformGateway focusPlatform;
  final TaskReminderPlatformGateway taskReminderPlatform;
  final ApiClient? apiClient;
  final Duration syncInterval;
  late final PrivateVaultController privateVault;
  Timer? _focusTicker;
  Future<void> _focusMutation = Future<void>.value();
  bool _ordinaryFocusStarting = false;
  Stopwatch? _earlyExitClock;
  String? _earlyExitSessionId;
  Timer? _syncTimer;
  Timer? _syncDebounce;
  String? _syncAccountId;
  String? _syncDeviceId;
  int _accountGeneration = 0;
  bool _automaticSyncPaused = false;
  bool _automaticSyncPausedForAuthentication = false;
  Future<void> _taskReminderMutation = Future<void>.value();
  (bool, int, String, bool, String)? _taskReminderSnapshot;
  int _taskReminderGeneration = 0;
  bool _disposed = false;

  static const inboxWhitelistKey = '__inbox__';
  static const _appWhitelistsSettingKey = 'focus_app_whitelists_v1';

  bool isReady = false;
  Object? initializationError;
  ThemePreference themePreference = ThemePreference.system;
  bool useDynamicColor = false;
  bool notificationsEnabled = true;
  bool focusVibrationEnabled = true;
  String? focusPlatformErrorMessage;
  bool taskRemindersEnabled = true;
  bool scheduledTaskRemindersEnabled = true;
  bool taskReminderNotificationsAllowed = false;
  bool scheduledTaskReminderNotificationsAllowed = false;
  String? taskReminderErrorMessage;
  int taskReminderOpenSequence = 0;
  bool usageAccessGranted = false;
  bool overlayPermissionGranted = false;
  bool installedApplicationsLoading = false;
  Object? installedApplicationsError;
  List<InstalledApplication> installedApplications = const [];
  Map<String, Set<String>> _appWhitelists = {};
  static const _ownedFocusSettingKey = 'focus_owned_sessions_v1';
  Map<String, String> _ownedFocusSessions = {};
  SyncPhase _syncPhase = SyncPhase.localOnly;
  int pendingOperations = 0;
  DateTime? lastSuccessfulSyncAt;
  String? syncErrorMessage;
  List<RejectedSyncOperation> syncRejections = const [];
  bool isSwitchingSyncAccount = false;
  Object? accountConnectionError;

  List<ProjectItem> projects = [];
  List<TaskItem> tasks = [];
  List<PlanBlockItem> planBlocks = [];
  List<FocusPolicyItem> focusPolicies = [];
  List<FocusSessionItem> focusSessions = [];

  List<DeviceItem> devices = const [];

  SyncPhase get syncPhase => _syncPhase;

  bool get canSync =>
      apiClient != null &&
      _syncAccountId != null &&
      _syncDeviceId != null &&
      !isSwitchingSyncAccount &&
      accountConnectionError == null;

  String get syncStatusTitle => switch (_syncPhase) {
    SyncPhase.localOnly => '未连接同步账户',
    SyncPhase.synced => '同步完成',
    SyncPhase.pending => pendingOperations == 0 ? '等待首次同步' : '本地更改等待同步',
    SyncPhase.syncing => '正在同步',
    SyncPhase.offline => '无法连接服务器',
    SyncPhase.attention => '同步异常',
  };

  String get syncStatusDescription => switch (_syncPhase) {
    SyncPhase.localOnly =>
      pendingOperations == 0
          ? '数据仅保存在本机，尚未连接同步账户'
          : '$pendingOperations 项本地更改仅保存在此设备',
    SyncPhase.synced => '当前更改已同步到服务器',
    SyncPhase.pending =>
      pendingOperations == 0
          ? '已连接账户，等待首次同步'
          : '$pendingOperations 项更改已保存在本机，等待发送到服务器',
    SyncPhase.syncing => '正在同步本机与服务器的更改',
    SyncPhase.offline =>
      pendingOperations == 0
          ? '暂时无法连接服务器，本机功能仍可使用'
          : '$pendingOperations 项更改保存在本机，服务器恢复后可继续同步',
    SyncPhase.attention => syncErrorMessage ?? '同步失败，请查看错误信息',
  };

  Future<void> initialize() async {
    try {
      final snapshot = await repository.restoreSelectedWorkspace();
      final owned = await repository.readGlobalSetting(_ownedFocusSettingKey);
      _ownedFocusSessions = owned == null
          ? {}
          : Map<String, String>.from(jsonDecode(owned) as Map);
      await _applyWorkspaceSnapshot(snapshot);
      _syncPhase = SyncPhase.localOnly;
      final savedTheme = await repository.readGlobalSetting('theme_preference');
      if (savedTheme != null) {
        themePreference = ThemePreference.values.byName(savedTheme);
      }
      useDynamicColor =
          await repository.readGlobalSetting('use_dynamic_color') == 'true';
      notificationsEnabled =
          await repository.readGlobalSetting('notifications_enabled') !=
          'false';
      focusVibrationEnabled =
          await repository.readGlobalSetting('focus_vibration_enabled') !=
          'false';
      taskRemindersEnabled =
          await repository.readGlobalSetting('task_reminders_enabled') !=
          'false';
      scheduledTaskRemindersEnabled =
          await repository.readGlobalSetting(
            'scheduled_task_reminders_enabled',
          ) !=
          'false';
      _appWhitelists = _decodeAppWhitelists(
        await repository.readSetting(_appWhitelistsSettingKey),
      );
      try {
        usageAccessGranted = await focusPlatform.hasUsageAccess();
      } catch (_) {
        usageAccessGranted = false;
      }
      try {
        overlayPermissionGranted = await focusPlatform.hasOverlayPermission();
      } catch (_) {
        overlayPermissionGranted = false;
      }
      await _restoreNativeFocus();
    } catch (error) {
      initializationError = error;
    } finally {
      isReady = true;
      notifyListeners();
    }
  }

  Future<void> retryInitialization() async {
    isReady = false;
    initializationError = null;
    notifyListeners();
    await initialize();
  }

  FocusSessionItem? get activeFocusSession {
    for (final session in focusSessions) {
      if (session.isActive && isLocalFocusSession(session)) return session;
    }
    return null;
  }

  bool get canStartFocus =>
      !privateVault.hasActiveFocus &&
      !privateVault.isBusy &&
      !focusSessions.any(
        (session) =>
            session.isActive &&
            (isLocalFocusSession(session) ||
                !repository.selectedAccountId.startsWith('__local__:')),
      );

  FocusSessionItem? get lastCompletedFocus {
    for (final session in focusSessions) {
      if (!session.isActive) return session;
    }
    return null;
  }

  bool isLocalFocusSession(FocusSessionItem session) =>
      _ownedFocusSessions[repository.selectedAccountId] == session.id ||
      (_syncDeviceId != null && session.startedDeviceId == _syncDeviceId) ||
      // Older offline sessions existed only in the original local workspace.
      (repository.selectedAccountId == '__local__' &&
          session.startedDeviceId == 'android-local');

  int get activeFocusElapsedSeconds {
    final session = activeFocusSession;
    if (session == null) return 0;
    final end = session.status == FocusSessionStatus.paused
        ? session.pauseStartedAt ?? DateTime.now()
        : DateTime.now();
    return math.max(
      0,
      end.difference(session.startedAt).inSeconds -
          session.pausedDurationSeconds,
    );
  }

  int get activeFocusRemainingSeconds {
    final session = activeFocusSession;
    if (session == null) return 0;
    return math.max(
      0,
      session.plannedDurationSeconds - activeFocusElapsedSeconds,
    );
  }

  TaskItem? taskById(String? id) {
    if (id == null) return null;
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  ProjectItem? projectById(String? id) {
    if (id == null) return null;
    for (final project in projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  FocusPolicyItem? policyById(String? id) {
    if (id == null) return null;
    for (final policy in focusPolicies) {
      if (policy.id == id) return policy;
    }
    return null;
  }

  bool get guardPermissionsGranted =>
      usageAccessGranted && overlayPermissionGranted;

  String whitelistName(String? projectId) {
    return projectById(projectId)?.name ?? '收集箱';
  }

  Set<String> appWhitelistForProject(String? projectId) {
    final key = projectId ?? inboxWhitelistKey;
    return Set.unmodifiable(_appWhitelists[key] ?? const <String>{});
  }

  Set<String> appWhitelistForTask(TaskItem task) {
    return appWhitelistForProject(task.projectId);
  }

  List<TaskItem> tasksForDate(DateTime date) {
    final plannedIds = planBlocks
        .where(
          (block) =>
              _sameDate(block.startsAt, date) &&
              block.status == PlanBlockStatus.scheduled,
        )
        .map((block) => block.taskId)
        .whereType<String>()
        .toSet();
    final result = tasks
        .where((task) {
          if (plannedIds.contains(task.id)) return true;
          return task.dueAt != null && _sameDate(task.dueAt!, date);
        })
        .toList(growable: false);
    result.sort((a, b) {
      final aBlock = firstPlanForTask(a.id, date);
      final bBlock = firstPlanForTask(b.id, date);
      if (aBlock == null && bBlock == null) return a.rank.compareTo(b.rank);
      if (aBlock == null) return 1;
      if (bBlock == null) return -1;
      return aBlock.startsAt.compareTo(bBlock.startsAt);
    });
    return result;
  }

  PlanBlockItem? firstPlanForTask(String taskId, DateTime date) {
    for (final block in planBlocks) {
      if (block.taskId == taskId && _sameDate(block.startsAt, date)) {
        return block;
      }
    }
    return null;
  }

  int actualSecondsForTask(String taskId, {DateTime? date}) {
    return focusSessions
        .where(
          (session) =>
              session.taskId == taskId &&
              (date == null || _sameDate(session.startedAt, date)),
        )
        .fold(0, (sum, session) => sum + session.actualDurationSeconds);
  }

  Future<ProjectItem> createProject({
    required String name,
    required String color,
  }) async {
    final project = ProjectItem(
      id: repository.createId(),
      name: name.trim(),
      color: color,
      sortOrder: projects.isEmpty
          ? 10
          : projects.map((item) => item.sortOrder).reduce(math.max) + 10,
    );
    await repository.saveProject(project);
    projects = [...projects, project]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    notifyListeners();
    await _markPending();
    return project;
  }

  Future<void> updateProject(ProjectItem project) async {
    await repository.saveProject(project);
    projects = [
      for (final current in projects)
        if (current.id == project.id) project else current,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    notifyListeners();
    await _markPending();
  }

  Future<TaskItem> createTask({
    required String title,
    String? note,
    String? projectId,
    TaskPriority priority = TaskPriority.none,
    DateTime? dueAt,
    int? estimatedDurationSeconds,
    List<String> tags = const [],
  }) async {
    final task = TaskItem(
      id: repository.createId(),
      title: title.trim(),
      note: note == null || note.trim().isEmpty ? null : note.trim(),
      projectId: projectId,
      priority: priority,
      dueAt: dueAt,
      estimatedDurationSeconds: estimatedDurationSeconds,
      status: TaskStatus.open,
      rank: tasks.isEmpty
          ? 10
          : tasks.map((item) => item.rank).reduce(math.max) + 10,
      tags: tags,
    );
    await repository.saveTask(task);
    tasks = [...tasks, task]..sort(TaskItem.compareByPriority);
    notifyListeners();
    await _markPending();
    return task;
  }

  Future<void> updateTask(TaskItem task) async {
    await repository.saveTask(task);
    tasks = [
      for (final current in tasks)
        if (current.id == task.id) task else current,
    ]..sort(TaskItem.compareByPriority);
    notifyListeners();
    await _markPending();
  }

  Future<void> toggleTask(TaskItem task) {
    final completed = !task.isCompleted;
    return updateTask(
      task.copyWith(
        status: completed ? TaskStatus.completed : TaskStatus.open,
        completedAt: completed ? DateTime.now() : null,
        clearCompletedAt: !completed,
      ),
    );
  }

  Future<void> reorderToday(DateTime date, int oldIndex, int newIndex) async {
    final visible = tasksForDate(date);
    await reorderTasks(visible, oldIndex, newIndex);
  }

  Future<void> reorderTasks(
    List<TaskItem> visible,
    int oldIndex,
    int newIndex,
  ) async {
    visible = [...visible];
    final moved = visible.removeAt(oldIndex);
    visible.insert(newIndex, moved);
    final updates = {
      for (var index = 0; index < visible.length; index++)
        visible[index].id: visible[index].copyWith(rank: (index + 1) * 10),
    };
    await repository.saveTasks(updates.values.toList(growable: false));
    tasks = [for (final task in tasks) updates[task.id] ?? task]
      ..sort(TaskItem.compareByPriority);
    notifyListeners();
    await _markPending();
  }

  Future<PlanBlockItem> scheduleTask({
    String? taskId,
    String? title,
    required DateTime startsAt,
    required Duration duration,
  }) async {
    final accountId = repository.selectedAccountId;
    _validatePlanBlock(taskId: taskId, title: title, duration: duration);
    final block = PlanBlockItem(
      id: repository.createId(),
      taskId: taskId,
      title: taskId == null ? title!.trim() : null,
      startsAt: startsAt,
      endsAt: startsAt.add(duration),
      timeZone: 'Asia/Shanghai',
      status: PlanBlockStatus.scheduled,
    );
    await repository.savePlanBlock(block);
    if (repository.selectedAccountId != accountId) return block;
    planBlocks = [...planBlocks, block]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    notifyListeners();
    await _markPending();
    return block;
  }

  Future<PlanBlockItem> updatePlanBlock({
    required PlanBlockItem block,
    String? taskId,
    String? title,
    required DateTime startsAt,
    required Duration duration,
  }) async {
    final accountId = repository.selectedAccountId;
    if (!planBlocks.any((current) => current.id == block.id)) {
      throw StateError('当前工作区中没有这个计划时段。');
    }
    _validatePlanBlock(taskId: taskId, title: title, duration: duration);
    final updated = PlanBlockItem(
      id: block.id,
      taskId: taskId,
      title: taskId == null ? title!.trim() : null,
      startsAt: startsAt,
      endsAt: startsAt.add(duration),
      timeZone: block.timeZone,
      status: block.status,
      originalPlanBlockId: block.originalPlanBlockId,
    );
    await repository.savePlanBlock(updated);
    if (repository.selectedAccountId != accountId) return updated;
    planBlocks = [
      for (final current in planBlocks)
        if (current.id == block.id) updated else current,
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    notifyListeners();
    await _markPending();
    return updated;
  }

  Future<void> deletePlanBlock(PlanBlockItem block) async {
    final accountId = repository.selectedAccountId;
    if (!planBlocks.any((current) => current.id == block.id)) return;
    await repository.deletePlanBlock(block.id);
    if (repository.selectedAccountId != accountId) return;
    planBlocks = planBlocks.where((current) => current.id != block.id).toList();
    notifyListeners();
    await _markPending();
  }

  void _validatePlanBlock({
    required String? taskId,
    required String? title,
    required Duration duration,
  }) {
    if (duration.inSeconds <= 0) {
      throw ArgumentError('计划时长必须大于零。');
    }
    if (taskId != null && taskById(taskId) == null) {
      throw StateError('当前工作区中没有关联任务。');
    }
    if (taskId == null && (title == null || title.trim().isEmpty)) {
      throw ArgumentError('未关联任务的计划必须填写标题。');
    }
  }

  Future<T> _serializeFocus<T>(Future<T> Function() action) async {
    final previous = _focusMutation;
    final completed = Completer<void>();
    _focusMutation = completed.future;
    await previous;
    try {
      return await action();
    } finally {
      completed.complete();
    }
  }

  Future<void> startFocus({
    required TaskItem task,
    required int durationSeconds,
    required FocusPolicyItem policy,
  }) => _serializeFocus(() async {
    if (!canStartFocus) return;
    _ordinaryFocusStarting = true;
    try {
      await _startFocus(
        task: task,
        durationSeconds: durationSeconds,
        policy: policy,
      );
    } finally {
      _ordinaryFocusStarting = false;
    }
  });

  Future<void> _startFocus({
    required TaskItem task,
    required int durationSeconds,
    required FocusPolicyItem policy,
  }) async {
    if (!canStartFocus) return;
    if (durationSeconds <= 0 || durationSeconds > 24 * 60 * 60) {
      throw ArgumentError('专注时长须大于零且不超过 24 小时。');
    }
    final storedPolicy = policyById(policy.id);
    if (storedPolicy == null || taskById(task.id)?.status != TaskStatus.open) {
      throw StateError('任务或专注规则已变化，请重新选择。');
    }
    policy = storedPolicy;
    if (policy.mode != FocusPolicyMode.normal && !guardPermissionsGranted) {
      throw StateError('请先授予使用情况访问和显示在其他应用上层权限。');
    }
    cancelEarlyFocusExit();
    final now = DateTime.now();
    final session = FocusSessionItem(
      id: repository.createId(),
      taskId: task.id,
      focusPolicyId: policy.id,
      plannedDurationSeconds: durationSeconds,
      startedAt: now,
      startedDeviceId: _syncDeviceId ?? repository.createId(),
      status: FocusSessionStatus.running,
      timeZone: 'Asia/Shanghai',
    );
    final owned = {
      ..._ownedFocusSessions,
      repository.selectedAccountId: session.id,
    };
    // Ownership is excluded from portable backups. A failed session write may
    // leave an unused ID here, but cannot create a live timer.
    await repository.writeGlobalSetting(
      _ownedFocusSettingKey,
      jsonEncode(owned),
    );
    await repository.saveFocusSession(session);
    _ownedFocusSessions = owned;
    focusSessions = [session, ...focusSessions];
    _startTicker();
    notifyListeners();
    await _markPending();
    await _restoreNativeFocus();
  }

  Future<void> pauseFocus() => _serializeFocus(_pauseFocus);

  Future<void> _pauseFocus() async {
    final session = activeFocusSession;
    if (session == null || session.status != FocusSessionStatus.running) return;
    final policy = policyById(session.focusPolicyId);
    if (policy?.allowPause == false || policy?.mode == FocusPolicyMode.strict) {
      throw StateError('当前专注规则不允许暂停。');
    }
    final updated = session.copyWith(
      status: FocusSessionStatus.paused,
      pauseStartedAt: DateTime.now(),
    );
    await _replaceFocusSession(updated);
    try {
      await focusPlatform.pauseTimer();
    } catch (_) {}
  }

  Future<void> resumeFocus() => _serializeFocus(_resumeFocus);

  Future<void> _resumeFocus() async {
    final session = activeFocusSession;
    if (session == null || session.status != FocusSessionStatus.paused) return;
    final now = DateTime.now();
    final pausedFor = now.difference(session.pauseStartedAt ?? now).inSeconds;
    final updated = session.copyWith(
      status: FocusSessionStatus.running,
      pausedDurationSeconds: session.pausedDurationSeconds + pausedFor,
      clearPauseStartedAt: true,
    );
    await _replaceFocusSession(updated);
    try {
      await focusPlatform.resumeTimer(
        now.add(Duration(seconds: activeFocusRemainingSeconds)),
      );
    } catch (_) {}
  }

  Future<FocusSessionItem?> finishFocus({
    FocusSessionStatus status = FocusSessionStatus.completed,
    String? reason,
  }) => _serializeFocus(() => _finishFocus(status: status, reason: reason));

  int get earlyExitRemainingSeconds {
    final session = activeFocusSession;
    if (session == null) return 0;
    final policy = policyById(session.focusPolicyId);
    if (policy?.earlyExitMode != 'countdown' &&
        policy?.mode != FocusPolicyMode.strict) {
      return 0;
    }
    final wait = policy?.mode == FocusPolicyMode.strict
        ? math.max(30, policy?.earlyExitWaitSeconds ?? 30)
        : math.max(0, policy?.earlyExitWaitSeconds ?? 0);
    if (_earlyExitSessionId != session.id || _earlyExitClock == null) {
      return wait;
    }
    return math.max(0, wait - _earlyExitClock!.elapsed.inSeconds);
  }

  void beginEarlyFocusExit() {
    final session = activeFocusSession;
    if (session == null || _earlyExitSessionId == session.id) return;
    _earlyExitSessionId = session.id;
    _earlyExitClock = Stopwatch()..start();
  }

  void cancelEarlyFocusExit() {
    _earlyExitClock?.stop();
    _earlyExitClock = null;
    _earlyExitSessionId = null;
  }

  Future<FocusSessionItem?> _finishFocus({
    FocusSessionStatus status = FocusSessionStatus.completed,
    String? reason,
  }) async {
    final session = activeFocusSession;
    if (session == null) return null;
    if (status != FocusSessionStatus.completed &&
        status != FocusSessionStatus.abandoned) {
      throw ArgumentError('只能完成专注或提前结束专注。');
    }
    final policy = policyById(session.focusPolicyId);
    if (status == FocusSessionStatus.completed &&
        policy?.mode == FocusPolicyMode.strict &&
        activeFocusRemainingSeconds > 0) {
      throw StateError('严格模式须达到目标时间后才能完成。紧急情况可选择提前结束。');
    }
    if (status == FocusSessionStatus.abandoned) {
      if (earlyExitRemainingSeconds > 0) {
        throw StateError('请在结束确认中等待倒计时完成。');
      }
      if ((policy?.mode == FocusPolicyMode.strict ||
              policy?.earlyExitMode == 'reason') &&
          (reason?.trim().isEmpty ?? true)) {
        throw StateError('当前专注规则提前结束须填写原因。');
      }
    }
    final actual = activeFocusElapsedSeconds;
    var appExitCount = session.appExitCount;
    var interruptionCount = session.interruptionCount;
    if (policy?.mode != FocusPolicyMode.normal) {
      try {
        final stats = await focusPlatform.getGuardActivityStats();
        if (stats.sessionId == session.id) {
          appExitCount = math.max(appExitCount, stats.appExitCount);
          interruptionCount = math.max(
            interruptionCount,
            stats.interruptionCount,
          );
        }
      } catch (_) {}
    }
    final updated = session.copyWith(
      status: status,
      endedAt: DateTime.now(),
      actualDurationSeconds: actual,
      terminationReason: reason,
      appExitCount: appExitCount,
      interruptionCount: interruptionCount,
      clearPauseStartedAt: true,
    );
    await _replaceFocusSession(updated);
    cancelEarlyFocusExit();
    _focusTicker?.cancel();
    try {
      await focusPlatform.stopTimer();
      focusPlatformErrorMessage = null;
    } catch (_) {
      focusPlatformErrorMessage = '专注已保存，但系统计时服务未停止。请在设置中重试。';
    }
    notifyListeners();
    try {
      await focusPlatform.feedback(
        status == FocusSessionStatus.completed ? 'completed' : 'abandoned',
      );
    } catch (_) {}
    return updated;
  }

  Future<void> refreshGuardActivityStats() =>
      _serializeFocus(_refreshGuardActivityStats);

  Future<void> _refreshGuardActivityStats() async {
    final session = activeFocusSession;
    if (session == null || session.status != FocusSessionStatus.running) return;
    final policy = policyById(session.focusPolicyId);
    if (policy == null ||
        policy.mode == FocusPolicyMode.normal ||
        !usageAccessGranted) {
      return;
    }
    GuardActivityStats stats;
    try {
      stats = await focusPlatform.getGuardActivityStats();
    } catch (_) {
      return;
    }
    if (stats.sessionId != session.id) return;
    final exits = math.max(session.appExitCount, stats.appExitCount);
    final interruptions = math.max(
      session.interruptionCount,
      stats.interruptionCount,
    );
    if (exits == session.appExitCount &&
        interruptions == session.interruptionCount) {
      return;
    }
    try {
      await _replaceFocusSession(
        session.copyWith(appExitCount: exits, interruptionCount: interruptions),
      );
    } catch (error) {
      debugPrint('Saving guard activity stats failed: $error');
    }
  }

  Future<void> _replaceFocusSession(FocusSessionItem updated) async {
    await repository.saveFocusSession(updated);
    focusSessions = [
      for (final session in focusSessions)
        if (session.id == updated.id) updated else session,
    ];
    notifyListeners();
    await _markPending();
  }

  Future<void> reconcileNativeFocus() => _serializeFocus(() async {
    await _restoreNativeFocus();
    if (!_disposed) notifyListeners();
  });

  Future<void> _restoreNativeFocus() async {
    final session = activeFocusSession;
    if (session == null) {
      final privateRuntime = privateVault.activeFocusRuntime;
      if (privateRuntime != null || privateVault.timerWarning != null) {
        await privateVault.retryNativeFocus();
        focusPlatformErrorMessage = privateVault.timerWarning;
        return;
      }
      try {
        final state = await focusPlatform.getTimerState();
        if (state.isActive) await focusPlatform.stopTimer();
        focusPlatformErrorMessage = null;
      } catch (error) {
        focusPlatformErrorMessage = '系统计时服务状态未更新，可在设置中重试。';
        debugPrint('Reconciling the local focus service failed: $error');
      }
      return;
    }
    final task = taskById(session.taskId);
    final policy = policyById(session.focusPolicyId);
    if (policy == null) return;
    try {
      await focusPlatform.configureFeedback(
        enabled: focusVibrationEnabled,
        notificationMode: policy.notificationMode,
      );
    } catch (_) {}
    try {
      if (_ownedFocusSessions[repository.selectedAccountId] != session.id) {
        final owned = {
          ..._ownedFocusSessions,
          repository.selectedAccountId: session.id,
        };
        await repository.writeGlobalSetting(
          _ownedFocusSettingKey,
          jsonEncode(owned),
        );
        _ownedFocusSessions = owned;
      }
      await focusPlatform.startTimer(
        sessionId: session.id,
        title: task?.title ?? '自由专注',
        endsAt: DateTime.now().add(
          Duration(seconds: activeFocusRemainingSeconds),
        ),
        mode: policy.mode,
        paused: session.status == FocusSessionStatus.paused,
        appExitCount: session.appExitCount,
        interruptionCount: session.interruptionCount,
        allowedPackageNames: {
          ...policy.allowedAppIds,
          ...appWhitelistForProject(task?.projectId),
        }.toList(growable: false),
        taskTypeName: whitelistName(task?.projectId),
        maxAppExits: policy.maxAppExits,
      );
      focusPlatformErrorMessage = null;
    } catch (error) {
      focusPlatformErrorMessage = '系统计时通知未更新，可在设置中重试；应用内计时仍可使用。';
      debugPrint('Restoring the local focus service failed: $error');
    }
  }

  Future<void> _restorePrivateFocusRuntime(PrivateFocusRuntime? runtime) async {
    if (runtime == null) {
      if (activeFocusSession == null) await focusPlatform.stopTimer();
    } else {
      await focusPlatform.configureFeedback(
        enabled: focusVibrationEnabled,
        notificationMode: 'vibrate',
      );
      await focusPlatform.startTimer(
        sessionId: runtime.sessionId,
        title: '私密任务',
        taskTypeName: '私密任务',
        endsAt: runtime.endsAt,
        mode: FocusPolicyMode.normal,
      );
    }
  }

  void _startTicker() {
    _focusTicker?.cancel();
    _focusTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (activeFocusSession == null) {
        _focusTicker?.cancel();
        return;
      }
      notifyListeners();
    });
  }

  List<DailyStatItem> statisticsForLastDays(int dayCount) {
    final today = DateTime.now();
    return List.generate(dayCount, (index) {
      final date = DateTime(
        today.year,
        today.month,
        today.day - (dayCount - index - 1),
      );
      final planned = planBlocks
          .where((block) => _sameDate(block.startsAt, date))
          .fold(0, (sum, block) => sum + block.durationSeconds);
      final actual = focusSessions
          .where((session) => _sameDate(session.startedAt, date))
          .fold(0, (sum, session) => sum + session.actualDurationSeconds);
      final completed = tasks
          .where(
            (task) =>
                task.completedAt != null && _sameDate(task.completedAt!, date),
          )
          .length;
      return DailyStatItem(
        date: date,
        plannedDurationSeconds: planned,
        actualDurationSeconds: actual,
        completedTasks: completed,
      );
    });
  }

  Future<void> setThemePreference(ThemePreference preference) async {
    await repository.writeGlobalSetting('theme_preference', preference.name);
    themePreference = preference;
    notifyListeners();
  }

  Future<void> setDynamicColor(bool value) async {
    await repository.writeGlobalSetting('use_dynamic_color', value.toString());
    useDynamicColor = value;
    notifyListeners();
  }

  Future<void> setFocusVibration(bool value) async {
    await repository.writeGlobalSetting('focus_vibration_enabled', '$value');
    focusVibrationEnabled = value;
    notifyListeners();
    try {
      await focusPlatform.configureFeedback(
        enabled: value,
        notificationMode:
            policyById(activeFocusSession?.focusPolicyId)?.notificationMode ??
            'vibrate',
      );
    } catch (_) {}
  }

  Future<void> setNotifications(bool value) async {
    await repository.writeGlobalSetting(
      'notifications_enabled',
      value.toString(),
    );
    notificationsEnabled = value;
    notifyListeners();
    if (value) {
      try {
        await focusPlatform.requestNotificationPermission();
      } catch (_) {}
    }
  }

  Future<void> setTaskRemindersEnabled(bool value) async {
    await repository.writeGlobalSetting('task_reminders_enabled', '$value');
    taskRemindersEnabled = value;
    notifyListeners();
    await refreshTaskReminders(requestPermission: value, automatic: false);
  }

  Future<void> setScheduledTaskRemindersEnabled(bool value) async {
    await repository.writeGlobalSetting(
      'scheduled_task_reminders_enabled',
      '$value',
    );
    scheduledTaskRemindersEnabled = value;
    notifyListeners();
    await refreshTaskReminders(requestPermission: value, automatic: false);
  }

  void _onTaskReminderDataChanged() {
    if (_disposed || !taskReminderPlatform.isSupported) return;
    final snapshot = _currentTaskReminderSnapshot();
    if (snapshot == _taskReminderSnapshot) return;
    unawaited(refreshTaskReminders(requestPermission: true));
  }

  (bool, int, String, bool, String) _currentTaskReminderSnapshot() {
    final usable =
        isReady &&
        initializationError == null &&
        !isSwitchingSyncAccount &&
        accountConnectionError == null;
    return (
      taskRemindersEnabled && usable,
      usable ? tasks.where((task) => task.status == TaskStatus.open).length : 0,
      repository.selectedAccountId,
      scheduledTaskRemindersEnabled && usable,
      jsonEncode(usable ? _scheduledTaskReminders() : const []),
    );
  }

  List<Map<String, Object>> _scheduledTaskReminders() {
    final openTasks = {
      for (final task in tasks)
        if (task.status == TaskStatus.open) task.id: task,
    };
    final reminders = <Map<String, Object>>[
      for (final task in openTasks.values)
        if (task.dueAt != null)
          {
            'id': 'due:${task.id}',
            'atMillis': task.dueAt!.millisecondsSinceEpoch,
            'kind': 'deadline',
          },
      for (final block in planBlocks)
        if (block.status == PlanBlockStatus.scheduled &&
            (block.taskId == null || openTasks.containsKey(block.taskId)))
          {
            'id': 'plan:${block.id}',
            'atMillis': block.startsAt.millisecondsSinceEpoch,
            'kind': 'plan',
          },
    ];
    reminders.sort((a, b) {
      final byTime = (a['atMillis']! as int).compareTo(b['atMillis']! as int);
      return byTime != 0
          ? byTime
          : (a['id']! as String).compareTo(b['id']! as String);
    });
    return reminders;
  }

  Future<void> refreshTaskReminders({
    bool requestPermission = false,
    bool automatic = true,
  }) {
    if (_disposed || !taskReminderPlatform.isSupported) {
      return Future<void>.value();
    }
    final snapshot = _currentTaskReminderSnapshot();
    final previous = _taskReminderSnapshot;
    _taskReminderSnapshot = snapshot;
    if (!isReady ||
        isSwitchingSyncAccount ||
        accountConnectionError != null ||
        initializationError != null ||
        (previous != null && previous.$3 != snapshot.$3)) {
      // A permission dialog can keep an older update future pending. Clear the
      // native snapshot immediately instead of waiting behind that dialog.
      unawaited(
        taskReminderPlatform.clearWorkspace().catchError((Object _) {}),
      );
    }
    final generation = ++_taskReminderGeneration;
    _taskReminderMutation = _taskReminderMutation.then((_) async {
      if (_disposed || generation != _taskReminderGeneration) return;
      try {
        final allowed = await taskReminderPlatform.update(
          enabled: snapshot.$1,
          openTaskCount: snapshot.$2,
          workspaceId: snapshot.$3,
          requestPermission:
              requestPermission &&
              (!automatic || (snapshot.$1 && snapshot.$2 > 0)),
          automatic: automatic,
        );
        if (_disposed || generation != _taskReminderGeneration) return;
        final scheduledAllowed = await taskReminderPlatform.updateSchedule(
          enabled: snapshot.$4,
          workspaceId: snapshot.$3,
          reminders: (jsonDecode(snapshot.$5) as List)
              .map((item) => Map<String, Object>.from(item as Map))
              .toList(growable: false),
          requestPermission:
              requestPermission &&
              (!automatic || (snapshot.$4 && snapshot.$5 != '[]')),
          automatic: automatic,
        );
        if (_disposed || generation != _taskReminderGeneration) return;
        taskReminderNotificationsAllowed = allowed;
        scheduledTaskReminderNotificationsAllowed = scheduledAllowed;
        taskReminderErrorMessage = null;
      } catch (_) {
        if (_disposed || generation != _taskReminderGeneration) return;
        taskReminderErrorMessage = '任务提醒更新失败，可重试；本地任务仍可使用。';
      }
      notifyListeners();
    });
    return _taskReminderMutation;
  }

  Future<bool> takeTaskReminderOpenRequest() async {
    if (_disposed || !taskReminderPlatform.isSupported) return false;
    try {
      final requested = await taskReminderPlatform.takeOpenTasksRequest();
      if (!requested || _disposed) return false;
      taskReminderOpenSequence++;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> refreshGuardPermissions() async {
    try {
      usageAccessGranted = await focusPlatform.hasUsageAccess();
    } catch (_) {
      usageAccessGranted = false;
    }
    try {
      overlayPermissionGranted = await focusPlatform.hasOverlayPermission();
    } catch (_) {
      overlayPermissionGranted = false;
    }
    notifyListeners();
  }

  Future<void> refreshUsageAccess() => refreshGuardPermissions();

  Future<void> openUsageAccessSettings() async {
    try {
      await focusPlatform.openUsageAccessSettings();
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await refreshGuardPermissions();
    }
  }

  Future<void> openOverlayPermissionSettings() async {
    try {
      await focusPlatform.openOverlayPermissionSettings();
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await refreshGuardPermissions();
    }
  }

  Future<void> loadInstalledApplications({bool force = false}) async {
    if (installedApplicationsLoading) return;
    if (!force && installedApplications.isNotEmpty) return;
    installedApplicationsLoading = true;
    installedApplicationsError = null;
    notifyListeners();
    try {
      installedApplications = await focusPlatform.getInstalledApplications();
    } catch (error) {
      installedApplicationsError = error;
    } finally {
      installedApplicationsLoading = false;
      notifyListeners();
    }
  }

  Future<void> setAppWhitelist(
    String? projectId,
    Set<String> packageNames,
  ) async {
    final key = projectId ?? inboxWhitelistKey;
    final updated = {
      ..._appWhitelists,
      key: Set<String>.unmodifiable(packageNames),
    };
    final payload = {
      for (final entry in updated.entries)
        entry.key: entry.value.toList(growable: false)..sort(),
    };
    await repository.writeSetting(
      _appWhitelistsSettingKey,
      jsonEncode(payload),
    );
    _appWhitelists = updated;
    notifyListeners();
  }

  Future<void> _markPending() async {
    try {
      pendingOperations = await repository.pendingOperationCount();
    } catch (error) {
      // The document and its outbox are already committed. A secondary count
      // failure must not make the editor retry a successfully persisted create.
      debugPrint('Reading the pending operation count failed: $error');
      if (_syncAccountId != null) _scheduleSync();
      return;
    }
    if (_syncPhase != SyncPhase.syncing &&
        (_syncAccountId != null ||
            _syncPhase == SyncPhase.synced ||
            _syncPhase == SyncPhase.pending)) {
      _syncPhase = pendingOperations > 0 ? SyncPhase.pending : SyncPhase.synced;
    }
    notifyListeners();
    if (_syncAccountId != null) _scheduleSync();
  }

  void markSyncStarted() {
    _syncPhase = SyncPhase.syncing;
    notifyListeners();
  }

  Future<void> connectSyncAccount({
    bool offline = false,
    String? userId,
    String? deviceId,
    String? uploadSourceWorkspace,
  }) async {
    // Keep the state-only form for controller/widget tests that do not attach
    // a real API. Production always supplies the authenticated identities.
    if (userId == null || deviceId == null) {
      _syncPhase = offline
          ? SyncPhase.offline
          : lastSuccessfulSyncAt != null
          ? (pendingOperations > 0 ? SyncPhase.pending : SyncPhase.synced)
          : SyncPhase.pending;
      notifyListeners();
      return;
    }

    if (_syncAccountId == userId &&
        _syncDeviceId == deviceId &&
        !isSwitchingSyncAccount &&
        accountConnectionError == null) {
      if (offline) {
        _syncPhase = SyncPhase.offline;
        notifyListeners();
      } else {
        final generation = _accountGeneration;
        // Requests sent with an old token can complete after token rotation.
        // Resume only after that request has reported its authentication error.
        await repository.waitForSyncIdle();
        if (generation != _accountGeneration ||
            _syncAccountId != userId ||
            _syncDeviceId != deviceId ||
            isSwitchingSyncAccount ||
            accountConnectionError != null) {
          return;
        }
        if (_automaticSyncPausedForAuthentication) {
          _automaticSyncPaused = false;
          _automaticSyncPausedForAuthentication = false;
        }
        _startSyncTimer();
        unawaited(syncNow(automatic: true));
      }
      return;
    }

    final previousAccountId = _syncAccountId;
    if (activeFocusSession != null && repository.selectedAccountId != userId) {
      syncErrorMessage = '请先结束当前专注，再切换同步工作区。';
      _syncPhase = SyncPhase.attention;
      notifyListeners();
      return;
    }
    final generation = ++_accountGeneration;
    _syncTimer?.cancel();
    _syncDebounce?.cancel();
    _syncAccountId = userId;
    _syncDeviceId = deviceId;
    _automaticSyncPaused = false;
    _automaticSyncPausedForAuthentication = false;
    isSwitchingSyncAccount = true;
    accountConnectionError = null;
    syncErrorMessage = null;
    syncRejections = const [];
    if (previousAccountId != userId) {
      lastSuccessfulSyncAt = null;
      devices = const [];
    }
    notifyListeners();

    try {
      if (uploadSourceWorkspace != null && uploadSourceWorkspace != userId) {
        await repository.store.copyWorkspace(
          uploadSourceWorkspace,
          userId,
          enqueueForSync: true,
        );
      }
      final snapshot = await repository.selectAccount(
        userId: userId,
        deviceId: deviceId,
      );
      if (generation != _accountGeneration || _syncAccountId != userId) return;
      await _applyWorkspaceSnapshot(snapshot);
      _appWhitelists = _decodeAppWhitelists(
        await repository.readSetting(_appWhitelistsSettingKey),
      );
      if (generation != _accountGeneration || _syncAccountId != userId) return;
      isSwitchingSyncAccount = false;
      _syncPhase = offline ? SyncPhase.offline : SyncPhase.pending;
      await _restoreNativeFocus();
      _startSyncTimer();
      notifyListeners();
      if (!offline) unawaited(syncNow());
    } catch (error, stackTrace) {
      debugPrint('Selecting the sync account failed: $error\n$stackTrace');
      if (generation != _accountGeneration || _syncAccountId != userId) return;
      isSwitchingSyncAccount = false;
      accountConnectionError = error;
      syncErrorMessage = '无法打开此账户的本地工作区。';
      _syncPhase = SyncPhase.attention;
      notifyListeners();
    }
  }

  Future<void> retrySyncAccountConnection() async {
    final userId = _syncAccountId;
    final deviceId = _syncDeviceId;
    if (userId == null || deviceId == null) return;
    await connectSyncAccount(userId: userId, deviceId: deviceId);
  }

  Future<void> syncNow({bool automatic = false}) async {
    if (automatic && _automaticSyncPaused) return;
    final resumeAutomaticSync = !automatic && _automaticSyncPaused;
    if (!automatic) {
      _automaticSyncPaused = false;
      _automaticSyncPausedForAuthentication = false;
    }
    final api = apiClient;
    final accountId = _syncAccountId;
    final deviceId = _syncDeviceId;
    if (api == null ||
        accountId == null ||
        deviceId == null ||
        isSwitchingSyncAccount ||
        accountConnectionError != null) {
      return;
    }
    if (resumeAutomaticSync) _startSyncTimer();
    final generation = _accountGeneration;
    _syncPhase = SyncPhase.syncing;
    syncErrorMessage = null;
    notifyListeners();
    try {
      final result = await repository.syncNow(api);
      if (generation != _accountGeneration ||
          accountId != _syncAccountId ||
          result.accountId != accountId) {
        return;
      }
      await _applyWorkspaceSnapshot(result.workspace);
      syncRejections = List.unmodifiable(result.rejections);
      lastSuccessfulSyncAt = DateTime.now();
      if (result.needsAttention) {
        syncErrorMessage = result.rejections.first.error.message;
        _syncPhase = SyncPhase.attention;
      } else {
        _syncPhase = pendingOperations > 0
            ? SyncPhase.pending
            : SyncPhase.synced;
      }
      notifyListeners();
      await _refreshDevices(api, deviceId, generation);
      if (!result.needsAttention && pendingOperations > 0) _scheduleSync();
    } on ApiNetworkException catch (error) {
      if (generation != _accountGeneration || accountId != _syncAccountId) {
        return;
      }
      syncErrorMessage = error.message;
      _syncPhase = SyncPhase.offline;
      notifyListeners();
    } on ApiException catch (error) {
      if (generation != _accountGeneration || accountId != _syncAccountId) {
        return;
      }
      syncErrorMessage = error.message;
      if (error.statusCode == 426 ||
          error.code == 'client_update_required' ||
          error.code == 'unsupported_protocol') {
        _pauseAutomaticSync();
      } else if (error.statusCode == 401) {
        _pauseAutomaticSync(authentication: error.code != 'invalid_response');
      }
      _syncPhase = error.statusCode == null || error.statusCode! >= 500
          ? SyncPhase.offline
          : SyncPhase.attention;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('Account sync failed: $error\n$stackTrace');
      if (generation != _accountGeneration || accountId != _syncAccountId) {
        return;
      }
      syncErrorMessage = error is FormatException
          ? '服务器返回了无法识别的同步数据。'
          : '同步未完成，请稍后重试。';
      _syncPhase = SyncPhase.attention;
      _pauseAutomaticSync();
      notifyListeners();
    }
  }

  Future<void> markSyncCompleted({
    required List<DeviceItem> serverDevices,
    DateTime? completedAt,
  }) async {
    pendingOperations = await repository.pendingOperationCount();
    devices = List.unmodifiable(serverDevices);
    lastSuccessfulSyncAt = completedAt ?? DateTime.now();
    syncErrorMessage = null;
    syncRejections = const [];
    _syncPhase = pendingOperations > 0 ? SyncPhase.pending : SyncPhase.synced;
    notifyListeners();
  }

  void markOffline() {
    if (_syncPhase == SyncPhase.localOnly) return;
    _syncPhase = SyncPhase.offline;
    notifyListeners();
  }

  void markSyncAttention() {
    if (_syncPhase == SyncPhase.localOnly) return;
    _syncPhase = SyncPhase.attention;
    notifyListeners();
  }

  Future<bool> revokeDevice(String deviceId) async {
    final api = apiClient;
    if (api == null || _syncAccountId == null) return false;
    try {
      await api.delete('/v1/devices/${Uri.encodeComponent(deviceId)}');
      devices = devices.where((device) => device.id != deviceId).toList();
      notifyListeners();
      return true;
    } on ApiNetworkException catch (error) {
      syncErrorMessage = error.message;
      _syncPhase = SyncPhase.offline;
    } on ApiException catch (error) {
      syncErrorMessage = error.message;
      _syncPhase = SyncPhase.attention;
    }
    notifyListeners();
    return false;
  }

  Future<void> disconnectSyncAccount() async {
    ++_accountGeneration;
    _syncTimer?.cancel();
    _syncDebounce?.cancel();
    _syncAccountId = null;
    _syncDeviceId = null;
    isSwitchingSyncAccount = false;
    accountConnectionError = null;
    _syncPhase = SyncPhase.localOnly;
    lastSuccessfulSyncAt = null;
    syncErrorMessage = null;
    syncRejections = const [];
    devices = const [];
    notifyListeners();
    await repository.waitForSyncIdle();
    repository.pauseSync();
  }

  Future<void> openOfflineWorkspace(String id) async {
    if (activeFocusSession != null) {
      throw StateError('请先结束当前专注，再切换工作区。');
    }
    await disconnectSyncAccount();
    await _applyWorkspaceSnapshot(await repository.openOfflineWorkspace(id));
    _appWhitelists = _decodeAppWhitelists(
      await repository.readSetting(_appWhitelistsSettingKey),
    );
    final theme = await repository.readSetting('theme_preference');
    for (final preference in ThemePreference.values) {
      if (preference.name == theme) {
        await repository.writeGlobalSetting('theme_preference', theme!);
        themePreference = preference;
      }
    }
    final dynamic = await repository.readSetting('use_dynamic_color');
    if (dynamic == 'true' || dynamic == 'false') {
      await repository.writeGlobalSetting('use_dynamic_color', dynamic!);
      useDynamicColor = dynamic == 'true';
    }
    final notifications = await repository.readSetting('notifications_enabled');
    if (notifications == 'true' || notifications == 'false') {
      await repository.writeGlobalSetting(
        'notifications_enabled',
        notifications!,
      );
      notificationsEnabled = notifications == 'true';
    }
    await _restoreNativeFocus();
    notifyListeners();
  }

  Future<void> refreshAfterPrivateTransfer() async {
    final accountId = repository.selectedAccountId;
    final snapshot = await repository.load();
    if (accountId != repository.selectedAccountId) {
      throw StateError('工作区已切换，请重新打开私密任务箱。');
    }
    await _applyWorkspaceSnapshot(snapshot);
    notifyListeners();
    await refreshTaskReminders();
  }

  Future<void> _applyWorkspaceSnapshot(WorkspaceSnapshot snapshot) async {
    await privateVault.selectWorkspace(repository.selectedAccountId);
    final previousFocusId = activeFocusSession?.id;
    projects = snapshot.projects;
    tasks = snapshot.tasks;
    planBlocks = snapshot.planBlocks;
    focusPolicies = snapshot.focusPolicies;
    focusSessions = snapshot.focusSessions;
    if (previousFocusId != activeFocusSession?.id) cancelEarlyFocusExit();
    pendingOperations = snapshot.pendingOperations;
    if (activeFocusSession != null) {
      _startTicker();
    } else {
      _focusTicker?.cancel();
    }
  }

  Future<void> _refreshDevices(
    ApiClient api,
    String currentDeviceId,
    int generation,
  ) async {
    try {
      final response = await api.get('/v1/devices');
      final values = response['devices'];
      if (values is! List) {
        throw const FormatException('Missing devices array.');
      }
      final loaded = <DeviceItem>[];
      for (final value in values) {
        if (value is! Map) throw const FormatException('Invalid device.');
        final device = value.map((key, item) => MapEntry(key.toString(), item));
        if (device['revoked_at'] != null) continue;
        final id = device['id'];
        final name = device['name'];
        final platform = device['platform'];
        final lastSeenAt = device['last_seen_at'];
        if (id is! String ||
            name is! String ||
            platform is! String ||
            lastSeenAt is! String) {
          throw const FormatException('Invalid device fields.');
        }
        final parsedLastSeenAt = DateTime.tryParse(lastSeenAt);
        if (parsedLastSeenAt == null) {
          throw const FormatException('Invalid device timestamp.');
        }
        loaded.add(
          DeviceItem(
            id: id,
            name: name,
            platform: platform,
            lastSeenAt: parsedLastSeenAt.toLocal(),
            isCurrent: id == currentDeviceId,
          ),
        );
      }
      if (generation != _accountGeneration) return;
      devices = List.unmodifiable(loaded);
      notifyListeners();
    } catch (error, stackTrace) {
      // Device inventory is supplementary; a successful data exchange remains
      // successful when this secondary request is temporarily unavailable.
      debugPrint('Loading account devices failed: $error\n$stackTrace');
    }
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    if (_automaticSyncPaused) return;
    if (_syncAccountId == null || apiClient == null) return;
    _syncTimer = Timer.periodic(
      syncInterval,
      (_) => unawaited(syncNow(automatic: true)),
    );
  }

  void _scheduleSync() {
    if (_automaticSyncPaused) return;
    if (_syncAccountId == null || apiClient == null) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(
      const Duration(milliseconds: 800),
      () => unawaited(syncNow(automatic: true)),
    );
  }

  void _pauseAutomaticSync({bool authentication = false}) {
    _automaticSyncPaused = true;
    _automaticSyncPausedForAuthentication = authentication;
    _syncTimer?.cancel();
    _syncDebounce?.cancel();
  }

  Map<String, Set<String>> _decodeAppWhitelists(String? value) {
    if (value == null || value.isEmpty) return {};
    try {
      final decoded = jsonDecode(value) as Map<String, Object?>;
      return {
        for (final entry in decoded.entries)
          entry.key: (entry.value as List<Object?>).whereType<String>().toSet(),
      };
    } catch (_) {
      return {};
    }
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  void dispose() {
    privateVault.removeListener(notifyListeners);
    privateVault.dispose();
    cancelEarlyFocusExit();
    _disposed = true;
    _taskReminderGeneration++;
    removeListener(_onTaskReminderDataChanged);
    _focusTicker?.cancel();
    _syncTimer?.cancel();
    _syncDebounce?.cancel();
    super.dispose();
  }
}
