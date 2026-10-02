import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/app/pactick_app.dart';
import 'package:pactick/app/theme/app_theme.dart';
import 'package:pactick/core/components/active_focus_dock.dart';
import 'package:pactick/core/components/focus_clock.dart';
import 'package:pactick/core/dialogs/task_editor.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/core/state/session_controller.dart';
import 'package:pactick/core/state/session_scope.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/local/session_store.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/remote/api_client.dart';
import 'package:pactick/data/repositories/auth_repository.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';

const _capture = bool.fromEnvironment('captureGui');

void main() {
  setUpAll(() async {
    if (!_capture) return;
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      final loader = FontLoader('Roboto')
        ..addFont(font.readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  test('fixed and generated dynamic schemes keep essential text contrast', () {
    double ratio(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
    }

    for (final brightness in Brightness.values) {
      for (final seed in [null, Colors.green, Colors.amber, Colors.purple]) {
        final dynamic = seed == null
            ? null
            : ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
        final theme = brightness == Brightness.light
            ? AppTheme.light(dynamic)
            : AppTheme.dark(dynamic);
        final c = theme.colorScheme;
        for (final surface in [
          c.surface,
          c.surfaceContainerLowest,
          c.surfaceContainerLow,
          c.surfaceContainer,
          c.surfaceContainerHigh,
          c.surfaceContainerHighest,
        ]) {
          expect(ratio(c.onSurface, surface), greaterThanOrEqualTo(4.5));
          expect(ratio(c.onSurfaceVariant, surface), greaterThanOrEqualTo(4.5));
          if (dynamic == null) {
            expect(ratio(c.primary, surface), greaterThanOrEqualTo(4.5));
          }
        }
        expect(ratio(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
        for (final pair in [
          (c.onPrimaryContainer, c.primaryContainer),
          (c.onSecondary, c.secondary),
          (c.onSecondaryContainer, c.secondaryContainer),
          (c.onTertiary, c.tertiary),
          (c.onTertiaryContainer, c.tertiaryContainer),
          (c.onInverseSurface, c.inverseSurface),
          (c.inversePrimary, c.inverseSurface),
        ]) {
          expect(ratio(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
        }
        if (dynamic != null) {
          expect(c, dynamic);
        }
        expect(
          ratio(c.onErrorContainer, c.errorContainer),
          greaterThanOrEqualTo(4.5),
        );
        expect(theme.textTheme.headlineLarge?.letterSpacing, 0);
      }
    }
  });

  for (final scenario in [
    ('compact', const Size(412, 915), 1.0, ThemePreference.light, true),
    ('large-type', const Size(320, 800), 2.0, ThemePreference.dark, true),
    ('medium', const Size(700, 800), 1.0, ThemePreference.light, true),
    ('expanded', const Size(1100, 760), 1.0, ThemePreference.dark, true),
    ('large', const Size(1440, 900), 1.0, ThemePreference.light, true),
    ('landscape', const Size(915, 412), 1.0, ThemePreference.light, true),
    ('split', const Size(320, 480), 1.0, ThemePreference.light, true),
    ('empty', const Size(412, 915), 1.0, ThemePreference.light, false),
  ]) {
    testWidgets('all pages remain readable in ${scenario.$1}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.$2;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = AppController(
        repository: WorkspaceRepository(MemoryDocumentStore()),
        focusPlatform: const FocusPlatformGateway(),
      );
      await app.initialize();
      await app.setThemePreference(scenario.$4);
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      if (scenario.$5) {
        final project = await app.createProject(
          name: 'Pactick 客户端设计与交互检查',
          color: '#C28A2C',
        );
        final task = await app.createTask(
          title: '核对 Android 客户端长任务名称、离线数据与可恢复的编辑流程',
          dueAt: day,
          estimatedDurationSeconds: 45 * 60,
          tags: ['评审', '中文与 English 混排'],
        );
        await app.createTask(
          title: '整理排期和专注记录',
          projectId: project.id,
          dueAt: day,
        );
        await app.scheduleTask(
          taskId: task.id,
          startsAt: day.add(const Duration(hours: 9)),
          duration: const Duration(minutes: 45),
        );
        await app.scheduleTask(
          title: '晚间回顾',
          startsAt: day.add(const Duration(hours: 21)),
          duration: const Duration(minutes: 30),
        );
      }
      final session = SessionController(
        repository: AuthRepository(
          sessionStore: MemorySessionStore(),
          apiClient: ApiClient(baseUrl: ''),
        ),
      );
      await session.initialize(restore: false);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: AppScope(
            controller: app,
            child: SessionScope(
              controller: session,
              child: MediaQuery(
                data: MediaQueryData(
                  size: scenario.$2,
                  textScaler: TextScaler.linear(scenario.$3),
                  disableAnimations: true,
                ),
                child: const PactickApp(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['今日', '任务', '日历', '专注', '统计']) {
        await _select(tester, label);
        expect(
          tester.takeException(),
          isNull,
          reason: '${scenario.$1} / $label',
        );
        await _snapshot(tester, boundary, '${scenario.$1}-$label');
      }
      await tester.tap(find.byTooltip('设置').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${scenario.$1} / 设置');
      await _snapshot(tester, boundary, '${scenario.$1}-设置');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _select(tester, '任务');
      await tester.tap(find.text('新建任务').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _snapshot(tester, boundary, '${scenario.$1}-editor-task');
      await tester.tap(find.byTooltip('关闭').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.text('项目').first,
          matching: find.byType(ChoiceChip),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('新建项目'));
      await tester.tap(find.text('新建项目'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _snapshot(tester, boundary, '${scenario.$1}-editor-project');
      await tester.tap(find.byTooltip('关闭').last);
      await tester.pumpAndSettle();
      await _select(tester, '日历');
      await tester.tap(find.text('新建时段').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _snapshot(tester, boundary, '${scenario.$1}-editor-plan');
      await tester.tap(find.byTooltip('关闭').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('设置').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('同步设置'));
      await tester.tap(find.text('同步设置'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _snapshot(tester, boundary, '${scenario.$1}-login');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      if (scenario.$5) {
        await _select(tester, '专注');
        await app.startFocus(
          task: app.tasks.first,
          durationSeconds: 45 * 60,
          policy: app.focusPolicies.first,
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${scenario.$1} / active focus',
        );
        await _snapshot(tester, boundary, '${scenario.$1}-focus-running');
        await app.pauseFocus();
        await tester.pumpAndSettle();
        await _snapshot(tester, boundary, '${scenario.$1}-focus-paused');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
      session.dispose();
    });
  }

  testWidgets(
    'search and pages survive settings, resize and low-height keyboard',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 480);
      addTearDown(tester.view.reset);
      final app = AppController(
        repository: WorkspaceRepository(MemoryDocumentStore()),
        focusPlatform: const FocusPlatformGateway(),
      );
      await app.initialize();
      final task = await app.createTask(title: '保留搜索与编辑状态');
      final session = SessionController(
        repository: AuthRepository(
          sessionStore: MemorySessionStore(),
          apiClient: ApiClient(baseUrl: ''),
        ),
      );
      await session.initialize(restore: false);
      await tester.pumpWidget(
        AppScope(
          controller: app,
          child: SessionScope(controller: session, child: const PactickApp()),
        ),
      );
      await tester.pumpAndSettle();
      await _select(tester, '任务');
      await tester.enterText(find.byType(TextField), '保留');
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      await _select(tester, '今日');
      expect(
        tester
            .widget<EditableText>(
              find.byType(EditableText, skipOffstage: false).first,
            )
            .focusNode
            .hasFocus,
        isFalse,
      );
      await _select(tester, '任务');
      expect(
        tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
        '保留',
      );
      await tester.tap(find.byTooltip('设置').first);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
        '保留',
      );
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDrawer), findsOneWidget);
      expect(
        tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
        '保留',
      );
      tester.view.physicalSize = const Size(700, 800);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
        tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
        '保留',
      );
      tester.view.physicalSize = const Size(320, 480);
      await app.startFocus(
        task: task,
        durationSeconds: 1500,
        policy: app.focusPolicies.first,
      );
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(find.byType(ActiveFocusDock), findsNothing);
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SearchBar));
      showTaskEditor(context, controller: app);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final submit = find.text('保存任务');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      expect(submit.hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
      session.dispose();
    },
  );

  testWidgets('data subscribers ignore timer-only notifications', (
    tester,
  ) async {
    final app = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
    );
    await app.initialize();
    final task = await app.createTask(title: '订阅隔离');
    await app.startFocus(
      task: task,
      durationSeconds: 1500,
      policy: app.focusPolicies.first,
    );
    var builds = 0;
    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: AppDataBoundary(
          controller: app,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                AppScope.watchData(context);
                builds++;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    final before = builds;
    await tester.pump(const Duration(seconds: 3));
    expect(builds, before);
    await app.createTask(title: '新任务必须刷新');
    await tester.pump();
    expect(builds, greaterThan(before));
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets('guard dock respects the same pause rule as the focus page', (
    tester,
  ) async {
    final app = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
    );
    await app.initialize();
    final task = await app.createTask(title: '守护专注');
    final normal = app.focusPolicies.first;
    await app.startFocus(task: task, durationSeconds: 1500, policy: normal);
    final session = app.activeFocusSession!;
    final guard = app.focusPolicies.firstWhere((p) => !p.allowPause);
    app.focusSessions = [
      FocusSessionItem(
        id: session.id,
        taskId: task.id,
        focusPolicyId: guard.id,
        plannedDurationSeconds: 1500,
        startedAt: session.startedAt,
        startedDeviceId: session.startedDeviceId,
        status: FocusSessionStatus.running,
        timeZone: 'Asia/Shanghai',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ActiveFocusDock(controller: app, onOpen: () {}),
        ),
      ),
    );
    expect(canPauseActiveFocus(app), isFalse);
    expect(find.byTooltip('暂停专注'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
}

Future<void> _select(WidgetTester tester, String label) async {
  final nav = find.byType(NavigationBar).evaluate().isNotEmpty
      ? find.byType(NavigationBar)
      : find.byType(NavigationRail).evaluate().isNotEmpty
      ? find.byType(NavigationRail)
      : find.byType(NavigationDrawer);
  final target = find.descendant(of: nav, matching: find.text(label));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _snapshot(WidgetTester tester, GlobalKey key, String name) async {
  if (!_capture) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(
      const String.fromEnvironment(
        'captureGuiDirectory',
        defaultValue: '../output/flutter-gui-review',
      ),
    );
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
