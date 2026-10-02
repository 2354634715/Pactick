import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a stale native timer is stopped when no owned session remains',
    () async {
      final gateway = _FocusGateway()
        ..nativeState = const FocusTimerState(
          sessionId: 'finished-session',
          isActive: true,
        );
      final controller = _controller(MemoryDocumentStore(), gateway);
      await controller.initialize();
      expect(controller.activeFocusSession, isNull);
      expect(gateway.starts, 0);
      expect(gateway.stops, 1);
      controller.dispose();
    },
  );

  test(
    'restart restores this installation paused timer, whitelist and stats',
    () async {
      final store = MemoryDocumentStore();
      final gateway = _FocusGateway();
      final first = _controller(store, gateway);
      await first.initialize();
      final task = await first.createTask(title: '重启恢复');
      final policy = first.focusPolicies.firstWhere(
        (policy) => policy.mode == FocusPolicyMode.guard,
      );
      await first.setAppWhitelist(null, {'com.example.documents'});
      await first.startFocus(task: task, durationSeconds: 1500, policy: policy);
      final session = first.activeFocusSession!;
      gateway.stats = GuardActivityStats(
        sessionId: session.id,
        appExitCount: 3,
        interruptionCount: 2,
      );
      await first.refreshGuardActivityStats();
      await first.pauseFocus();
      first.dispose();

      final recoveredGateway = _FocusGateway();
      final recovered = _controller(store, recoveredGateway);
      await recovered.initialize();
      expect(recovered.initializationError, isNull);
      expect(recovered.activeFocusSession!.id, session.id);
      expect(recoveredGateway.startedSessionId, session.id);
      expect(recoveredGateway.paused, isTrue);
      expect(recoveredGateway.appExitCount, 3);
      expect(recoveredGateway.interruptionCount, 2);
      expect(recoveredGateway.allowedPackageNames, ['com.example.documents']);
      expect(
        recoveredGateway.endsAt!.difference(DateTime.now()).inSeconds,
        closeTo(1500, 2),
      );
      recovered.dispose();
    },
  );

  test('remote active session is read-only and blocks a new session', () async {
    final store = MemoryDocumentStore();
    final gateway = _FocusGateway();
    final controller = _controller(store, gateway);
    await controller.initialize();
    await controller.connectSyncAccount(
      userId: 'account',
      deviceId: 'device-b',
      offline: true,
    );
    final task = await controller.createTask(title: '其他设备正在专注');
    final session = _session(controller, task, deviceId: 'device-a');
    await store.putDocument(
      'focus_session',
      session.id,
      session.toBody(),
      accountId: 'account',
      enqueue: false,
    );
    await controller.retryInitialization();
    await controller.connectSyncAccount(
      userId: 'account',
      deviceId: 'device-b',
      offline: true,
    );
    final pending = controller.pendingOperations;
    expect(controller.focusSessions.single.isActive, isTrue);
    expect(
      controller.isLocalFocusSession(controller.focusSessions.single),
      isFalse,
    );
    expect(controller.activeFocusSession, isNull);
    expect(controller.canStartFocus, isFalse);
    await controller.pauseFocus();
    await controller.resumeFocus();
    await controller.refreshGuardActivityStats();
    expect(await controller.finishFocus(), isNull);
    await controller.startFocus(
      task: task,
      durationSeconds: 900,
      policy: controller.focusPolicies.first,
    );
    expect(controller.focusSessions.single.status, FocusSessionStatus.running);
    expect(controller.pendingOperations, pending);
    expect(gateway.starts, 0);
    expect(gateway.pauses, 0);
    expect(gateway.resumes, 0);
    expect(gateway.stops, 0);
    expect(gateway.statsReads, 0);
    controller.dispose();
  });

  test(
    'portable restore does not grant ownership of an active session',
    () async {
      final store = MemoryDocumentStore();
      final controller = _controller(store, _FocusGateway());
      await controller.initialize();
      final task = await controller.createTask(title: '备份中的活动会话');
      await controller.startFocus(
        task: task,
        durationSeconds: 1500,
        policy: controller.focusPolicies.first,
      );
      final archive = await store.exportWorkspace(DocumentStore.localAccountId);
      expect(archive.settings, isNot(contains('focus_owned_sessions_v1')));
      final restoredId = await controller.repository.backups.restoreJson(
        archive.encode(),
      );
      await store.writeSetting('selected_workspace_v2', restoredId);
      controller.dispose();
      final gateway = _FocusGateway();
      final recovered = _controller(store, gateway);
      await recovered.initialize();
      expect(recovered.focusSessions.single.isActive, isTrue);
      expect(recovered.activeFocusSession, isNull);
      expect(recovered.canStartFocus, isTrue);
      expect(gateway.starts, 0);
      expect(await recovered.finishFocus(), isNull);
      await recovered.startFocus(
        task: recovered.tasks.single,
        durationSeconds: 900,
        policy: recovered.focusPolicies.first,
      );
      expect(recovered.activeFocusSession, isNotNull);
      expect(
        recovered.activeFocusSession!.id,
        isNot(recovered.focusSessions.last.id),
      );
      recovered.dispose();
    },
  );

  test('authenticated originating device can recover a legacy account session offline later', () async {
    final store = MemoryDocumentStore();
    final controller = _controller(store, _FocusGateway());
    await controller.initialize();
    await controller.connectSyncAccount(
      userId: 'account',
      deviceId: 'device-a',
      offline: true,
    );
    final task = await controller.createTask(title: '原始设备专注');
    final session = _session(controller, task, deviceId: 'device-a');
    await store.putDocument(
      'focus_session',
      session.id,
      session.toBody(),
      accountId: 'account',
      enqueue: false,
    );
    controller.dispose();
    final gateway = _FocusGateway();
    final recovered = _controller(store, gateway);
    await recovered.initialize();
    expect(recovered.activeFocusSession, isNull);
    await recovered.connectSyncAccount(
      userId: 'account',
      deviceId: 'device-a',
      offline: true,
    );
    expect(recovered.activeFocusSession!.id, session.id);
    expect(gateway.startedSessionId, session.id);
    recovered.dispose();
    final offlineGateway = _FocusGateway();
    final offline = _controller(store, offlineGateway);
    await offline.initialize();
    expect(offline.activeFocusSession!.id, session.id);
    expect(offlineGateway.startedSessionId, session.id);
    offline.dispose();
  });

  test(
    'guard counters from a different native session never enter this session',
    () async {
      final gateway = _FocusGateway();
      final controller = _controller(MemoryDocumentStore(), gateway);
      await controller.initialize();
      final task = await controller.createTask(title: '统计隔离');
      await controller.startFocus(
        task: task,
        durationSeconds: 900,
        policy: controller.focusPolicies.firstWhere(
          (policy) => policy.mode == FocusPolicyMode.guard,
        ),
      );
      gateway.stats = const GuardActivityStats(
        sessionId: 'previous-session',
        appExitCount: 90,
        interruptionCount: 40,
      );
      await controller.refreshGuardActivityStats();
      expect(controller.activeFocusSession!.appExitCount, 0);
      final finished = await controller.finishFocus();
      expect(finished!.appExitCount, 0);
      expect(finished.interruptionCount, 0);
      controller.dispose();
    },
  );

  test('focus mutations serialize concurrent starts and delayed guard refresh with finish', () async {
    final gateway = _FocusGateway();
    final controller = _controller(MemoryDocumentStore(), gateway);
    await controller.initialize();
    final task = await controller.createTask(title: '并发控制');
    final policy = controller.focusPolicies.firstWhere(
      (policy) => policy.mode == FocusPolicyMode.guard,
    );
    await Future.wait([
      controller.startFocus(task: task, durationSeconds: 900, policy: policy),
      controller.startFocus(task: task, durationSeconds: 900, policy: policy),
    ]);
    expect(controller.focusSessions, hasLength(1));
    expect(gateway.starts, 1);
    final id = controller.activeFocusSession!.id;
    gateway.delayedStats = Completer<GuardActivityStats>();
    final refresh = controller.refreshGuardActivityStats();
    final finish = controller.finishFocus();
    gateway.delayedStats!.complete(
      GuardActivityStats(sessionId: id, appExitCount: 4, interruptionCount: 2),
    );
    await refresh;
    final finished = await finish;
    expect(controller.activeFocusSession, isNull);
    expect(finished!.appExitCount, 4);
    expect(
      controller.focusSessions.single.status,
      FocusSessionStatus.completed,
    );
    controller.dispose();
  });

  test('a count failure after successful save does not report the create as failed', () async {
    final store = _CountFailureStore();
    final controller = _controller(store, _FocusGateway());
    await controller.initialize();
    store.failCount = true;
    final task = await controller.createTask(title: '已成功保存');
    expect(controller.tasks.single.id, task.id);
    expect((await store.readDocuments('task')).single.id, task.id);
    controller.dispose();
  });
}

AppController _controller(DocumentStore store, FocusPlatformGateway gateway) =>
    AppController(
      repository: WorkspaceRepository(store),
      focusPlatform: gateway,
    );

FocusSessionItem _session(
  AppController controller,
  TaskItem task, {
  required String deviceId,
}) => FocusSessionItem(
  id: controller.repository.createId(),
  taskId: task.id,
  focusPolicyId: controller.focusPolicies.first.id,
  plannedDurationSeconds: 1500,
  startedAt: DateTime.now(),
  startedDeviceId: deviceId,
  status: FocusSessionStatus.running,
  timeZone: 'Asia/Shanghai',
);

class _FocusGateway extends FocusPlatformGateway {
  FocusTimerState nativeState = const FocusTimerState();
  int starts = 0;
  int pauses = 0;
  int resumes = 0;
  int stops = 0;
  int statsReads = 0;
  String? startedSessionId;
  DateTime? endsAt;
  bool paused = false;
  int appExitCount = 0;
  int interruptionCount = 0;
  List<String> allowedPackageNames = const [];
  GuardActivityStats stats = const GuardActivityStats(
    appExitCount: 0,
    interruptionCount: 0,
  );
  Completer<GuardActivityStats>? delayedStats;

  @override
  Future<FocusTimerState> getTimerState() async => nativeState;

  @override
  Future<void> startTimer({
    String? sessionId,
    required String title,
    required DateTime endsAt,
    required FocusPolicyMode mode,
    List<String> allowedPackageNames = const [],
    String taskTypeName = '收集箱',
    int? maxAppExits,
    bool paused = false,
    int appExitCount = 0,
    int interruptionCount = 0,
  }) async {
    starts++;
    startedSessionId = sessionId;
    this.endsAt = endsAt;
    this.paused = paused;
    this.appExitCount = appExitCount;
    this.interruptionCount = interruptionCount;
    this.allowedPackageNames = allowedPackageNames;
  }

  @override
  Future<void> pauseTimer() async {
    pauses++;
  }

  @override
  Future<void> resumeTimer(DateTime endsAt) async {
    resumes++;
  }

  @override
  Future<void> stopTimer() async {
    stops++;
  }

  @override
  Future<GuardActivityStats> getGuardActivityStats() async {
    statsReads++;
    return delayedStats?.future ?? Future.value(stats);
  }
}

class _CountFailureStore extends MemoryDocumentStore {
  bool failCount = false;
  @override
  Future<int> pendingOperationCount({
    String accountId = DocumentStore.localAccountId,
  }) {
    if (failCount) throw StateError('count query failed after commit');
    return super.pendingOperationCount(accountId: accountId);
  }
}
