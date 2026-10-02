import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/app/pactick_app.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/core/state/session_scope.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/settings/pages/settings_page.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('compact layout exposes the five primary destinations', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    final controller = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
    );
    await controller.initialize();
    final sessionController = await createAuthenticatedSessionController(
      onAuthenticationChanged: (authenticated, offline) {
        if (authenticated) controller.connectSyncAccount(offline: offline);
      },
    );

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

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('今日'), findsWidgets);
    expect(find.text('任务'), findsWidgets);
    expect(find.text('日历'), findsWidgets);
    expect(find.text('专注'), findsWidgets);
    expect(find.text('统计'), findsWidgets);
    expect(find.text('今日安排'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
    sessionController.dispose();
  });

  testWidgets('settings shows the signed-in account before first sync', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    final controller = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
    );
    await controller.initialize();
    final sessionController = await createAuthenticatedSessionController(
      onAuthenticationChanged: (authenticated, offline) {
        if (authenticated) controller.connectSyncAccount(offline: offline);
      },
    );

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: SessionScope(
          controller: sessionController,
          child: MaterialApp(home: SettingsPage(onClose: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('等待首次同步'), findsOneWidget);
    expect(find.text('已连接账户，等待首次同步'), findsOneWidget);
    expect(find.text('林默'), findsOneWidget);
    expect(find.text('lin@example.com'), findsOneWidget);
    expect(find.text('测试 Android 设备'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('同步完成'), findsNothing);
    expect(find.text('当前设备已读取最新游标'), findsNothing);
    expect(find.text('工作电脑'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
    sessionController.dispose();
  });

  testWidgets('ending focus returns the adaptive shell to Today', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    final controller = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
    );
    await controller.initialize();
    final sessionController = await createAuthenticatedSessionController();
    final task = await controller.createTask(title: '返回今日页测试');
    await controller.startFocus(
      task: task,
      durationSeconds: 25 * 60,
      policy: controller.focusPolicies.first,
    );

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
    await tester.tap(find.byIcon(Icons.center_focus_strong_outlined));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('完成专注'));
    await tester.tap(find.text('完成专注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂不完成任务'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(find.text('今日安排'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
    sessionController.dispose();
  });
}
