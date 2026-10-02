import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pactick/app/theme/app_theme.dart';
import 'package:pactick/core/components/task_card.dart';
import 'package:pactick/core/components/task_details_panel.dart';
import 'package:pactick/core/dialogs/task_editor.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/tasks/pages/tasks_page.dart';
import 'package:pactick/features/today/pages/today_page.dart';

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  Future<AppController> controllerFor(
    WidgetTester tester, {
    MemoryDocumentStore? store,
    Size size = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final controller = AppController(
      repository: WorkspaceRepository(store ?? MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
    );
    await controller.initialize();
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> showPage(
    WidgetTester tester,
    AppController controller,
    Widget page,
  ) async {
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(theme: AppTheme.light(), home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final today in [false, true]) {
    testWidgets(
      '${today ? 'Today' : 'Tasks'} undo restores status and retains later edits',
      (tester) async {
        final controller = await controllerFor(tester);
        final task = await controller.createTask(
          title: '完成后仍可编辑',
          dueAt: today ? DateTime.now() : null,
        );
        await showPage(
          tester,
          controller,
          today
              ? TodayPage(
                  onOpenSettings: () {},
                  onOpenCalendar: () {},
                  onOpenFocus: () {},
                )
              : TasksPage(onOpenSettings: () {}, onOpenFocus: () {}),
        );
        final scrollable = find
            .descendant(
              of: find.byKey(
                PageStorageKey(today ? 'today-list' : 'tasks-list'),
              ),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.byType(Checkbox),
          200,
          scrollable: scrollable,
        );
        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();
        expect(controller.taskById(task.id)!.isCompleted, isTrue);
        await controller.updateTask(
          controller
              .taskById(task.id)!
              .copyWith(
                title: '稍后修改的标题',
                note: '稍后写入的备注不能被撤销覆盖',
                tags: ['后来新增'],
              ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('撤销'));
        await tester.pumpAndSettle();
        final undone = controller.taskById(task.id)!;
        expect(undone.isCompleted, isFalse);
        expect(undone.completedAt, isNull);
        expect(undone.title, '稍后修改的标题');
        expect(undone.note, '稍后写入的备注不能被撤销覆盖');
        expect(undone.tags, ['后来新增']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('failed completion preserves task and exposes a working retry', (
    tester,
  ) async {
    final store = _FailingTaskStore();
    final controller = await controllerFor(tester, store: store);
    final task = await controller.createTask(title: '保存失败仍在列表');
    await showPage(
      tester,
      controller,
      TasksPage(onOpenSettings: () {}, onOpenFocus: () {}),
    );
    store.failTasks = true;
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(controller.taskById(task.id)!.isCompleted, isFalse);
    expect(find.text('保存失败仍在列表'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    store.failTasks = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(controller.taskById(task.id)!.isCompleted, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('narrow task details are read-only until explicit edit', (
    tester,
  ) async {
    final controller = await controllerFor(tester);
    await controller.createTask(title: '完整任务', note: '完整备注', tags: ['完整标签']);
    await showPage(
      tester,
      controller,
      TasksPage(onOpenSettings: () {}, onOpenFocus: () {}),
    );
    await tester.tap(find.text('完整任务'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailsPanel), findsOneWidget);
    expect(find.byType(TaskEditor), findsNothing);
    expect(find.text('完整备注'), findsOneWidget);
    await tester.ensureVisible(find.text('编辑任务'));
    await tester.tap(find.text('编辑任务'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'search and selected detail survive narrowing a two-pane window',
    (tester) async {
      final controller = await controllerFor(
        tester,
        size: const Size(1440, 900),
      );
      await controller.createTask(title: '保留选择');
      await controller.createTask(title: '其他任务');
      await showPage(
        tester,
        controller,
        TasksPage(onOpenSettings: () {}, onOpenFocus: () {}),
      );
      await tester.enterText(find.byType(TextField).first, '保留');
      await tester.pumpAndSettle();
      expect(find.byType(TaskCard), findsOneWidget);
      await tester.tap(find.text('保留选择'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailsPanel), findsOneWidget);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailsPanel), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '保留',
      );
      expect(find.byType(TaskCard), findsOneWidget);
      expect(find.text('查看选中任务详情'), findsOneWidget);
      await tester.tap(find.text('查看选中任务详情'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailsPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Today move-down changes rank without changing due dates', (
    tester,
  ) async {
    final controller = await controllerFor(tester, size: const Size(390, 915));
    final first = await controller.createTask(
      title: '第一项',
      dueAt: DateTime.now(),
    );
    final second = await controller.createTask(
      title: '第二项',
      dueAt: first.dueAt,
    );
    await showPage(
      tester,
      controller,
      TodayPage(
        onOpenSettings: () {},
        onOpenCalendar: () {},
        onOpenFocus: () {},
      ),
    );
    final more = find.byKey(ValueKey('today-more-${first.id}'));
    final scrollable = find
        .descendant(
          of: find.byKey(const PageStorageKey('today-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(more, 200, scrollable: scrollable);
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(find.text('下移'));
    await tester.pumpAndSettle();
    expect(controller.tasksForDate(first.dueAt!).map((task) => task.id), [
      second.id,
      first.id,
    ]);
    expect(controller.taskById(first.id)!.dueAt, first.dueAt);
    expect(controller.taskById(second.id)!.dueAt, second.dueAt);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FailingTaskStore extends MemoryDocumentStore {
  bool failTasks = false;

  @override
  Future<void> putDocument(
    String entityType,
    String id,
    Map<String, Object?> body, {
    bool enqueue = true,
    String accountId = DocumentStore.localAccountId,
  }) async {
    if (entityType == 'task' && failTasks) {
      throw StateError('simulated write failure');
    }
    return super.putDocument(
      entityType,
      id,
      body,
      enqueue: enqueue,
      accountId: accountId,
    );
  }
}
