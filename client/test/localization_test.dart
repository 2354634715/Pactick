import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pactick/app/navigation/app_destination.dart';
import 'package:pactick/app/pactick_app.dart';
import 'package:pactick/core/dialogs/task_editor.dart';
import 'package:pactick/core/localization/app_localizations.dart';
import 'package:pactick/core/localization/english.dart';
import 'package:pactick/core/localization/language_preference.dart';
import 'package:pactick/core/models/default_focus_policies.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/core/state/session_controller.dart';
import 'package:pactick/core/state/session_scope.dart';
import 'package:pactick/core/utilities/formatters.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/auth/pages/login_page.dart';
import 'package:pactick/features/settings/pages/settings_page.dart';
import 'package:pactick/features/tasks/pages/private_vault_page.dart';
import 'package:pactick/features/tasks/pages/tasks_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
    await initializeDateFormatting('en');
  });
  setUp(() => AppLocalizations.languageCode = 'zh');
  tearDown(() => AppLocalizations.languageCode = 'zh');

  test('every static UI message has an English translation', () {
    final missing = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.contains('localization')) {
        continue;
      }
      for (final key in _staticMessageKeys(file.readAsStringSync())) {
        if (!englishTranslations.containsKey(key)) {
          missing.add('${file.path}: $key');
        }
      }
    }
    expect(missing, isEmpty);
    expect(englishTranslations.length, greaterThan(700));
    for (final source in englishTranslations.keys) {
      expect(
        _placeholders(source),
        _placeholders(englishTranslations[source]!),
      );
      expect(englishTranslations[source]!.trim(), isNotEmpty);
      expect(
        RegExp(r'[\u4e00-\u9fff]').hasMatch(englishTranslations[source]!),
        isFalse,
        reason: source,
      );
    }
  });

  test('placeholder values are not translated or recursively substituted', () {
    AppLocalizations.languageCode = 'en';
    expect(
      tr('关联任务：{arg0}', args: {'arg0': '任务 {arg1}'}),
      'Linked task: 任务 {arg1}',
    );
    expect(tr('{arg0} 项任务', args: {'arg0': 3}), '3 tasks');
    expect(tr('missing message'), 'missing message');
    expect(AppDestination.tasks.label, 'Tasks');
    for (final destination in AppDestination.values) {
      expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(destination.label), isFalse);
    }
    for (final policy in defaultFocusPolicies) {
      expect(policy.displayName, isNot(policy.name));
      expect(policy.toBody()['name'], policy.name);
    }
    final custom = defaultFocusPolicies.first.toBody()..['name'] = '用户策略';
    expect(
      FocusPolicyItem.fromDocument(
        defaultFocusPolicies.first.id,
        custom,
      ).displayName,
      '用户策略',
    );
  });

  test(
    'Chinese variants and unsupported system languages resolve consistently',
    () {
      expect(
        resolveAppLocale(const Locale('zh', 'HK')),
        const Locale('zh', 'CN'),
      );
      expect(
        resolveAppLocale(const Locale('zh', 'TW')),
        const Locale('zh', 'CN'),
      );
      expect(resolveAppLocale(const Locale('en', 'GB')), const Locale('en'));
      expect(resolveAppLocale(const Locale('fr', 'FR')), const Locale('en'));
      expect(resolveAppLocale(null), const Locale('en'));
      expect(LanguagePreference.parse('unknown'), LanguagePreference.system);
      expect(LanguagePreference.system.locale, isNull);
    },
  );

  test(
    'dates, weekdays, relative dates, and compact durations follow language',
    () {
      final date = DateTime(2026, 10, 27, 14, 5);
      expect(formatMonthDay(date), '10月27日');
      expect(formatShortWeekday(date), '周二');
      expect(formatDuration(5400, compact: true), '1小时30分');
      expect(formatRelativeDate(date, date), '今天');
      AppLocalizations.languageCode = 'en';
      expect(formatMonthDay(date), 'Oct 27');
      expect(formatShortWeekday(date), 'Tue');
      expect(formatFullDate(date), 'Tuesday, Oct 27');
      expect(formatDuration(5400, compact: true), '1h 30m');
      expect(formatDuration(3600, compact: true), '1h');
      expect(formatDuration(60, compact: true), '1m');
      expect(formatClock(date), '14:05');
      expect(formatDuration(5400), '01:30:00');
      expect(formatRelativeDate(date, date), 'Today');
      expect(
        formatRelativeDate(date.subtract(const Duration(days: 1)), date),
        'Yesterday',
      );
      expect(
        formatRelativeDate(date.add(const Duration(days: 1)), date),
        'Tomorrow',
      );
    },
  );

  for (final sqlite in [false, true]) {
    test(
      '${sqlite ? 'SQLite' : 'memory'} language survives restart and workspace changes',
      () async {
        final directory = sqlite
            ? await Directory.systemTemp.createTemp('pactick-locale-')
            : null;
        final databasePath = directory == null
            ? null
            : '${directory.path}/workspace.db';
        DocumentStore store = sqlite
            ? LocalDatabase(
                databasePath: databasePath!,
                factory: databaseFactoryFfi,
              )
            : MemoryDocumentStore();
        var controller = _controller(store);
        try {
          await controller.initialize();
          expect(controller.initializationError, isNull);
          expect(controller.languagePreference, LanguagePreference.system);
          await controller.createTask(title: '保留中文用户标题');
          await controller.setLanguagePreference(LanguagePreference.english);
          expect(
            await controller.repository.readGlobalSetting(
              'language_preference',
            ),
            'english',
          );
          await controller.connectSyncAccount(
            userId: 'other-account',
            deviceId: 'other-device',
            offline: true,
          );
          expect(controller.languagePreference, LanguagePreference.english);
          await controller.openOfflineWorkspace(DocumentStore.localAccountId);
          expect(controller.languagePreference, LanguagePreference.english);
          expect(controller.tasks.single.title, '保留中文用户标题');
          controller.dispose();
          if (store is LocalDatabase) {
            await store.close();
            store = LocalDatabase(
              databasePath: databasePath!,
              factory: databaseFactoryFfi,
            );
          }
          controller = _controller(store);
          await controller.initialize();
          expect(controller.initializationError, isNull);
          expect(controller.languagePreference, LanguagePreference.english);
          expect(controller.tasks.single.title, '保留中文用户标题');
          await controller.setLanguagePreference(LanguagePreference.system);
          expect(
            await controller.repository.readGlobalSetting(
              'language_preference',
            ),
            'system',
          );
        } finally {
          controller.dispose();
          if (store is LocalDatabase) await store.close();
          if (directory != null) await directory.delete(recursive: true);
        }
      },
    );
  }

  test(
    'failed preference write leaves the selected language unchanged',
    () async {
      final store = _FailingPreferenceStore();
      final controller = _controller(store);
      await controller.initialize();
      addTearDown(controller.dispose);
      await controller.setLanguagePreference(LanguagePreference.chinese);
      store.failLanguageWrite = true;
      await expectLater(
        controller.setLanguagePreference(LanguagePreference.english),
        throwsStateError,
      );
      expect(controller.languagePreference, LanguagePreference.chinese);
      expect(
        await controller.repository.readGlobalSetting('language_preference'),
        'chinese',
      );
    },
  );

  testWidgets('English main destinations fit a narrow window with large text', (
    tester,
  ) async {
    final app = await _mountApp(tester, LanguagePreference.english, scale: 1.5);
    try {
      await app.controller.createTask(title: '用户中文标题保留');
      await tester.pumpAndSettle();
      expect(find.text("Today's schedule"), findsOneWidget);
      final labels = tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .destinations
          .cast<NavigationDestination>()
          .map((destination) => destination.label)
          .toList();
      expect(
        labels,
        unorderedEquals(['Today', 'Tasks', 'Calendar', 'Focus', 'Statistics']),
      );
      for (var index = 0; index < labels.length; index++) {
        expect(find.text(labels[index]), findsWidgets);
        await tester.tap(find.byType(NavigationDestination).at(index));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          index,
        );
        expect(tester.takeException(), isNull, reason: labels[index]);
      }
      await tester.tap(_navigationDestination(AppDestination.tasks.label));
      await tester.pumpAndSettle();
      expect(find.text('用户中文标题保留'), findsWidgets);
    } finally {
      await app.unmount(tester);
    }
  });

  testWidgets(
    'system locale changes refresh navigation, formatting, and labels without losing tasks',
    (tester) async {
      final app = await _mountApp(tester, LanguagePreference.system);
      try {
        final task = await app.controller.createTask(title: '系统语言变化后保留中文任务');
        await tester.pumpAndSettle();
        await tester.tap(_navigationDestination(AppDestination.tasks.label));
        await tester.pumpAndSettle();

        void expectLanguage({required bool chinese}) {
          // MaterialApp.locale is null when following the system. Read the
          // resolved locale inherited by a real page instead of the input.
          final locale = Localizations.localeOf(
            tester.element(find.byType(TasksPage)),
          );
          expect(
            locale,
            chinese ? const Locale('zh', 'CN') : const Locale('en'),
          );
          final navigation = tester.widget<NavigationBar>(
            find.byType(NavigationBar),
          );
          expect(_selectedDestination(tester), chinese ? '任务' : 'Tasks');
          expect(
            navigation.destinations.cast<NavigationDestination>().map(
              (item) => item.label,
            ),
            contains(chinese ? '今日' : 'Today'),
          );
          expect(find.text(chinese ? '今日' : 'Today'), findsWidgets);
          expect(AppDestination.tasks.label, chinese ? '任务' : 'Tasks');
          expect(TaskPriority.high.label, chinese ? '高' : 'High');
          expect(
            formatShortWeekday(DateTime(2026, 10, 27)),
            chinese ? '周二' : 'Tue',
          );
          expect(find.text('系统语言变化后保留中文任务'), findsWidgets);
          expect(app.controller.taskById(task.id)!.title, '系统语言变化后保留中文任务');
          expect(tester.takeException(), isNull);
        }

        expectLanguage(chinese: false);
        tester.platformDispatcher.localesTestValue = const [Locale('zh', 'HK')];
        await tester.pumpAndSettle();
        expectLanguage(chinese: true);
        tester.platformDispatcher.localesTestValue = const [Locale('fr')];
        await tester.pumpAndSettle();
        expectLanguage(chinese: false);

        await app.controller.setLanguagePreference(LanguagePreference.chinese);
        await tester.pumpAndSettle();
        expectLanguage(chinese: true);
        tester.platformDispatcher.localesTestValue = const [Locale('en')];
        await tester.pumpAndSettle();
        expectLanguage(chinese: true);
        expect(app.controller.languagePreference, LanguagePreference.chinese);
      } finally {
        await app.unmount(tester);
      }
    },
  );

  testWidgets(
    'language changes update the open settings route and retain task state',
    (tester) async {
      final app = await _mountApp(tester, LanguagePreference.chinese);
      final controller = app.controller;
      try {
        final task = await controller.createTask(title: '不会翻译的任务');
        await tester.pumpAndSettle();
        await tester.tap(_navigationDestination(AppDestination.tasks.label));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('设置').first);
        await tester.pumpAndSettle();
        final route = ModalRoute.of(tester.element(find.byType(SettingsPage)));
        await tester.tap(find.widgetWithText(ChoiceChip, 'English'));
        await tester.pumpAndSettle();
        expect(controller.languagePreference, LanguagePreference.english);
        expect(find.text('Appearance'), findsOneWidget);
        expect(find.text('Language'), findsOneWidget);
        expect(
          ModalRoute.of(tester.element(find.byType(SettingsPage))),
          same(route),
        );
        await tester.tap(find.widgetWithText(ChoiceChip, '简体中文'));
        await tester.pumpAndSettle();
        expect(find.text('外观'), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, '跟随系统').first);
        await tester.pumpAndSettle();
        expect(controller.languagePreference, LanguagePreference.system);
        expect(find.text('Appearance'), findsOneWidget);
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
        expect(_selectedDestination(tester), AppDestination.tasks.label);
        expect(find.text('不会翻译的任务'), findsWidgets);
        expect(controller.taskById(task.id)!.title, '不会翻译的任务');
        expect(tester.takeException(), isNull);
      } finally {
        await app.unmount(tester);
      }
    },
  );

  testWidgets(
    'English free focus links a task without translating user content',
    (tester) async {
      final app = await _mountApp(tester, LanguagePreference.english);
      try {
        final task = await app.controller.createTask(title: '用户中文关联目标');
        await tester.pumpAndSettle();
        await tester.tap(_navigationDestination(AppDestination.focus.label));
        await tester.pumpAndSettle();
        expect(
          find.text('Start now and link a task after focusing'),
          findsOneWidget,
        );
        expect(find.text('Free focus (no task yet)'), findsOneWidget);
        await tester.ensureVisible(find.text('Start focus'));
        await tester.tap(find.text('Start focus'));
        await tester.pumpAndSettle();
        expect(app.controller.activeFocusSession!.taskId, isNull);
        expect(find.text('Free focus'), findsOneWidget);
        await tester.ensureVisible(find.text('Complete focus'));
        await tester.tap(find.text('Complete focus'));
        await tester.pumpAndSettle();
        final original = app.controller.focusSessions.single;
        final total = app.controller
            .statisticsForLastDays(1)
            .single
            .actualDurationSeconds;
        expect(find.text('Skip linking'), findsOneWidget);
        await tester.ensureVisible(find.text('Linked task').last);
        await tester.tap(find.text('Linked task').last);
        await tester.pumpAndSettle();
        expect(find.text('Save link'), findsOneWidget);
        await tester.tap(find.byType(DropdownButtonFormField<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text(task.title).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save link'));
        await tester.pumpAndSettle();
        final associated = app.controller.focusSessions.single;
        expect(associated.toBody(), {...original.toBody(), 'task_id': task.id});
        expect(app.controller.taskById(task.id)!.title, task.title);
        expect(app.controller.taskById(task.id)!.status, TaskStatus.open);
        expect(
          app.controller.statisticsForLastDays(1).single.actualDurationSeconds,
          total,
        );
        expect(find.text(task.title), findsWidgets);
        expect(tester.takeException(), isNull);
      } finally {
        await app.unmount(tester);
      }
    },
  );

  testWidgets('task editor, private vault, and login show English controls', (
    tester,
  ) async {
    final app = await _mountApp(tester, LanguagePreference.english);
    try {
      await tester.tap(_navigationDestination(AppDestination.tasks.label));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(TasksPage));
      unawaited(showTaskEditor(context, controller: app.controller));
      await tester.pumpAndSettle();
      expect(find.text('New task'), findsWidgets);
      expect(find.text('Task title'), findsOneWidget);
      expect(find.text('Save task'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(TaskEditor))).pop();
      await tester.pumpAndSettle();
      unawaited(showPrivateVault(context));
      await tester.pumpAndSettle();
      expect(find.text('Private vault'), findsOneWidget);
      expect(find.text('Set password'), findsOneWidget);
      expect(find.text('Confirm password'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(PrivateVaultPage))).pop();
      await tester.pumpAndSettle();
      unawaited(
        Navigator.of(context)
            .push<void>(MaterialPageRoute(builder: (_) => const LoginPage())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Server HTTPS URL'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Copy and upload current local data'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await app.unmount(tester);
    }
  });
}

Finder _navigationDestination(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

String _selectedDestination(WidgetTester tester) {
  final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
  return (navigation.destinations[navigation.selectedIndex]
          as NavigationDestination)
      .label;
}

AppController _controller(DocumentStore store) => AppController(
  repository: WorkspaceRepository(store),
  focusPlatform: const FocusPlatformGateway(),
);

Future<_MountedApp> _mountApp(
  WidgetTester tester,
  LanguagePreference language, {
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  tester.platformDispatcher.localesTestValue = const [Locale('en')];
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final controller = _controller(MemoryDocumentStore());
  await controller.initialize();
  await controller.setLanguagePreference(language);
  final session = await createAuthenticatedSessionController();
  final mounted = _MountedApp(controller, session);
  addTearDown(mounted.disposeControllers);
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: SessionScope(controller: session, child: const PactickApp()),
    ),
  );
  await tester.pumpAndSettle();
  return mounted;
}

class _MountedApp {
  _MountedApp(this.controller, this.session);

  final AppController controller;
  final SessionController session;
  bool _disposed = false;

  void disposeControllers() {
    if (_disposed) return;
    _disposed = true;
    session.dispose();
    controller.dispose();
  }

  Future<void> unmount(WidgetTester tester) async {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      // Flutter checks pending timers before addTearDown runs. Cancel session
      // refresh and controller timers inside the test body's finally block.
      disposeControllers();
    }
    await tester.pump();
  }
}

Set<String> _placeholders(String value) =>
    RegExp(r'\{(\w+)\}').allMatches(value).map((match) => match[1]!).toSet();

/// Read only literal first arguments to tr(). This avoids a dependency on the
/// analyzer in the production client and understands escaped Dart strings.
Iterable<String> _staticMessageKeys(String source) sync* {
  for (final match in RegExp(r'\btr\(\s*').allMatches(source)) {
    var offset = match.end;
    if (offset >= source.length || !['\u0027', '"'].contains(source[offset])) {
      continue;
    }
    final quote = source[offset++];
    final value = StringBuffer();
    while (offset < source.length) {
      var character = source[offset++];
      if (character == quote) break;
      if (character == r'\' && offset < source.length) {
        character = source[offset++];
        value.write(switch (character) {
          'n' => '\n',
          'r' => '\r',
          't' => '\t',
          _ => character,
        });
      } else {
        value.write(character);
      }
    }
    yield value.toString();
  }
}

class _FailingPreferenceStore extends MemoryDocumentStore {
  bool failLanguageWrite = false;

  @override
  Future<void> writeSetting(
    String key,
    String value, {
    String accountId = DocumentStore.localAccountId,
  }) async {
    if (key == 'language_preference' && failLanguageWrite) {
      throw StateError('test write rejected');
    }
    await super.writeSetting(key, value, accountId: accountId);
  }
}
