import 'package:flutter_localizations/flutter_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/app/pactick_app.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/core/state/session_scope.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/platform/task_reminder_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/settings/pages/settings_page.dart';
import 'package:pactick/features/settings/pages/task_reminder_settings.dart';

import 'support/session_test_support.dart';

typedef ReminderUpdate = ({
  bool enabled,
  int count,
  String workspace,
  bool requestPermission,
  bool automatic,
});

class _ReminderGateway extends TaskReminderPlatformGateway {
  final updates = <ReminderUpdate>[];
  final schedules =
      <
        ({bool enabled, String workspace, List<Map<String, Object>> reminders})
      >[];
  bool allowed = true;
  bool fail = false;
  bool scheduleFail = false;
  int clears = 0;
  bool openTasks = false;
  Completer<bool>? nextUpdate;

  @override
  bool get isSupported => true;

  @override
  Future<bool> update({
    required bool enabled,
    required int openTaskCount,
    required String workspaceId,
    bool requestPermission = false,
    bool automatic = true,
  }) async {
    updates.add((
      enabled: enabled,
      count: openTaskCount,
      workspace: workspaceId,
      requestPermission: requestPermission,
      automatic: automatic,
    ));
    final pending = nextUpdate;
    nextUpdate = null;
    if (pending != null) return pending.future;
    if (fail) throw PlatformException(code: 'task_reminder_update_failed');
    return allowed;
  }

  @override
  Future<bool> takeOpenTasksRequest() async {
    final requested = openTasks;
    openTasks = false;
    return requested;
  }

  @override
  Future<bool> updateSchedule({
    required bool enabled,
    required String workspaceId,
    required List<Map<String, Object>> reminders,
    bool requestPermission = false,
    bool automatic = true,
  }) async {
    if (scheduleFail) throw PlatformException(code: 'schedule_failed');
    schedules.add((
      enabled: enabled,
      workspace: workspaceId,
      reminders: reminders,
    ));
    return allowed;
  }

  @override
  Future<void> clearWorkspace() async {
    clears++;
  }
}

class _FailingSettingsStore extends MemoryDocumentStore {
  bool fail = false;

  @override
  Future<void> writeSetting(
    String key,
    String value, {
    String accountId = DocumentStore.localAccountId,
  }) async {
    if (fail &&
        (key == 'task_reminders_enabled' ||
            key == 'scheduled_task_reminders_enabled')) {
      throw StateError('disk unavailable');
    }
    await super.writeSetting(key, value, accountId: accountId);
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void _resumeFromBackground(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'default is on; only open tasks count and empty workspaces do not prompt',
    () async {
      final gateway = _ReminderGateway();
      final app = AppController(
        repository: WorkspaceRepository(MemoryDocumentStore()),
        focusPlatform: const FocusPlatformGateway(),
        taskReminderPlatform: gateway,
      );
      addTearDown(app.dispose);
      await app.initialize();
      await _flush();
      expect(app.taskRemindersEnabled, isTrue);
      expect(gateway.updates.last.count, 0);
      expect(gateway.updates.last.requestPermission, isFalse);
      final done = await app.createTask(title: '已完成');
      final cancelled = await app.createTask(title: '已取消');
      final open = await app.createTask(title: '待办');
      await app.toggleTask(done);
      await app.updateTask(cancelled.copyWith(status: TaskStatus.cancelled));
      await _flush();
      expect(gateway.updates.last.count, 1);
      expect(gateway.updates.last.requestPermission, isTrue);
      await app.toggleTask(open);
      await _flush();
      expect(gateway.updates.last.count, 0);
      expect(gateway.updates.last.requestPermission, isFalse);
      await app.toggleTask(app.tasks.firstWhere((task) => task.id == open.id));
      await _flush();
      expect(gateway.updates.last.count, 1);
    },
  );

  test('disabled preference survives controller restart', () async {
    final store = MemoryDocumentStore();
    final first = AppController(
      repository: WorkspaceRepository(store),
      focusPlatform: const FocusPlatformGateway(),
      taskReminderPlatform: _ReminderGateway(),
    );
    await first.initialize();
    await first.createTask(title: '保存待办');
    await first.setTaskRemindersEnabled(false);
    await first.setScheduledTaskRemindersEnabled(false);
    first.dispose();
    final gateway = _ReminderGateway();
    final restored = AppController(
      repository: WorkspaceRepository(store),
      focusPlatform: const FocusPlatformGateway(),
      taskReminderPlatform: gateway,
    );
    addTearDown(restored.dispose);
    await restored.initialize();
    await _flush();
    expect(restored.taskRemindersEnabled, isFalse);
    expect(restored.scheduledTaskRemindersEnabled, isFalse);
    expect(gateway.updates.last.enabled, isFalse);
    expect(gateway.updates.last.requestPermission, isFalse);
  });

  test('schedule changes resubmit timestamps with no task content; completion and removal cancel', () async {
    final gateway = _ReminderGateway();
    final app = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
      taskReminderPlatform: gateway,
    );
    addTearDown(app.dispose);
    await app.initialize();
    final due = DateTime.now().add(const Duration(days: 1));
    final task = await app.createTask(
      title: '私密标题不交给原生',
      note: '私密备注',
      dueAt: due,
    );
    final block = await app.scheduleTask(
      taskId: task.id,
      startsAt: due.subtract(const Duration(hours: 2)),
      duration: const Duration(minutes: 45),
    );
    await app.refreshTaskReminders();
    expect(gateway.schedules.last.enabled, isTrue);
    expect(gateway.schedules.last.reminders, [
      {
        'id': 'plan:${block.id}',
        'atMillis': block.startsAt.millisecondsSinceEpoch,
        'kind': 'plan',
      },
      {
        'id': 'due:${task.id}',
        'atMillis': due.millisecondsSinceEpoch,
        'kind': 'deadline',
      },
    ]);
    final later = due.add(const Duration(days: 2));
    await app.updateTask(task.copyWith(dueAt: later));
    await _flush();
    expect(
      gateway.schedules.last.reminders.last['atMillis'],
      later.millisecondsSinceEpoch,
    );
    final changed = await app.updatePlanBlock(
      block: block,
      taskId: task.id,
      startsAt: later.add(const Duration(hours: 1)),
      duration: const Duration(minutes: 60),
    );
    await _flush();
    expect(
      gateway.schedules.last.reminders.last['atMillis'],
      changed.startsAt.millisecondsSinceEpoch,
    );
    await app.toggleTask(app.tasks.single);
    await _flush();
    expect(gateway.schedules.last.reminders, isEmpty);
    await app.toggleTask(app.tasks.single);
    await app.deletePlanBlock(changed);
    await _flush();
    expect(gateway.schedules.last.reminders.single['kind'], 'deadline');
    await app.repository.deleteTask(task.id);
    await app.retryInitialization();
    await _flush();
    expect(gateway.schedules.last.reminders, isEmpty);
  });

  test('standalone scheduled plans remind while completed and cancelled plans do not', () async {
    final gateway = _ReminderGateway();
    final app = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
      taskReminderPlatform: gateway,
    );
    addTearDown(app.dispose);
    await app.initialize();
    final starts = DateTime.now().add(const Duration(days: 1));
    final standalone = await app.scheduleTask(
      title: '独立时段',
      startsAt: starts,
      duration: const Duration(minutes: 30),
    );
    for (final status in [
      PlanBlockStatus.completed,
      PlanBlockStatus.cancelled,
    ]) {
      await app.repository.savePlanBlock(
        PlanBlockItem(
          id: status.name,
          startsAt: starts,
          endsAt: starts.add(const Duration(minutes: 30)),
          title: status.name,
          timeZone: 'Asia/Shanghai',
          status: status,
        ),
      );
    }
    await app.retryInitialization();
    await app.refreshTaskReminders();
    expect(
      gateway.schedules.last.reminders.single['id'],
      'plan:${standalone.id}',
    );
    await app.setTaskRemindersEnabled(false);
    expect(gateway.schedules.last.enabled, isTrue);
    expect(gateway.updates.last.enabled, isFalse);
    await app.setScheduledTaskRemindersEnabled(false);
    expect(gateway.schedules.last.enabled, isFalse);
  });

  test('failed scheduled setting preserves state and scheduler failure can be retried', () async {
    final store = _FailingSettingsStore();
    final gateway = _ReminderGateway();
    final app = AppController(
      repository: WorkspaceRepository(store),
      focusPlatform: const FocusPlatformGateway(),
      taskReminderPlatform: gateway,
    );
    addTearDown(app.dispose);
    await app.initialize();
    await app.refreshTaskReminders();
    store.fail = true;
    await expectLater(
      app.setScheduledTaskRemindersEnabled(false),
      throwsStateError,
    );
    expect(app.scheduledTaskRemindersEnabled, isTrue);
    store.fail = false;
    gateway.scheduleFail = true;
    await app.createTask(
      title: '调度失败不影响本地保存',
      dueAt: DateTime.now().add(const Duration(days: 1)),
    );
    await app.refreshTaskReminders();
    expect(app.tasks, hasLength(1));
    expect(app.taskReminderErrorMessage, contains('可重试'));
    gateway.scheduleFail = false;
    await app.refreshTaskReminders();
    expect(app.taskReminderErrorMessage, isNull);
    expect(gateway.schedules.last.reminders, hasLength(1));
  });

  test('failed preference write retains the switch and native state', () async {
    final store = _FailingSettingsStore();
    final gateway = _ReminderGateway();
    final app = AppController(
      repository: WorkspaceRepository(store),
      focusPlatform: const FocusPlatformGateway(),
      taskReminderPlatform: gateway,
    );
    addTearDown(app.dispose);
    await app.initialize();
    await _flush();
    final before = gateway.updates.length;
    store.fail = true;
    await expectLater(app.setTaskRemindersEnabled(false), throwsStateError);
    expect(app.taskRemindersEnabled, isTrue);
    expect(gateway.updates.length, before);
  });

  test(
    'platform failure preserves successful task save and can be retried',
    () async {
      final store = MemoryDocumentStore();
      final gateway = _ReminderGateway();
      final repository = WorkspaceRepository(store);
      final app = AppController(
        repository: repository,
        focusPlatform: const FocusPlatformGateway(),
        taskReminderPlatform: gateway,
      );
      addTearDown(app.dispose);
      await app.initialize();
      await _flush();
      gateway.fail = true;
      final task = await app.createTask(title: '通知失败仍保存');
      await _flush();
      expect((await repository.load()).tasks.single.id, task.id);
      expect(app.taskReminderErrorMessage, contains('可重试'));
      gateway.fail = false;
      await app.refreshTaskReminders();
      expect(app.taskReminderErrorMessage, isNull);
      expect(gateway.updates.last.count, 1);
    },
  );

  test('queued updates keep latest workspace and ignore obsolete permission result', () async {
    final gateway = _ReminderGateway();
    final app = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
      taskReminderPlatform: gateway,
    );
    addTearDown(app.dispose);
    await app.initialize();
    await _flush();
    final pending = Completer<bool>();
    gateway.nextUpdate = pending;
    await app.createTask(title: '原工作区');
    await _flush();
    await app.connectSyncAccount(
      offline: true,
      userId: 'another-user',
      deviceId: 'device',
    );
    expect(gateway.clears, greaterThan(0));
    pending.complete(false);
    await _flush();
    expect(gateway.updates.last.count, 0);
    expect(gateway.updates.last.workspace, isNot(DocumentStore.localAccountId));
    expect(gateway.schedules.last.reminders, isEmpty);
    expect(
      gateway.schedules.last.workspace,
      isNot(DocumentStore.localAccountId),
    );
    expect(app.taskReminderNotificationsAllowed, isTrue);
  });

  testWidgets('settings defaults on and saves the off switch', (tester) async {
    final gateway = _ReminderGateway();
    final app = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
      taskReminderPlatform: gateway,
    );
    addTearDown(app.dispose);
    await app.initialize();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,

        home: Scaffold(
          body: AnimatedBuilder(
            animation: app,
            builder: (_, _) => TaskReminderSettingsCard(controller: app),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('task-reminders-toggle'));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(gateway.updates.last.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final coldStart in [true, false]) {
    testWidgets(
      'notification opens tasks on ${coldStart ? 'cold start' : 'resume from settings'}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(412, 915);
        addTearDown(tester.view.reset);
        final gateway = _ReminderGateway()..openTasks = coldStart;
        final app = AppController(
          repository: WorkspaceRepository(MemoryDocumentStore()),
          focusPlatform: const FocusPlatformGateway(),
          taskReminderPlatform: gateway,
        );
        final session = await createAuthenticatedSessionController();
        await app.initialize();
        await tester.pumpWidget(
          AppScope(
            controller: app,
            child: SessionScope(controller: session, child: const PactickApp()),
          ),
        );
        await tester.pumpAndSettle();
        if (!coldStart) {
          await tester.tap(find.byIcon(Icons.settings_outlined).first);
          await tester.pumpAndSettle();
          expect(find.byType(SettingsPage), findsOneWidget);
          gateway.openTasks = true;
          _resumeFromBackground(tester);
          await tester.pumpAndSettle();
          expect(find.byType(SettingsPage), findsNothing);
        }
        final navigation = tester.widget<NavigationBar>(
          find.byType(NavigationBar),
        );
        expect(
          (navigation.destinations[navigation.selectedIndex]
                  as NavigationDestination)
              .label,
          '任务',
        );
        expect(app.taskReminderOpenSequence, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        app.dispose();
        session.dispose();
      },
    );
  }

  testWidgets('notification navigation respects unsaved page guards', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    final gateway = _ReminderGateway();
    final app = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
      taskReminderPlatform: gateway,
    );
    final session = await createAuthenticatedSessionController();
    await app.initialize();
    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: SessionScope(controller: session, child: const PactickApp()),
      ),
    );
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const PopScope(
            canPop: false,
            child: Scaffold(body: Text('未保存编辑')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    gateway.openTasks = true;
    _resumeFromBackground(tester);
    await tester.pumpAndSettle();
    expect(find.text('未保存编辑'), findsOneWidget);
    expect(app.taskReminderOpenSequence, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
    session.dispose();
  });
}
