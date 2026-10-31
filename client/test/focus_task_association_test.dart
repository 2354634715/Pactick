import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryDocumentStore store;
  late AppController controller;
  late _FocusGateway gateway;

  setUp(() async {
    store = MemoryDocumentStore();
    gateway = _FocusGateway();
    controller = _controller(store, gateway);
    await controller.initialize();
  });

  tearDown(() => controller.dispose());

  test(
    'focus without a task persists and restores its paused native timer',
    () async {
      await controller.setAppWhitelist(null, {'com.example.notes'});
      await controller.startFocus(
        durationSeconds: 900,
        policy: controller.focusPolicies.first,
      );
      final session = controller.activeFocusSession!;
      expect(controller.tasks, isEmpty);
      expect(session.taskId, isNull);
      expect(controller.focusSessionTitle(session), '自由专注');
      expect(gateway.title, '自由专注');
      expect(gateway.allowedPackageNames, ['com.example.notes']);
      expect(
        (await store.readDocuments('focus_session')).single.body['task_id'],
        isNull,
      );
      await controller.pauseFocus();

      final restoredGateway = _FocusGateway();
      final restored = _controller(store, restoredGateway);
      await restored.initialize();
      expect(restored.activeFocusSession!.id, session.id);
      expect(restored.activeFocusSession!.taskId, isNull);
      expect(restoredGateway.title, '自由专注');
      expect(restoredGateway.paused, isTrue);
      expect(restored.tasks, isEmpty);
      restored.dispose();
    },
  );

  test('associating a finished focus changes only its task and queues that association', () async {
    final session = _finished(controller);
    await store.putDocument(
      'focus_session',
      session.id,
      session.toBody(),
      enqueue: false,
    );
    await controller.retryInitialization();
    final task = await controller.createTask(title: '补记任务');
    final actualBefore = controller
        .statisticsForLastDays(1)
        .single
        .actualDurationSeconds;

    expect(controller.canAssociateFocusSessionTask(session), isTrue);
    await controller.associateFocusSessionTask(
      sessionId: session.id,
      task: task,
    );

    final associated = controller.focusSessions.single;
    expect(associated.toBody(), {...session.toBody(), 'task_id': task.id});
    expect(controller.focusSessionTitle(associated), task.title);
    expect(
      controller.actualSecondsForTask(task.id),
      session.actualDurationSeconds,
    );
    expect(
      controller.statisticsForLastDays(1).single.actualDurationSeconds,
      actualBefore,
    );
    final pending = await store.readPendingOperations(
      DocumentStore.localAccountId,
    );
    final focusOperation = pending.singleWhere(
      (operation) => operation.entityId == session.id,
    );
    expect(focusOperation.patch!['task_id'], task.id);
    expect(
      focusOperation.patch!['actual_duration_seconds'],
      session.actualDurationSeconds,
    );
    expect(gateway.starts, 0);
    final pendingCount = controller.pendingOperations;
    await controller.associateFocusSessionTask(
      sessionId: session.id,
      task: task,
    );
    expect(controller.pendingOperations, pendingCount);
  });

  test(
    'older local focus remains associable after a new session and restart',
    () async {
      final task = await controller.createTask(title: '稍后关联');
      await controller.startFocus(
        durationSeconds: 900,
        policy: controller.focusPolicies.first,
      );
      final first = (await controller.finishFocus())!;
      await controller.startFocus(
        durationSeconds: 900,
        policy: controller.focusPolicies.first,
      );
      final second = controller.activeFocusSession!;
      expect(controller.isLocalFocusSession(first), isFalse);
      expect(controller.canAssociateFocusSessionTask(first), isTrue);

      final restored = _controller(store, _FocusGateway());
      await restored.initialize();
      expect(restored.activeFocusSession!.id, second.id);
      await restored.associateFocusSessionTask(sessionId: first.id, task: task);
      expect(
        restored.focusSessions
            .singleWhere((session) => session.id == first.id)
            .taskId,
        task.id,
      );
      expect(restored.activeFocusSession!.taskId, isNull);
      restored.dispose();
    },
  );

  test('restored local terminal history can be associated without taking timer ownership', () async {
    final task = await controller.createTask(title: '恢复后的任务');
    final session = _finished(controller);
    await store.putDocument(
      'focus_session',
      session.id,
      session.toBody(),
      enqueue: false,
    );
    final archive = await controller.repository.backups.exportJson(
      controller.repository.selectedAccountId,
    );
    final restoredId = await controller.repository.backups.restoreJson(archive);
    await controller.openOfflineWorkspace(restoredId);
    expect(
      controller.isLocalFocusSession(controller.focusSessions.single),
      isFalse,
    );
    expect(
      controller.canAssociateFocusSessionTask(controller.focusSessions.single),
      isTrue,
    );
    await controller.associateFocusSessionTask(
      sessionId: session.id,
      task: controller.taskById(task.id)!,
    );
    expect(controller.focusSessions.single.taskId, task.id);
    expect(controller.activeFocusSession, isNull);
    expect(gateway.starts, 0);
  });

  test(
    'association rejects active sessions, missing tasks and replacement tasks',
    () async {
      final task = await controller.createTask(title: '目标任务');
      final other = await controller.createTask(title: '另一任务');
      await controller.startFocus(
        durationSeconds: 900,
        policy: controller.focusPolicies.first,
      );
      final sessionId = controller.activeFocusSession!.id;
      expect(
        controller.canAssociateFocusSessionTask(controller.activeFocusSession!),
        isFalse,
      );
      await expectLater(
        controller.associateFocusSessionTask(sessionId: sessionId, task: task),
        throwsStateError,
      );
      await controller.finishFocus();
      await expectLater(
        controller.associateFocusSessionTask(sessionId: 'missing', task: task),
        throwsStateError,
      );
      await controller.repository.deleteTask(task.id);
      await controller.retryInitialization();
      await expectLater(
        controller.associateFocusSessionTask(sessionId: sessionId, task: task),
        throwsStateError,
      );
      await controller.associateFocusSessionTask(
        sessionId: sessionId,
        task: other,
      );
      final replacement = await controller.createTask(title: '不能换到这里');
      await expectLater(
        controller.associateFocusSessionTask(
          sessionId: sessionId,
          task: replacement,
        ),
        throwsStateError,
      );
      expect(controller.focusSessions.single.taskId, other.id);
    },
  );

  test('another sync device cannot associate a terminal focus', () async {
    await controller.connectSyncAccount(
      userId: 'account',
      deviceId: 'device-b',
      offline: true,
    );
    final task = await controller.createTask(title: '云端目标');
    final session = _finished(controller);
    await store.putDocument(
      'focus_session',
      session.id,
      session.toBody(),
      accountId: 'account',
      enqueue: false,
    );
    await controller.retryInitialization();
    expect(
      controller.canAssociateFocusSessionTask(controller.focusSessions.single),
      isFalse,
    );
    await expectLater(
      controller.associateFocusSessionTask(sessionId: session.id, task: task),
      throwsStateError,
    );
    expect(controller.focusSessions.single.taskId, isNull);
  });

  for (final restoredBackup in [false, true]) {
    test(
      'association preserves raw ${restoredBackup ? 'backup' : 'server'} timestamps and pause history',
      () async {
        if (!restoredBackup) {
          await controller.connectSyncAccount(
            userId: 'account',
            deviceId: 'device-b',
            offline: true,
          );
        }
        final task = await controller.createTask(title: '暂停后补记');
        final session = _finished(controller);
        final endedAt = session.endedAt!;
        final raw = {
          ...session.toBody(),
          // Keep an equivalent non-UTC spelling to detect timestamp rewrites.
          'started_at': session.startedAt.toIso8601String(),
          'ended_at': endedAt.toIso8601String(),
          'started_device_id': 'device-b',
          'pause_intervals': [
            {
              'started_at': endedAt
                  .subtract(const Duration(minutes: 2))
                  .toIso8601String(),
              'ended_at': endedAt
                  .subtract(const Duration(seconds: 90))
                  .toIso8601String(),
            },
          ],
        };
        await store.putDocument(
          'focus_session',
          session.id,
          raw,
          accountId: controller.repository.selectedAccountId,
          enqueue: false,
        );
        if (restoredBackup) {
          final archive = await controller.repository.backups.exportJson(
            controller.repository.selectedAccountId,
          );
          final restoredId = await controller.repository.backups.restoreJson(
            archive,
          );
          await controller.openOfflineWorkspace(restoredId);
        } else {
          await controller.retryInitialization();
        }
        final accountId = controller.repository.selectedAccountId;
        final before = (await store.readDocuments(
          'focus_session',
          accountId: accountId,
        )).single.body;
        await controller.associateFocusSessionTask(
          sessionId: session.id,
          task: controller.taskById(task.id)!,
        );
        final after = (await store.readDocuments(
          'focus_session',
          accountId: accountId,
        )).single.body;
        expect(after, {...before, 'task_id': task.id});
        expect(after['pause_intervals'], raw['pause_intervals']);
        expect(after['started_at'], raw['started_at']);
        expect(after['ended_at'], raw['ended_at']);
      },
    );
  }

  for (final status in [
    FocusSessionStatus.abandoned,
    FocusSessionStatus.interrupted,
  ]) {
    test(
      '${status.name} focus can be associated with a completed task',
      () async {
        final task = await controller.createTask(title: '已完成目标');
        await controller.toggleTask(task);
        final session = _finished(controller).copyWith(status: status);
        await store.putDocument(
          'focus_session',
          session.id,
          session.toBody(),
          enqueue: false,
        );
        await controller.retryInitialization();
        await controller.associateFocusSessionTask(
          sessionId: session.id,
          task: controller.taskById(task.id)!,
        );
        expect(controller.focusSessions.single.status, status);
        expect(controller.focusSessions.single.taskId, task.id);
      },
    );
  }
}

AppController _controller(DocumentStore store, FocusPlatformGateway gateway) =>
    AppController(
      repository: WorkspaceRepository(store),
      focusPlatform: gateway,
    );

FocusSessionItem _finished(AppController controller) {
  final endedAt = DateTime.now();
  return FocusSessionItem(
    id: controller.repository.createId(),
    focusPolicyId: controller.focusPolicies.first.id,
    plannedDurationSeconds: 900,
    startedAt: endedAt.subtract(const Duration(minutes: 10)),
    endedAt: endedAt,
    actualDurationSeconds: 570,
    pausedDurationSeconds: 30,
    startedDeviceId: 'other-device',
    status: FocusSessionStatus.completed,
    timeZone: 'Asia/Shanghai',
    appExitCount: 2,
    interruptionCount: 1,
  );
}

class _FocusGateway extends FocusPlatformGateway {
  String? title;
  bool paused = false;
  int starts = 0;
  List<String> allowedPackageNames = const [];

  @override
  Future<void> startTimer({
    String? sessionId,
    required String title,
    String? titleKey,
    required DateTime endsAt,
    required FocusPolicyMode mode,
    List<String> allowedPackageNames = const [],
    String? taskTypeName,
    String? taskTypeKey,
    int? maxAppExits,
    bool paused = false,
    bool focusDesktopEnabled = false,
    int appExitCount = 0,
    int interruptionCount = 0,
  }) async {
    this.title = title;
    this.paused = paused;
    this.allowedPackageNames = allowedPackageNames;
    starts++;
  }
}
