import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pactick/core/components/task_details_panel.dart';
import 'package:pactick/core/dialogs/plan_block_editor.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/calendar/pages/calendar_page.dart';

class _PlanStore extends MemoryDocumentStore {
  bool failPlanWrites = false;

  @override
  Future<void> putDocument(
    String entityType,
    String id,
    Map<String, Object?> body, {
    bool enqueue = true,
    String accountId = DocumentStore.localAccountId,
  }) async {
    if (entityType == 'plan_block' && failPlanWrites) {
      throw StateError('disk unavailable');
    }
    await super.putDocument(
      entityType,
      id,
      body,
      enqueue: enqueue,
      accountId: accountId,
    );
  }

  @override
  Future<void> deleteDocument(
    String entityType,
    String id, {
    bool enqueue = true,
    String accountId = DocumentStore.localAccountId,
  }) async {
    if (entityType == 'plan_block' && failPlanWrites) {
      throw StateError('disk unavailable');
    }
    await super.deleteDocument(
      entityType,
      id,
      enqueue: enqueue,
      accountId: accountId,
    );
  }
}

Future<AppController> _controller(_PlanStore store) async {
  final controller = AppController(
    repository: WorkspaceRepository(store),
    focusPlatform: const FocusPlatformGateway(),
  );
  await controller.initialize();
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));
  testWidgets(
    'new schedules list only open tasks, including when given an inactive initial task',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.reset);
      final controller = await _controller(_PlanStore());
      final open = await controller.createTask(title: '可排期待办');
      final completed = await controller.createTask(title: '已完成不可新增关联');
      final cancelled = await controller.createTask(title: '已取消不可新增关联');
      await controller.updateTask(
        completed.copyWith(status: TaskStatus.completed),
      );
      await controller.updateTask(
        cancelled.copyWith(status: TaskStatus.cancelled),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,

          home: Scaffold(
            body: PlanBlockEditor(
              controller: controller,
              initialTask: controller.taskById(cancelled.id),
            ),
          ),
        ),
      );
      final dropdown = tester.widget<DropdownButton<String?>>(
        find.byType(DropdownButton<String?>),
      );
      expect(dropdown.items!.map((item) => item.value), [null, open.id]);
      expect(dropdown.value, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final status in [TaskStatus.completed, TaskStatus.cancelled]) {
    testWidgets(
      'details for ${status.name} tasks disable new scheduling and keep existing plans editable',
      (tester) async {
        final controller = await _controller(_PlanStore());
        final task = await controller.createTask(title: '保留已有时段');
        await controller.scheduleTask(
          taskId: task.id,
          startsAt: DateTime.now().add(const Duration(days: 1)),
          duration: const Duration(minutes: 30),
        );
        await controller.updateTask(task.copyWith(status: status));
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,

            home: Scaffold(
              body: SingleChildScrollView(
                child: TaskDetailsPanel(
                  task: controller.taskById(task.id)!,
                  controller: controller,
                  onEdit: null,
                ),
              ),
            ),
          ),
        );
        expect(
          find.text(status == TaskStatus.completed ? '已完成' : '已取消'),
          findsOneWidget,
        );
        final addButton = tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text('安排时间'),
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          ),
        );
        expect(addButton.onPressed, isNull);
        expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'existing ${status.name} association remains editable without offering other inactive tasks',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 900);
        addTearDown(tester.view.reset);
        final controller = await _controller(_PlanStore());
        final task = await controller.createTask(title: '保留原关联');
        final other = await controller.createTask(title: '其他已取消任务');
        final block = await controller.scheduleTask(
          taskId: task.id,
          startsAt: DateTime.now().add(const Duration(days: 1)),
          duration: const Duration(minutes: 45),
        );
        await controller.updateTask(task.copyWith(status: status));
        await controller.updateTask(
          other.copyWith(status: TaskStatus.cancelled),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,

            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showPlanBlockEditor(
                    context,
                    controller: controller,
                    block: block,
                  ),
                  child: const Text('打开原时段'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开原时段'));
        await tester.pumpAndSettle();
        final dropdown = tester.widget<DropdownButton<String?>>(
          find.byType(DropdownButton<String?>),
        );
        expect(dropdown.items!.map((item) => item.value), [null, task.id]);
        expect(dropdown.value, task.id);
        await tester.enterText(
          find.byKey(const ValueKey('plan-duration-minutes')),
          '60',
        );
        await tester.tap(find.text('保存修改'));
        await tester.pumpAndSettle();
        expect(controller.planBlocks.single.taskId, task.id);
        expect(controller.planBlocks.single.durationSeconds, 3600);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'calendar unscheduled counters and panel exclude completed and cancelled tasks',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 1000);
      addTearDown(tester.view.reset);
      final controller = await _controller(_PlanStore());
      await controller.createTask(title: '待排期任务');
      final completed = await controller.createTask(title: '已完成任务');
      final cancelled = await controller.createTask(title: '已取消任务');
      await controller.updateTask(
        completed.copyWith(status: TaskStatus.completed),
      );
      await controller.updateTask(
        cancelled.copyWith(status: TaskStatus.cancelled),
      );
      await tester.pumpWidget(
        AppScope(
          controller: controller,
          child: MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: CalendarPage(onOpenSettings: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('未排期 · 1'), findsOneWidget);
      await tester.tap(find.text('未排期 · 1'));
      await tester.pumpAndSettle();
      expect(find.text('未排期任务 · 1'), findsWidgets);
      expect(find.text('已完成任务'), findsNothing);
      expect(find.text('已取消任务'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'editing keeps identity, history and sync ownership; deletion persists',
    () async {
      final controller = await _controller(_PlanStore());
      final task = await controller.createTask(title: '原任务');
      final target = await controller.createTask(title: '改关联任务');
      final start = DateTime.now().add(const Duration(days: 1));
      final block = await controller.scheduleTask(
        taskId: task.id,
        startsAt: start,
        duration: const Duration(minutes: 45),
      );
      final session = FocusSessionItem(
        id: 'history',
        taskId: task.id,
        planBlockId: block.id,
        plannedDurationSeconds: 2700,
        actualDurationSeconds: 900,
        startedDeviceId: 'history-device',
        startedAt: start.subtract(const Duration(days: 2)),
        endedAt: start
            .subtract(const Duration(days: 2))
            .add(const Duration(minutes: 15)),
        status: FocusSessionStatus.completed,
        timeZone: 'Asia/Shanghai',
      );
      await controller.repository.saveFocusSession(session);
      await controller.retryInitialization();
      final changed = await controller.updatePlanBlock(
        block: block,
        taskId: target.id,
        startsAt: start.add(const Duration(days: 1)),
        duration: const Duration(minutes: 90),
      );
      expect(changed.id, block.id);
      expect(changed.taskId, target.id);
      expect(changed.durationSeconds, 5400);
      expect(controller.planBlocks, hasLength(1));
      expect(controller.actualSecondsForTask(task.id), 900);
      expect(controller.actualSecondsForTask(target.id), 0);
      final detached = await controller.updatePlanBlock(
        block: changed,
        title: '独立安排',
        startsAt: changed.startsAt,
        duration: const Duration(minutes: 20),
      );
      expect(detached.taskId, isNull);
      expect(detached.title, '独立安排');
      await controller.deletePlanBlock(detached);
      await controller.retryInitialization();
      expect(controller.planBlocks, isEmpty);
      expect(controller.tasks, hasLength(2));
      expect(controller.focusSessions.single.planBlockId, block.id);
      expect(controller.actualSecondsForTask(task.id), 900);
    },
  );

  test(
    'write failures preserve saved schedule and invalid changes do not write',
    () async {
      final store = _PlanStore();
      final controller = await _controller(store);
      final start = DateTime.now().add(const Duration(days: 1));
      final block = await controller.scheduleTask(
        title: '原安排',
        startsAt: start,
        duration: const Duration(minutes: 30),
      );
      store.failPlanWrites = true;
      await expectLater(
        controller.updatePlanBlock(
          block: block,
          title: '失败改动',
          startsAt: start.add(const Duration(hours: 1)),
          duration: const Duration(minutes: 90),
        ),
        throwsStateError,
      );
      await expectLater(controller.deletePlanBlock(block), throwsStateError);
      expect(controller.planBlocks.single, same(block));
      store.failPlanWrites = false;
      await expectLater(
        controller.updatePlanBlock(
          block: block,
          title: '',
          startsAt: start,
          duration: const Duration(minutes: 30),
        ),
        throwsArgumentError,
      );
      await expectLater(
        controller.updatePlanBlock(
          block: block,
          taskId: 'missing',
          startsAt: start,
          duration: const Duration(minutes: 30),
        ),
        throwsStateError,
      );
      await expectLater(
        controller.updatePlanBlock(
          block: block,
          title: '无时长',
          startsAt: start,
          duration: Duration.zero,
        ),
        throwsArgumentError,
      );
      await controller.retryInitialization();
      expect(controller.planBlocks.single.startsAt, start);
      expect(controller.planBlocks.single.title, '原安排');
    },
  );

  testWidgets('existing plan edits duration in place and confirms deletion', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.reset);
    final controller = await _controller(_PlanStore());
    final task = await controller.createTask(title: '已安排任务');
    final block = await controller.scheduleTask(
      taskId: task.id,
      startsAt: DateTime.now().add(const Duration(days: 1)),
      duration: const Duration(minutes: 45),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,

        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPlanBlockEditor(
                context,
                controller: controller,
                block: controller.planBlocks.single,
              ),
              child: const Text('打开计划'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开计划'));
    await tester.pumpAndSettle();
    expect(find.text('编辑计划时段'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('plan-duration-minutes')),
      '75',
    );
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(controller.planBlocks.single.id, block.id);
    expect(controller.planBlocks.single.startsAt, block.startsAt);
    expect(controller.planBlocks.single.durationSeconds, 4500);
    await tester.tap(find.text('打开计划'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-plan-block')));
    await tester.pumpAndSettle();
    expect(find.text('删除计划时段？'), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(controller.planBlocks, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('delete-plan-block')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(controller.planBlocks, isEmpty);
    expect(controller.tasks.single.id, task.id);
    expect(tester.takeException(), isNull);
  });
}
