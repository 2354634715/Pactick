import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/app/theme/app_theme.dart';
import 'package:pactick/app/theme/app_tokens.dart';
import 'package:pactick/core/components/focus_clock.dart';
import 'package:pactick/core/components/section_header.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';

void main() {
  test('display headings retain platform controls and dynamic color roles', () {
    for (final brightness in Brightness.values) {
      final dynamic = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: brightness,
      );
      final theme = brightness == Brightness.light
          ? AppTheme.light(dynamic)
          : AppTheme.dark(dynamic);
      expect(theme.colorScheme, dynamic);
      expect(
        theme.textTheme.headlineLarge?.fontFamily,
        AppTypography.displayFamily,
      );
      expect(
        theme.textTheme.bodyMedium?.fontFamily,
        isNot(AppTypography.displayFamily),
      );
      expect(
        theme.textTheme.labelLarge?.fontFamily,
        isNot(AppTypography.displayFamily),
      );
      expect(
        theme.filledButtonTheme.style?.minimumSize?.resolve({})?.height,
        greaterThanOrEqualTo(48),
      );
    }
  });

  testWidgets('English section action remains reachable at 320dp and 2x text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    var activated = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SectionHeader(
                title: 'Scheduled for today',
                subtitle: 'Tasks and plans use their original titles.',
                action: OutlinedButton(
                  onPressed: () => activated = true,
                  child: const Text('Manage applications'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final action = find.widgetWithText(OutlinedButton, 'Manage applications');
    await tester.ensureVisible(action);
    await tester.tap(action);
    expect(activated, isTrue);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
  });

  testWidgets('focus clock wraps large English units within narrow content', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    final controller = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
    );
    await controller.initialize();
    final task = await controller.createTask(title: '用户输入 English task');
    await controller.startFocus(
      task: task,
      durationSeconds: 7200,
      policy: controller.focusPolicies.first,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: FocusClock(controller: controller, showRing: true),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(controller.taskById(task.id)?.title, '用户输入 English task');
    expect(
      tester.getSize(find.byType(LinearProgressIndicator)).width,
      lessThanOrEqualTo(288),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
