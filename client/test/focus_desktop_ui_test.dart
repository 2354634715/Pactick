import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/local/private_vault_crypto.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/focus/pages/focus_page.dart';
import 'package:pactick/features/focus/widgets/focus_desktop_controls.dart';
import 'package:pactick/features/tasks/pages/private_vault_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unsupported platforms omit the preference and open button', (
    tester,
  ) async {
    final app = _UiController(supported: false);
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            FocusDesktopSettingsTile(controller: app),
            OpenFocusDesktopButton(controller: app),
          ],
        ),
      ),
    );
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets('preference is initially off and saving it does not launch', (
    tester,
  ) async {
    final app = _UiController();
    await tester.pumpWidget(_host(FocusDesktopSettingsTile(controller: app)));
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(app.openCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets('failed saving retains the choice and provides a retry', (
    tester,
  ) async {
    final app = _UiController()..failSave = true;
    final pending = Completer<void>();
    app.pendingSave = pending.future;
    await tester.pumpWidget(_host(FocusDesktopSettingsTile(controller: app)));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.text('重试保存专注桌面设置'), findsOneWidget);
    app.failSave = false;
    await tester.tap(find.text('重试保存专注桌面设置'));
    await tester.pumpAndSettle();
    expect(app.focusDesktopEnabled, isTrue);
    expect(find.text('重试保存专注桌面设置'), findsNothing);
    expect(app.openCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets('platform configuration failures can be applied again', (
    tester,
  ) async {
    final app = _UiController()
      ..focusDesktopEnabled = true
      ..focusDesktopErrorMessage = '专注桌面设置未应用到系统，请重试。';
    await tester.pumpWidget(_host(FocusDesktopSettingsTile(controller: app)));
    expect(find.text('专注桌面设置未应用到系统，请重试。'), findsOneWidget);
    await tester.tap(find.text('重试应用专注桌面设置'));
    await tester.pumpAndSettle();
    expect(app.saveCount, 1);
    expect(app.focusDesktopEnabled, isTrue);
    expect(app.openCount, 0);
    expect(find.text('重试应用专注桌面设置'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets('English settings and open errors fit at 320 dp and 200% text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.reset);
    final app = _UiController()
      ..focusDesktopEnabled = true
      ..failOpen = true;
    await tester.pumpWidget(
      _host(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FocusDesktopSettingsTile(controller: app),
            OpenFocusDesktopButton(controller: app),
          ],
        ),
        locale: const Locale('en'),
        scale: 2,
      ),
    );
    expect(find.text('Focus desktop'), findsOneWidget);
    expect(find.textContaining('Off by default.'), findsOneWidget);
    final open = find.text('Open focus desktop');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.text('Retry opening focus desktop'), findsOneWidget);
    expect(find.textContaining('Focus is still running.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    app.failOpen = false;
    await tester.ensureVisible(find.text('Retry opening focus desktop'));
    await tester.tap(find.text('Retry opening focus desktop'));
    await tester.pumpAndSettle();
    expect(find.text('Open focus desktop'), findsOneWidget);
    expect(app.openCount, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets('active focus offers the desktop and preserves the task title', (
    tester,
  ) async {
    final app = _UiController();
    await app.initialize();
    final task = await app.createTask(title: '用户标题保持中文');
    await app.startFocus(
      task: task,
      durationSeconds: 1500,
      policy: app.focusPolicies.first,
    );
    app.focusDesktopEnabled = true;
    app.openCount = 0;
    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: _host(
          FocusPage(onOpenSettings: () {}, onFocusEnded: () {}),
          locale: const Locale('en'),
          scrollable: false,
        ),
      ),
    );
    expect(find.text('用户标题保持中文'), findsOneWidget);
    await tester.ensureVisible(find.text('Open focus desktop'));
    await tester.tap(find.text('Open focus desktop'));
    await tester.pumpAndSettle();
    expect(app.openCount, 1);
    expect(app.activeFocusSession, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets('locked private focus opens the desktop without unlocking', (
    tester,
  ) async {
    final store = MemoryDocumentStore();
    final now = DateTime.now().toUtc();
    final envelope = await const PrivateVaultCrypto().encrypt(
      'encrypted UI fixture',
      key: SecretKeyData(List<int>.filled(32, 7)),
      salt: List<int>.filled(32, 3),
      runtime: {
        'session_id': 'private-focus-ui-test',
        'started_at': now.toIso8601String(),
        'ends_at': now.add(const Duration(minutes: 25)).toIso8601String(),
      },
    );
    await store.writePrivateVault(
      DocumentStore.localAccountId,
      envelope.encode(),
      expectedEnvelope: null,
      ownsFocusRuntime: true,
    );
    final app = _UiController(store: store);
    await app.initialize();
    app.focusDesktopEnabled = true;
    expect(app.privateVault.hasActiveFocus, isTrue);
    expect(app.privateVault.isUnlocked, isFalse);
    await tester.pumpWidget(
      _host(
        PrivateVaultPage(app: app),
        locale: const Locale('en'),
        scrollable: false,
      ),
    );
    await tester.ensureVisible(find.text('Open focus desktop'));
    await tester.tap(find.text('Open focus desktop'));
    await tester.pumpAndSettle();
    expect(app.openCount, 1);
    expect(app.privateVault.isUnlocked, isFalse);
    expect(app.privateVault.hasActiveFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
}

Widget _host(
  Widget child, {
  Locale? locale,
  double scale = 1,
  bool scrollable = true,
}) => MaterialApp(
  locale: locale ?? const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: scrollable
      ? Scaffold(body: SingleChildScrollView(child: child))
      : child,
);

class _UiController extends AppController {
  _UiController({bool supported = true, DocumentStore? store})
    : super(
        repository: WorkspaceRepository(store ?? MemoryDocumentStore()),
        focusPlatform: _UiGateway(supported),
      );

  int openCount = 0;
  int saveCount = 0;
  bool failSave = false;
  bool failOpen = false;
  Future<void>? pendingSave;

  @override
  Future<void> setFocusDesktopEnabled(bool value) async {
    saveCount++;
    await pendingSave;
    if (failSave) throw StateError('fixture save failure');
    focusDesktopEnabled = value;
    focusDesktopErrorMessage = null;
    notifyListeners();
  }

  @override
  Future<void> openFocusDesktop() async {
    openCount++;
    if (failOpen) throw StateError('fixture open failure');
    focusDesktopErrorMessage = null;
    notifyListeners();
  }
}

class _UiGateway extends FocusPlatformGateway {
  const _UiGateway(this.supported);
  final bool supported;

  @override
  bool get supportsFocusDesktop => supported;

  @override
  Future<void> configureFocusDesktop({required bool enabled}) async {}
}
