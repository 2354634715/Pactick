import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/app/pactick_app.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/core/state/session_controller.dart';
import 'package:pactick/core/state/session_scope.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/calendar/pages/calendar_page.dart';
import 'package:pactick/features/focus/pages/focus_page.dart';
import 'package:pactick/features/statistics/pages/statistics_page.dart';
import 'package:pactick/features/tasks/pages/tasks_page.dart';
import 'package:pactick/features/today/pages/today_page.dart';

import 'support/session_test_support.dart';

void main() {
  testWidgets(
    'Android bottom destinations put Focus first and open each page',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);
      final (controller, sessionController) = await _pumpApp(tester);

      final navigation = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(
        navigation.destinations.cast<NavigationDestination>().map(
          (destination) => destination.label,
        ),
        ['专注', '今日', '任务', '日历', '统计'],
      );
      expect(navigation.selectedIndex, 1);
      expect(find.byType(TodayPage), findsOneWidget);

      final pages = [
        ('专注', FocusPage),
        ('今日', TodayPage),
        ('任务', TasksPage),
        ('日历', CalendarPage),
        ('统计', StatisticsPage),
      ];
      for (var index = 0; index < pages.length; index++) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(pages[index].$1),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(pages[index].$2), findsOneWidget);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          index,
        );
        expect(tester.takeException(), isNull);
      }

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('专注'),
        ),
      );
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(800, 915);
      await tester.pumpAndSettle();
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 3);
      expect(find.byType(FocusPage), findsOneWidget);
      tester.view.physicalSize = const Size(412, 915);
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(find.byType(FocusPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      sessionController.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'desktop compact navigation keeps the existing destination order',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);
      final (controller, sessionController) = await _pumpApp(tester);

      final navigation = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(
        navigation.destinations.cast<NavigationDestination>().map(
          (destination) => destination.label,
        ),
        ['今日', '任务', '日历', '专注', '统计'],
      );
      expect(navigation.selectedIndex, 0);
      expect(find.byType(TodayPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      sessionController.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Future<(AppController, SessionController)> _pumpApp(WidgetTester tester) async {
  final controller = AppController(
    repository: WorkspaceRepository(MemoryDocumentStore()),
    focusPlatform: const FocusPlatformGateway(),
  );
  await controller.initialize();
  final sessionController = await createAuthenticatedSessionController();
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: SessionScope(
        controller: sessionController,
        child: const PactickApp(automaticallyCheckForUpdates: false),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (controller, sessionController);
}
