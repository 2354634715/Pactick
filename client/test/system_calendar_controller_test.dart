import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/localization/app_localizations.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/settings/pages/system_calendar_settings.dart';

import 'support/system_calendar_fake.dart';

Future<AppController> createCalendarApp(FakeSystemCalendar provider) async {
  final app = AppController(
    repository: WorkspaceRepository(MemoryDocumentStore()),
    focusPlatform: const FocusPlatformGateway(),
    systemCalendarGateway: provider,
  );
  await app.initialize();
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('disabled integration never reads events and manual sync refreshes app data', () async {
    final provider = FakeSystemCalendar();
    final app = await createCalendarApp(provider);
    try {
      provider.add('系统原文');
      await app.scheduleTask(
        title: '客户端原文',
        startsAt: DateTime.now(),
        duration: const Duration(hours: 1),
      );
      expect(provider.reads, 0);
      await app.systemCalendar.configure(
        enabled: true,
        calendar: FakeSystemCalendar.calendar,
      );
      await app.systemCalendar.syncNow();
      expect(
        app.planBlocks.map((p) => p.title),
        containsAll(['系统原文', '客户端原文']),
      );
      expect(app.systemCalendar.lastResult!.imported, 1);
      expect(app.systemCalendar.lastResult!.exported, 1);
      expect(app.pendingOperations, greaterThan(0));
      await app.systemCalendar.configure(enabled: false);
      final reads = provider.reads;
      await app.systemCalendar.syncNow();
      expect(provider.reads, reads);
      expect(provider.events, hasLength(2));
      expect(app.planBlocks, hasLength(2));
    } finally {
      app.dispose();
      await provider.close();
    }
  });

  test(
    'editing waits for a cancelled provider read and preserves the user edit',
    () async {
      final provider = FakeSystemCalendar();
      final app = await createCalendarApp(provider);
      try {
        final eventId = provider.add('系统标题');
        await app.systemCalendar.configure(
          enabled: true,
          calendar: FakeSystemCalendar.calendar,
        );
        await app.systemCalendar.syncNow();
        final block = app.planBlocks.single;
        final started = Completer<void>();
        final release = Completer<void>();
        provider.beforeRead = () async {
          started.complete();
          await release.future;
        };
        final sync = app.systemCalendar.syncNow();
        await started.future;
        final edit = app.updatePlanBlock(
          block: block,
          title: '编辑中保留',
          startsAt: block.startsAt,
          duration: const Duration(hours: 1),
        );
        release.complete();
        await sync;
        await edit;
        expect(app.planBlocks.single.title, '编辑中保留');
        expect(provider.events[eventId]!['title'], '系统标题');
      } finally {
        app.dispose();
        await provider.close();
      }
    },
  );

  test('workspace switching waits for old calendar work and disables the new connection', () async {
    final provider = FakeSystemCalendar();
    final app = await createCalendarApp(provider);
    try {
      provider.add('旧工作区系统内容');
      await app.systemCalendar.configure(
        enabled: true,
        calendar: FakeSystemCalendar.calendar,
      );
      final started = Completer<void>();
      final release = Completer<void>();
      provider.beforeRead = () async {
        started.complete();
        await release.future;
      };
      final sync = app.systemCalendar.syncNow();
      await started.future;
      final switchWorkspace = app.openOfflineWorkspace('__local__:other');
      release.complete();
      await sync;
      await switchWorkspace;
      await Future<void>.delayed(Duration.zero);
      expect(app.repository.selectedAccountId, '__local__:other');
      expect(app.planBlocks, isEmpty);
      expect(app.systemCalendar.enabled, isFalse);
      expect(provider.writes, 0);
    } finally {
      app.dispose();
      await provider.close();
    }
  });

  test(
    'foreground observer imports external changes and stops while backgrounded',
    () async {
      final provider = FakeSystemCalendar();
      final app = await createCalendarApp(provider);
      try {
        await app.systemCalendar.requestAccess();
        await app.systemCalendar.configure(
          enabled: true,
          calendar: FakeSystemCalendar.calendar,
        );
        await app.systemCalendar.syncNow();
        provider.add('前台新日程');
        provider.changesController.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 2200));
        expect(app.planBlocks.single.title, '前台新日程');
        app.systemCalendar.setForeground(false);
        final reads = provider.reads;
        provider.add('后台新增');
        provider.changesController.add(null);
        await app.systemCalendar.syncNow();
        expect(provider.reads, reads);
        app.systemCalendar.setForeground(true);
        await app.systemCalendar.syncNow();
        expect(app.planBlocks.map((p) => p.title), contains('后台新增'));
      } finally {
        app.dispose();
        await provider.close();
      }
    },
  );

  test('granting write access resumes pending exports automatically', () async {
    final provider = FakeSystemCalendar(writeGranted: false)..denyWrites = true;
    final app = await createCalendarApp(provider);
    try {
      await app.scheduleTask(
        title: '等待写入权限',
        startsAt: DateTime.now(),
        duration: const Duration(hours: 1),
      );
      provider.add('读取仍可用');
      await app.systemCalendar.requestAccess(write: true);
      await app.systemCalendar.configure(
        enabled: true,
        calendar: FakeSystemCalendar.calendar,
      );
      await app.systemCalendar.syncNow();
      expect(app.planBlocks.map((p) => p.title), contains('读取仍可用'));
      expect(provider.writes, 0);
      provider.denyWrites = false;
      await app.systemCalendar.requestAccess(write: true);
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(provider.events.values.map((e) => e['title']), contains('等待写入权限'));
      expect(provider.writes, 1);
    } finally {
      app.dispose();
      await provider.close();
    }
  });

  for (final language in ['zh', 'en']) {
    testWidgets(
      '$language setup and conflict deletion fit large text and require consent',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        AppLocalizations.languageCode = language;
        final provider = FakeSystemCalendar(
          readGranted: false,
          writeGranted: false,
        );
        final app = await createCalendarApp(provider);
        try {
          final eventId = provider.add('日程标题不翻译');
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('en'), Locale('zh')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: SystemCalendarSettingsPage(app: app),
            ),
          );
          await tester.pumpAndSettle();
          expect(provider.reads, 0);
          final choose = language == 'en'
              ? 'Choose a system calendar'
              : '选择系统日历';
          await tester.tap(find.text(choose));
          await tester.pumpAndSettle();
          await tester.tap(find.text(FakeSystemCalendar.calendar.displayName));
          await tester.pumpAndSettle();
          expect(provider.reads, 0);
          expect(provider.writes, 0);
          final enable = language == 'en' ? 'Enable sync' : '启用同步';
          await tester.tap(find.text(enable));
          await tester.pumpAndSettle();
          expect(app.systemCalendar.enabled, isTrue);
          expect(provider.permissionRequests, 2);
          expect(app.planBlocks.single.title, '日程标题不翻译');
          provider.events.remove(eventId);
          await app.systemCalendar.syncNow();
          await tester.pumpAndSettle();
          final keepSystem = language == 'en'
              ? 'Keep system version'
              : '保留系统版本';
          await tester.scrollUntilVisible(
            find.text(keepSystem).hitTestable(),
            300,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(keepSystem).hitTestable());
          await tester.pumpAndSettle();
          expect(app.planBlocks, hasLength(1));
          await tester.tap(find.text(language == 'en' ? 'Cancel' : '取消'));
          await tester.pumpAndSettle();
          expect(app.planBlocks, hasLength(1));
          await tester.tap(find.text(keepSystem).hitTestable());
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(language == 'en' ? 'Confirm deletion' : '确认删除'),
          );
          await tester.pumpAndSettle();
          expect(app.planBlocks, isEmpty);
          expect(provider.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          app.dispose();
          await provider.close();
        }
      },
    );
  }
}
