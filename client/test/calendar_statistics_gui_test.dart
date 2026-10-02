import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pactick/app/theme/app_theme.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/calendar/pages/calendar_page.dart';
import 'package:pactick/features/statistics/pages/statistics_page.dart';

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  testWidgets(
    'calendar exposes overnight, late, deadline and saved focus as separate records',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final task = await controller.createTask(
        title: '跨午夜的完整任务标题',
        dueAt: today.add(const Duration(hours: 21)),
      );
      final start = DateTime(today.year, today.month, today.day - 1, 23, 30);
      final end = today.add(const Duration(minutes: 30));
      await controller.scheduleTask(
        taskId: task.id,
        startsAt: start,
        duration: const Duration(hours: 1),
      );
      await controller.scheduleTask(
        title: '深夜计划仍可见',
        startsAt: today.add(const Duration(hours: 23)),
        duration: const Duration(minutes: 30),
      );
      await controller.repository.saveFocusSession(
        FocusSessionItem(
          id: 'overnight-focus',
          taskId: task.id,
          plannedDurationSeconds: 3600,
          actualDurationSeconds: 3600,
          startedAt: start,
          endedAt: end,
          startedDeviceId: 'another-device',
          status: FocusSessionStatus.completed,
          timeZone: 'Asia/Shanghai',
        ),
      );
      await controller.retryInitialization();
      await _show(
        tester,
        controller,
        CalendarPage(onOpenSettings: () {}),
        width: 390,
      );

      expect(find.text('00:00–00:30'), findsNWidgets(2));
      expect(find.text('23:00–23:30'), findsOneWidget);
      expect(find.text('21:00'), findsOneWidget);
      expect(find.text('已记录 1小时'), findsOneWidget);
      expect(find.text('时间重叠'), findsNWidgets(2));
      final firstTitle = find.text(task.title).first;
      await tester.ensureVisible(firstTitle);
      await tester.tap(firstTitle);
      await tester.pumpAndSettle();
      expect(find.text('日历记录详情'), findsOneWidget);
      expect(
        find.text('${_date(start)} 23:30 至 ${_date(end)} 00:30'),
        findsWidgets,
      );
      expect(find.text('议程仅显示与所选日期相交的时段，原始记录未拆分。'), findsOneWidget);
      expect(find.text('删除计划'), findsNothing);
      expect(controller.planBlocks.first.startsAt, start);
      expect(controller.planBlocks.first.endsAt, end);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cancelled plan association still excludes a task from global backlog',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      final now = DateTime.now();
      final linked = await controller.createTask(title: '已关联取消计划的任务');
      final unscheduled = await controller.createTask(title: '真正未排期的任务');
      final start = DateTime(now.year, now.month, now.day + 1, 9);
      await controller.repository.savePlanBlock(
        PlanBlockItem(
          id: 'cancelled-plan',
          taskId: linked.id,
          startsAt: start,
          endsAt: start.add(const Duration(hours: 1)),
          status: PlanBlockStatus.cancelled,
          timeZone: 'Asia/Shanghai',
        ),
      );
      await controller.retryInitialization();
      await _show(tester, controller, CalendarPage(onOpenSettings: () {}));
      await tester.tap(find.text('未排期 · 1'));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text(unscheduled.title)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text(linked.title)),
        findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('安排时间')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'failed calendar drop keeps its task and can retry without duplicate plans',
    (tester) async {
      final store = _PlanFailStore();
      final controller = await _controller(store);
      addTearDown(controller.dispose);
      final task = await controller.createTask(title: '拖拽失败后保留');
      await _show(
        tester,
        controller,
        CalendarPage(onOpenSettings: () {}),
        width: 1440,
      );
      store.rejectNextPlan = true;
      final target = tester.widget<DragTarget<TaskItem>>(
        find.byType(DragTarget<TaskItem>).first,
      );
      target.onAcceptWithDetails!(
        DragTargetDetails(data: task, offset: Offset.zero),
      );
      await tester.pumpAndSettle();
      expect(controller.planBlocks, isEmpty);
      expect(controller.tasks.single.id, task.id);
      expect(find.textContaining('任务已保留'), findsOneWidget);
      await tester.ensureVisible(find.text('重试排期'));
      await tester.tap(find.text('重试排期'));
      await tester.pumpAndSettle();
      expect(controller.planBlocks, hasLength(1));
      expect(controller.planBlocks.single.taskId, task.id);
      expect(find.textContaining('任务已保留'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'calendar month targets remain 48 dp at 320 dp and double text size',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await _show(
        tester,
        controller,
        CalendarPage(onOpenSettings: () {}),
        width: 320,
        scale: 2,
      );
      await tester.ensureVisible(find.text('月'));
      await tester.tap(find.text('月'));
      await tester.pumpAndSettle();
      final cells = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label?.endsWith('个计划时段，选择日期') == true,
      );
      expect(cells, findsNWidgets(42));
      for (final element in cells.evaluate()) {
        final box = element.renderObject! as RenderBox;
        expect(box.size.width, greaterThanOrEqualTo(48));
        expect(box.size.height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'empty statistics has no comparison graph or invented percentage',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await _show(
        tester,
        controller,
        StatisticsPage(onOpenSettings: () {}),
        width: 320,
        scale: 2,
      );
      expect(find.text('还没有统计记录'), findsOneWidget);
      expect(find.text('每日计划与实际'), findsNothing);
      expect(find.byType(FractionallySizedBox), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'actual-only statistics exposes exact range, saved values and no-plan explanation',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day, 1);
      await controller.repository.saveFocusSession(
        FocusSessionItem(
          id: 'saved-focus',
          plannedDurationSeconds: 1800,
          actualDurationSeconds: 1800,
          startedAt: start,
          endedAt: start.add(const Duration(minutes: 30)),
          startedDeviceId: 'other-device',
          status: FocusSessionStatus.completed,
          timeZone: 'Asia/Shanghai',
        ),
      );
      await controller.retryInitialization();
      final handle = tester.ensureSemantics();
      try {
        await _show(
          tester,
          controller,
          StatisticsPage(onOpenSettings: () {}),
          width: 390,
          scale: 2,
        );
        expect(
          find.textContaining(
            '${_date(DateTime(now.year, now.month, now.day - 6))} 至 ${_date(now)}',
          ),
          findsOneWidget,
        );
        expect(find.text('30 分钟'), findsOneWidget);
        final description = find.textContaining('本期没有计划时段，不计算');
        await tester.ensureVisible(description);
        await tester.pumpAndSettle();
        expect(description, findsOneWidget);
        expect(find.textContaining('%'), findsNothing);
        await tester.ensureVisible(find.text('30 分钟'));
        await tester.pumpAndSettle();
        final daily = find.bySemanticsLabel(
          '${_date(now)}，计划 0 分钟，已记录实际专注 30 分钟，完成 0 项任务',
        );
        expect(daily, findsOneWidget);
        await tester.ensureVisible(find.text('近 4 周'));
        await tester.tap(find.text('近 4 周'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            '${_date(DateTime(now.year, now.month, now.day - 27))} 至 ${_date(now)}',
          ),
          findsOneWidget,
        );
        expect(find.text('30 分钟'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        handle.dispose();
      }
    },
  );
}

Future<AppController> _controller([MemoryDocumentStore? store]) async {
  final controller = AppController(
    repository: WorkspaceRepository(store ?? MemoryDocumentStore()),
    focusPlatform: const FocusPlatformGateway(),
  );
  await controller.initialize();
  return controller;
}

Future<void> _show(
  WidgetTester tester,
  AppController controller,
  Widget page, {
  double width = 390,
  double height = 915,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _date(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class _PlanFailStore extends MemoryDocumentStore {
  bool rejectNextPlan = false;

  @override
  Future<void> putDocument(
    String entityType,
    String id,
    Map<String, Object?> body, {
    bool enqueue = true,
    String accountId = DocumentStore.localAccountId,
  }) async {
    if (entityType == 'plan_block' && rejectNextPlan) {
      rejectNextPlan = false;
      throw StateError('simulated write failure');
    }
    await super.putDocument(
      entityType,
      id,
      body,
      enqueue: enqueue,
      accountId: accountId,
    );
  }
}
