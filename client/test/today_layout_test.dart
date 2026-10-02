import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pactick/app/theme/app_theme.dart';
import 'package:pactick/core/components/task_card.dart';
import 'package:pactick/core/components/task_details_panel.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/today/pages/today_page.dart';

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));
  for (final width in [320.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Today task list remains usable at $width and scale $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 915);
        addTearDown(tester.view.reset);
        final controller = AppController(
          repository: WorkspaceRepository(MemoryDocumentStore()),
          focusPlatform: const FocusPlatformGateway(),
        );
        await controller.initialize();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          AppScope(
            controller: controller,
            child: MaterialApp(
              theme: AppTheme.dark(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: TodayPage(
                onOpenSettings: () {},
                onOpenCalendar: () {},
                onOpenFocus: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(controller.tasks, isEmpty);
        const title = '整理今天的工作记录并为明天的学习和项目开发安排时间';
        await controller.createTask(
          title: title,
          dueAt: DateTime.now(),
          tags: ['一个需要查看完整内容的较长标签', '第二个标签', '第三个标签'],
        );
        await tester.pumpAndSettle();
        final scrollable = find
            .descendant(
              of: find.byKey(const PageStorageKey('today-list')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text(title),
          200,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(TaskCard), findsOneWidget);
        expect(find.text(title), findsOneWidget);
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(find.byType(TaskDetailsPanel), findsOneWidget);
        expect(find.text('任务详情'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
