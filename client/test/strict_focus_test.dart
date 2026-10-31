import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/focus/pages/focus_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'strict rules reject controller bypasses without changing the session',
    () async {
      final platform = _Platform();
      final app = _app(MemoryDocumentStore(), platform);
      await app.initialize();
      final task = await app.createTask(title: '严格规则');
      final policy = app.focusPolicies.firstWhere(
        (p) => p.mode == FocusPolicyMode.strict,
      );
      await app.startFocus(task: task, durationSeconds: 900, policy: policy);
      final id = app.activeFocusSession!.id;
      await expectLater(app.pauseFocus(), throwsStateError);
      await expectLater(app.finishFocus(), throwsStateError);
      await expectLater(
        app.finishFocus(status: FocusSessionStatus.running),
        throwsArgumentError,
      );
      await expectLater(
        app.finishFocus(status: FocusSessionStatus.abandoned, reason: '紧急'),
        throwsStateError,
      );
      app.beginEarlyFocusExit();
      expect(app.earlyExitRemainingSeconds, inInclusiveRange(29, 30));
      app.cancelEarlyFocusExit();
      expect(app.earlyExitRemainingSeconds, 30);
      expect(app.activeFocusSession!.id, id);
      expect(app.activeFocusSession!.status, FocusSessionStatus.running);
      expect(platform.pauses, 0);
      expect(platform.events, isEmpty);
      app.dispose();
    },
  );

  test(
    'strict completion is available at target and preserves the open task',
    () async {
      final platform = _Platform();
      final app = _app(MemoryDocumentStore(), platform);
      await app.initialize();
      final task = await app.createTask(title: '达到目标');
      await app.startFocus(
        task: task,
        durationSeconds: 900,
        policy: app.focusPolicies.firstWhere(
          (p) => p.mode == FocusPolicyMode.strict,
        ),
      );
      app.focusSessions = [
        FocusSessionItem.fromDocument(app.activeFocusSession!.id, {
          ...app.activeFocusSession!.toBody(),
          'started_at': DateTime.now()
              .subtract(const Duration(minutes: 16))
              .toUtc()
              .toIso8601String(),
        }),
      ];
      final ended = await app.finishFocus();
      expect(ended!.status, FocusSessionStatus.completed);
      expect(app.activeFocusSession, isNull);
      expect(app.taskById(task.id)!.status, TaskStatus.open);
      expect(platform.events, ['completed']);
      app.dispose();
    },
  );

  test('vibration choice survives restart and feedback failure does not undo completion', () async {
    final store = MemoryDocumentStore();
    final app = _app(store, _Platform());
    await app.initialize();
    expect(app.focusVibrationEnabled, isTrue);
    await app.setFocusVibration(false);
    app.dispose();
    final platform = _Platform()..failFeedback = true;
    final reloaded = _app(store, platform);
    await reloaded.initialize();
    expect(reloaded.focusVibrationEnabled, isFalse);
    final task = await reloaded.createTask(title: '震动不可用仍能保存');
    await reloaded.startFocus(
      task: task,
      durationSeconds: 900,
      policy: reloaded.focusPolicies.first,
    );
    expect(platform.enabled, isFalse);
    final ended = await reloaded.finishFocus();
    expect(ended!.status, FocusSessionStatus.completed);
    expect(
      (await store.readDocuments('focus_session')).single.body['status'],
      'completed',
    );
    reloaded.dispose();
  });

  test(
    'guard pause rule and missing strict permissions apply below the UI',
    () async {
      final platform = _Platform();
      final app = _app(MemoryDocumentStore(), platform);
      await app.initialize();
      final task = await app.createTask(title: '守护规则');
      final guard = app.focusPolicies.firstWhere(
        (p) => p.mode == FocusPolicyMode.guard,
      );
      await app.startFocus(task: task, durationSeconds: 900, policy: guard);
      await expectLater(app.pauseFocus(), throwsStateError);
      await app.finishFocus();
      app.overlayPermissionGranted = false;
      await expectLater(
        app.startFocus(
          task: task,
          durationSeconds: 900,
          policy: app.focusPolicies.firstWhere(
            (p) => p.mode == FocusPolicyMode.strict,
          ),
        ),
        throwsStateError,
      );
      expect(app.activeFocusSession, isNull);
      app.dispose();
    },
  );

  test('a failed native stop preserves completion and foreground reconciliation retries it', () async {
    final platform = _Platform();
    final app = _app(MemoryDocumentStore(), platform);
    await app.initialize();
    final task = await app.createTask(title: '系统服务重试');
    await app.startFocus(
      task: task,
      durationSeconds: 900,
      policy: app.focusPolicies.first,
    );
    platform.nativeActive = true;
    platform.failStop = true;
    expect((await app.finishFocus())!.status, FocusSessionStatus.completed);
    expect(app.focusPlatformErrorMessage, isNotNull);
    expect(app.activeFocusSession, isNull);
    platform.failStop = false;
    await app.reconcileNativeFocus();
    expect(platform.nativeActive, isFalse);
    expect(app.focusPlatformErrorMessage, isNull);
    app.dispose();
  });

  testWidgets('cancelled tasks are excluded from focus selection', (
    tester,
  ) async {
    final app = _app(MemoryDocumentStore(), _Platform());
    await app.initialize();
    final task = await app.createTask(title: '已取消的任务');
    await app.updateTask(task.copyWith(status: TaskStatus.cancelled));
    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,

          home: FocusPage(onOpenSettings: () {}, onFocusEnded: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('自由专注（暂不关联任务）'), findsOneWidget);
    expect(find.text('已取消的任务'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  test('taskless strict focus keeps permissions, exit rules and association timing', () async {
    final platform = _Platform();
    final app = _app(MemoryDocumentStore(), platform);
    addTearDown(app.dispose);
    await app.initialize();
    final policy = app.focusPolicies.firstWhere(
      (policy) => policy.mode == FocusPolicyMode.strict,
    );
    app.overlayPermissionGranted = false;
    await expectLater(
      app.startFocus(durationSeconds: 900, policy: policy),
      throwsStateError,
    );
    expect(app.activeFocusSession, isNull);
    app.overlayPermissionGranted = true;
    await app.startFocus(durationSeconds: 900, policy: policy);
    expect(app.activeFocusSession!.taskId, isNull);
    await expectLater(app.pauseFocus(), throwsStateError);
    await expectLater(app.finishFocus(), throwsStateError);
    app.beginEarlyFocusExit();
    expect(app.earlyExitRemainingSeconds, inInclusiveRange(29, 30));
    app.cancelEarlyFocusExit();
    app.focusSessions = [
      FocusSessionItem.fromDocument(app.activeFocusSession!.id, {
        ...app.activeFocusSession!.toBody(),
        'started_at': DateTime.now()
            .subtract(const Duration(minutes: 16))
            .toUtc()
            .toIso8601String(),
      }),
    ];
    final ended = (await app.finishFocus())!;
    final task = await app.createTask(title: 'After strict free focus');
    await app.associateFocusSessionTask(sessionId: ended.id, task: task);
    expect(
      app.focusSessions.single.actualDurationSeconds,
      ended.actualDurationSeconds,
    );
    expect(app.focusSessions.single.taskId, task.id);
    expect(app.taskById(task.id)!.status, TaskStatus.open);
    expect(platform.events, ['completed']);
  });

  testWidgets(
    'strict UI disables early completion and starts cancellable exit countdown',
    (tester) async {
      final app = _app(MemoryDocumentStore(), _Platform());
      await app.initialize();
      final task = await app.createTask(title: '严格专注界面');
      await app.startFocus(
        task: task,
        durationSeconds: 900,
        policy: app.focusPolicies.firstWhere(
          (p) => p.mode == FocusPolicyMode.strict,
        ),
      );
      await tester.pumpWidget(
        AppScope(
          controller: app,
          child: MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,

            home: FocusPage(onOpenSettings: () {}, onFocusEnded: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final complete = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('完成专注'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(complete.onPressed, isNull);
      await tester.ensureVisible(find.text('提前结束'));
      await tester.tap(find.text('提前结束'));
      await tester.pumpAndSettle();
      expect(find.text('原因（必填）'), findsOneWidget);
      expect(find.textContaining('等待 30 秒'), findsWidgets);
      await tester.tap(find.text('继续专注'));
      await tester.pumpAndSettle();
      expect(app.activeFocusSession, isNotNull);
      expect(app.earlyExitRemainingSeconds, 30);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
    },
  );
}

AppController _app(DocumentStore store, FocusPlatformGateway platform) =>
    AppController(
      repository: WorkspaceRepository(store),
      focusPlatform: platform,
    );

class _Platform extends FocusPlatformGateway {
  int pauses = 0;
  bool enabled = true;
  bool failFeedback = false;
  bool nativeActive = false;
  bool failStop = false;
  final events = <String>[];
  @override
  Future<FocusTimerState> getTimerState() async =>
      FocusTimerState(isActive: nativeActive);
  @override
  Future<void> stopTimer() async {
    if (failStop) throw StateError('stop failed');
    nativeActive = false;
  }

  @override
  Future<void> configureFeedback({
    required bool enabled,
    required String notificationMode,
  }) async {
    this.enabled = enabled;
  }

  @override
  Future<void> feedback(String event) async {
    if (failFeedback) throw StateError('vibrator unavailable');
    events.add(event);
  }

  @override
  Future<void> pauseTimer() async {
    pauses++;
  }
}
