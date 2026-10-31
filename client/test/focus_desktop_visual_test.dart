import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pactick/app/navigation/adaptive_app_shell.dart';
import 'package:pactick/app/theme/app_theme.dart';
import 'package:pactick/core/localization/app_localizations.dart';
import 'package:pactick/core/localization/language_preference.dart';
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

/// Product Flutter widgets with isolated sample data. These captures do not
/// contain or simulate the native Android focus desktop or device acceptance.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
    await initializeDateFormatting('en');
    if (!_capture) return;
    final bodyFont = File('C:/Windows/Fonts/msyh.ttc');
    expect(
      bodyFont.existsSync(),
      isTrue,
      reason: 'Review captures require the local test-only body font.',
    );
    await (FontLoader(
      'Roboto',
    )..addFont(bodyFont.readAsBytes().then(ByteData.sublistView))).load();
    await (FontLoader(
      'PactickDisplay',
    )..addFont(rootBundle.load('assets/fonts/NotoSerifSC.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  tearDown(() {
    AppLocalizations.languageCode = 'zh';
  });

  testWidgets('review English Today with the shared client design', (
    tester,
  ) async {
    final fixture = await _mount(
      tester,
      language: LanguagePreference.english,
      size: const Size(412, 915),
    );
    try {
      expect(find.text('Review the weekly plan'), findsWidgets);
      expect(find.text('Write meeting notes'), findsWidgets);
      expect(tester.takeException(), isNull);
      await _snapshot(tester, fixture.boundary, 'today-en-412');
    } finally {
      await fixture.unmount(tester);
    }
  }, skip: !_capture);

  testWidgets('review active Chinese focus with the desktop entry', (
    tester,
  ) async {
    final fixture = await _mount(
      tester,
      language: LanguagePreference.chinese,
      size: const Size(412, 915),
      startFocus: true,
    );
    try {
      final nav = find.byType(NavigationBar);
      await tester.tap(find.descendant(of: nav, matching: find.text('专注')));
      await tester.pumpAndSettle();
      expect(find.text('阅读一节书并整理笔记'), findsWidgets);
      expect(find.text('打开专注桌面'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _snapshot(tester, fixture.boundary, 'focus-zh-active-412');
    } finally {
      await fixture.unmount(tester);
    }
  }, skip: !_capture);

  for (final scenario in [
    ('settings-zh-320', LanguagePreference.chinese, 1.0, 900.0),
    ('settings-en-320', LanguagePreference.english, 1.0, 900.0),
    ('settings-en-large-type-320', LanguagePreference.english, 2.0, 1100.0),
  ]) {
    testWidgets('review desktop preference ${scenario.$1}', (tester) async {
      final fixture = await _mount(
        tester,
        language: scenario.$2,
        size: Size(320, scenario.$4),
        scale: scenario.$3,
      );
      try {
        final label = scenario.$2 == LanguagePreference.english
            ? 'Settings'
            : '设置';
        await tester.tap(find.byTooltip(label).first);
        await tester.pumpAndSettle();
        final preference = find.byKey(const ValueKey('focus-desktop-switch'));
        await Scrollable.ensureVisible(
          tester.element(preference),
          alignment: 0.12,
        );
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(preference).value, isFalse);
        expect(tester.takeException(), isNull);
        await _snapshot(tester, fixture.boundary, scenario.$1);
      } finally {
        await fixture.unmount(tester);
      }
    }, skip: !_capture);
  }
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  required LanguagePreference language,
  required Size size,
  double scale = 1,
  bool startFocus = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final app = AppController(
    repository: WorkspaceRepository(MemoryDocumentStore()),
    focusPlatform: const _ReviewFocusGateway(),
  );
  await app.initialize();
  await app.setLanguagePreference(language);
  final english = language == LanguagePreference.english;
  AppLocalizations.languageCode = english ? 'en' : 'zh';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final project = await app.createProject(
    name: english ? 'Personal study' : '个人学习',
    color: '#C28A2C',
  );
  final first = await app.createTask(
    title: english ? 'Review the weekly plan' : '阅读一节书并整理笔记',
    projectId: project.id,
    dueAt: today.add(const Duration(hours: 18)),
    estimatedDurationSeconds: 45 * 60,
    tags: [english ? 'Planning' : '阅读'],
  );
  final second = await app.createTask(
    title: english ? 'Write meeting notes' : '整理今天的计划',
    dueAt: today.add(const Duration(hours: 20)),
    estimatedDurationSeconds: 30 * 60,
  );
  await app.scheduleTask(
    taskId: first.id,
    startsAt: today.add(const Duration(hours: 9, minutes: 30)),
    duration: const Duration(minutes: 45),
  );
  await app.scheduleTask(
    taskId: second.id,
    startsAt: today.add(const Duration(hours: 14)),
    duration: const Duration(minutes: 30),
  );
  if (startFocus) {
    await app.setFocusDesktopEnabled(true);
    await app.startFocus(
      task: first,
      durationSeconds: 45 * 60,
      policy: app.focusPolicies.first,
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
  final fixture = _Fixture(app, session, boundary);
  try {
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: AppScope(
          controller: app,
          child: SessionScope(
            controller: session,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light().copyWith(
                platform: TargetPlatform.android,
              ),
              darkTheme: AppTheme.dark().copyWith(
                platform: TargetPlatform.android,
              ),
              themeMode: ThemeMode.light,
              locale: language.locale,
              supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: AppDataBoundary(
                controller: app,
                child: const AdaptiveAppShell(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fixture;
  } catch (_) {
    await fixture.unmount(tester);
    rethrow;
  }
}

Future<void> _snapshot(WidgetTester tester, GlobalKey key, String name) async {
  if (!_capture) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('../output/focus-desktop/screenshots');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

class _Fixture {
  _Fixture(this.app, this.session, this.boundary);
  final AppController app;
  final SessionController session;
  final GlobalKey boundary;

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    app.dispose();
    await tester.pump();
  }
}

class _ReviewFocusGateway extends FocusPlatformGateway {
  const _ReviewFocusGateway();

  @override
  bool get supportsFocusDesktop => true;

  @override
  Future<void> configureFocusDesktop({required bool enabled}) async {}

  @override
  Future<bool> openFocusDesktop({
    List<String> allowedPackageNames = const [],
  }) async => true;
}
