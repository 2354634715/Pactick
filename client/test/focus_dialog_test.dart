import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('reaching the target keeps recording and pause promotes resume', (
    tester,
  ) async {
    final controller = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
    );
    await controller.initialize();
    final task = await controller.createTask(title: '达到目标后由使用者完成');
    await controller.startFocus(
      task: task,
      durationSeconds: 45,
      policy: controller.focusPolicies.first,
    );
    controller.focusSessions = [
      FocusSessionItem.fromDocument(controller.activeFocusSession!.id, {
        ...controller.activeFocusSession!.toBody(),
        'started_at': DateTime.now()
            .subtract(const Duration(seconds: 61))
            .toUtc()
            .toIso8601String(),
      }),
    ];
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          home: FocusPage(onOpenSettings: () {}, onFocusEnded: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('目标已到，仍在记录'), findsOneWidget);
    expect(controller.taskById(task.id)!.isCompleted, isFalse);
    expect(controller.activeFocusSession, isNotNull);
    await tester.ensureVisible(find.text('暂停'));
    await tester.tap(find.text('暂停'));
    await tester.pumpAndSettle();
    expect(find.text('目标已到，已暂停'), findsOneWidget);
    final resume = find.ancestor(
      of: find.text('继续'),
      matching: find.byType(FilledButton),
    );
    expect(resume, findsOneWidget);
    await tester.ensureVisible(resume);
    await tester.tap(resume);
    await tester.pumpAndSettle();
    expect(find.text('目标已到，仍在记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('permission launch failure remains actionable on focus page', (
    tester,
  ) async {
    final controller = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const _FailingPermissionGateway(),
    );
    await controller.initialize();
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          home: FocusPage(onOpenSettings: () {}, onFocusEnded: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('专注权限'));
    await tester.pumpAndSettle();
    final button = find.text('前往授权').first;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.textContaining('权限操作未完成，普通专注仍可使用'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<OutlinedButton>(
            find.ancestor(of: button, matching: find.byType(OutlinedButton)),
          )
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('a four-hour task can be selected and started', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);

    final controller = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
    );
    await controller.initialize();
    await controller.createTask(
      title: '短任务',
      estimatedDurationSeconds: 15 * 60,
    );
    final task = await controller.createTask(
      title: '四小时任务',
      estimatedDurationSeconds: 240 * 60,
    );

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          home: FocusPage(onOpenSettings: () {}, onFocusEnded: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('四小时任务').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 240);
    await tester.ensureVisible(find.text('开始专注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始专注'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.activeFocusSession?.taskId, task.id);
    expect(controller.activeFocusSession?.plannedDurationSeconds, 240 * 60);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'early-exit dialog can close and submit without lifecycle errors',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);

      final controller = AppController(
        repository: WorkspaceRepository(MemoryDocumentStore()),
        focusPlatform: const FocusPlatformGateway(),
      );
      await controller.initialize();
      final task = await controller.createTask(title: '整理第一版评审要点并确认跨设备冲突处理流程');
      await controller.startFocus(
        task: task,
        durationSeconds: 25 * 60,
        policy: controller.focusPolicies.first,
      );
      var focusEndedCount = 0;

      await tester.pumpWidget(
        AppScope(
          controller: controller,
          child: MaterialApp(
            home: FocusPage(
              onOpenSettings: () {},
              onFocusEnded: () => focusEndedCount++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('提前结束'));
      await tester.tap(find.text('提前结束'));
      await tester.pumpAndSettle();
      expect(find.text('提前结束专注？'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '暂时不结束');
      await tester.tap(find.text('继续专注'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.activeFocusSession, isNotNull);

      await tester.tap(find.text('提前结束'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '需要处理紧急电话');
      await tester.tap(find.text('结束'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(controller.activeFocusSession, isNull);
      expect(controller.focusSessions.first.terminationReason, '需要处理紧急电话');
      expect(focusEndedCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      controller.dispose();
    },
  );

  testWidgets('completing the selected task clears a stale dropdown value', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);

    final controller = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
    );
    await controller.initialize();
    final task = await controller.createTask(title: '完成后清理选择项');
    await controller.startFocus(
      task: task,
      durationSeconds: 25 * 60,
      policy: controller.focusPolicies.first,
    );
    var focusEndedCount = 0;

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          home: FocusPage(
            onOpenSettings: () {},
            onFocusEnded: () => focusEndedCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('完成专注'));
    await tester.tap(find.text('完成专注'));
    await tester.pumpAndSettle();
    expect(find.text('本次专注已记录'), findsOneWidget);

    await tester.tap(find.text('完成任务'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.taskById(task.id)!.isCompleted, isTrue);
    expect(controller.activeFocusSession, isNull);
    expect(focusEndedCount, 1);
    expect(find.text('先添加一个任务'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
  });
}

class _FailingPermissionGateway extends FocusPlatformGateway {
  const _FailingPermissionGateway();
  @override
  Future<bool> hasUsageAccess() async => false;
  @override
  Future<bool> hasOverlayPermission() async => false;
  @override
  Future<void> openUsageAccessSettings() async =>
      throw PlatformException(code: 'unavailable', message: '系统设置不可用');
}
