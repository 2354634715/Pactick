import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/dialogs/project_editor.dart';
import 'package:pactick/core/dialogs/plan_block_editor.dart';
import 'package:pactick/core/dialogs/task_editor.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/focus/dialogs/app_whitelist_editor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('SQLite persistence failures', () {
    late Directory directory;
    late LocalDatabase store;
    late Database database;
    late AppController controller;
    late _RecordingFocus gateway;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('pactick-write-test-');
      final databasePath = '${directory.path}/workspace.db';
      store = LocalDatabase(
        databasePath: databasePath,
        factory: databaseFactoryFfi,
      );
      gateway = _RecordingFocus();
      controller = AppController(
        repository: WorkspaceRepository(store),
        focusPlatform: gateway,
      );
      await controller.initialize();
      expect(controller.initializationError, isNull);
      // Sqflite shares the same opened file: query_only rejects actual writes.
      database = await databaseFactoryFfi.openDatabase(databasePath);
    });

    tearDown(() async {
      controller.dispose();
      await store.close();
      await directory.delete(recursive: true);
    });

    test('failed create and update leave no phantom task or outbox', () async {
      final task = await controller.createTask(title: '已保存');
      final beforeCount = controller.pendingOperations;
      var notifications = 0;
      controller.addListener(() => notifications++);
      await database.execute('PRAGMA query_only = ON');

      await expectLater(
        controller.createTask(title: '不会保存'),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        controller.updateTask(task.copyWith(title: '失败修改')),
        throwsA(isA<DatabaseException>()),
      );

      expect(controller.tasks.single.title, '已保存');
      expect((await store.readDocuments('task')).single.body['title'], '已保存');
      expect(await store.pendingOperationCount(), beforeCount);
      expect(controller.pendingOperations, beforeCount);
      expect(notifications, 0);

      await database.execute('PRAGMA query_only = OFF');
      await controller.updateTask(task.copyWith(title: '重试成功'));
      expect(controller.tasks.single.title, '重试成功');
      expect((await store.readDocuments('task')).single.body['title'], '重试成功');
    });

    test(
      'project, schedule, preferences and whitelist remain durable on failure',
      () async {
        final project = await controller.createProject(
          name: '已保存项目',
          color: '#5367A5',
        );
        await database.execute('PRAGMA query_only = ON');
        await expectLater(
          controller.createProject(name: '失败项目', color: '#5367A5'),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          controller.updateProject(project.copyWith(name: '失败改名')),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          controller.scheduleTask(
            title: '失败计划',
            startsAt: DateTime.now(),
            duration: const Duration(minutes: 15),
          ),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          controller.setThemePreference(ThemePreference.dark),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          controller.setDynamicColor(true),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          controller.setNotifications(false),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          controller.setAppWhitelist(null, {'com.example.private'}),
          throwsA(isA<DatabaseException>()),
        );
        expect(controller.projects.single.name, '已保存项目');
        expect(controller.planBlocks, isEmpty);
        expect(controller.themePreference, ThemePreference.system);
        expect(controller.useDynamicColor, isFalse);
        expect(controller.notificationsEnabled, isTrue);
        expect(controller.appWhitelistForProject(null), isEmpty);
      },
    );

    test('reorder rolls back all ranks when its second write fails', () async {
      final first = await controller.createTask(title: '第一项');
      final second = await controller.createTask(title: '第二项');
      await database.execute('''
        CREATE TEMP TRIGGER fail_rank BEFORE INSERT ON documents
        WHEN NEW.entity_type = 'task' AND NEW.entity_id = '${first.id}'
        BEGIN SELECT RAISE(ABORT, 'simulated second write failure'); END
      ''');
      await expectLater(
        controller.reorderTasks(controller.tasks, 0, 1),
        throwsA(isA<DatabaseException>()),
      );
      expect(controller.tasks.map((task) => task.id), [first.id, second.id]);
      expect(controller.tasks.map((task) => task.rank), [10, 20]);
      final saved = await store.readDocuments('task');
      expect(saved.singleWhere((task) => task.id == first.id).body['rank'], 10);
      expect(
        saved.singleWhere((task) => task.id == second.id).body['rank'],
        20,
      );
      await database.execute('DROP TRIGGER fail_rank');
      await controller.reorderTasks(controller.tasks, 0, 1);
      expect(controller.tasks.map((task) => task.id), [second.id, first.id]);
    });

    test(
      'failed focus writes never change the active session or native timer',
      () async {
        final task = await controller.createTask(title: '专注');
        final policy = controller.focusPolicies.first;
        await database.execute('PRAGMA query_only = ON');
        await expectLater(
          controller.startFocus(
            task: task,
            durationSeconds: 900,
            policy: policy,
          ),
          throwsA(isA<DatabaseException>()),
        );
        expect(controller.activeFocusSession, isNull);
        expect(gateway.starts, 0);
        await database.execute('PRAGMA query_only = OFF');
        await controller.startFocus(
          task: task,
          durationSeconds: 900,
          policy: policy,
        );
        final sessionId = controller.activeFocusSession!.id;
        await database.execute('PRAGMA query_only = ON');
        await expectLater(
          controller.pauseFocus(),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          controller.finishFocus(),
          throwsA(isA<DatabaseException>()),
        );
        expect(controller.activeFocusSession!.id, sessionId);
        expect(
          controller.activeFocusSession!.status,
          FocusSessionStatus.running,
        );
        expect(gateway.pauses, 0);
        expect(gateway.stops, 0);
        await database.execute('PRAGMA query_only = OFF');
        await controller.finishFocus();
        expect(gateway.stops, 1);
      },
    );

    for (final edit in [false, true]) {
      testWidgets(
        'task editor preserves inputs and retries a SQLite ${edit ? 'update' : 'create'}',
        (tester) async {
          final original = edit
              ? await tester.runAsync(() => controller.createTask(title: '原任务'))
              : null;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () => showTaskEditor(
                      context,
                      controller: controller,
                      task: original,
                    ),
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('打开'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextFormField).first, '保留的输入');
          await tester.runAsync(
            () => database.execute('PRAGMA query_only = ON'),
          );
          await tester.runAsync(() async {
            await tester.tap(find.text('保存任务'));
            await Future<void>.delayed(const Duration(milliseconds: 200));
          });
          await tester.pumpAndSettle();
          expect(find.textContaining('保存失败'), findsOneWidget);
          expect(find.textContaining('存储当前不可写'), findsOneWidget);
          expect(find.text('保留的输入'), findsOneWidget);
          final button = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, '保存任务'),
          );
          expect(button.onPressed, isNotNull);
          expect(controller.tasks, hasLength(edit ? 1 : 0));
          if (edit) expect(controller.tasks.single.title, '原任务');
          expect(tester.takeException(), isNull);
          await tester.runAsync(
            () => database.execute('PRAGMA query_only = OFF'),
          );
          await tester.runAsync(() async {
            await tester.tap(find.text('保存任务'));
            await Future<void>.delayed(const Duration(milliseconds: 200));
          });
          await tester.pumpAndSettle();
          expect(find.byType(TaskEditor), findsNothing);
          expect(controller.tasks.single.title, '保留的输入');
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    for (final editor in ['项目', '计划', '白名单']) {
      testWidgets(
        '$editor editor restores its submit button after a failed write',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () {
                      switch (editor) {
                        case '项目':
                          showProjectEditor(context, controller: controller);
                        case '计划':
                          showPlanBlockEditor(context, controller: controller);
                        case '白名单':
                          showAppWhitelistEditor(
                            context,
                            controller: controller,
                            projectId: null,
                          );
                      }
                    },
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('打开'));
          await tester.pumpAndSettle();
          if (editor != '白名单') {
            await tester.enterText(find.byType(TextFormField), '保留输入');
          }
          final submit = editor == '项目'
              ? '创建项目'
              : editor == '计划'
              ? '加入日历'
              : '保存白名单';
          await tester.runAsync(
            () => database.execute('PRAGMA query_only = ON'),
          );
          await tester.runAsync(() async {
            await tester.tap(find.widgetWithText(FilledButton, submit));
            await Future<void>.delayed(const Duration(milliseconds: 200));
          });
          await tester.pumpAndSettle();
          expect(find.textContaining('保存失败'), findsOneWidget);
          expect(find.textContaining('存储当前不可写'), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, submit))
                .onPressed,
            isNotNull,
          );
          expect(controller.projects, isEmpty);
          expect(controller.planBlocks, isEmpty);
          expect(controller.appWhitelistForProject(null), isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  });

  test('concurrent failed opens share one attempt, and controller retry opens again', () async {
    final factory = _RetryFactory();
    final store = LocalDatabase(
      databasePath: inMemoryDatabasePath,
      factory: factory,
    );
    final controller = AppController(
      repository: WorkspaceRepository(store),
      focusPlatform: _RecordingFocus(),
    );
    final initialize = controller.initialize();
    final secondRead = store.listWorkspaceIds();
    final secondFailure = expectLater(secondRead, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(factory.attempts, 1);
    factory.firstAttempt.complete();
    await initialize;
    await secondFailure;
    expect(controller.initializationError, isA<StateError>());
    await controller.retryInitialization();
    expect(factory.attempts, 2);
    expect(controller.initializationError, isNull);
    expect(controller.isReady, isTrue);
    controller.dispose();
    await store.close();
  });
}

class _RetryFactory implements DatabaseFactory {
  final firstAttempt = Completer<void>();
  int attempts = 0;

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    attempts++;
    if (attempts == 1) {
      await firstAttempt.future;
      throw StateError('first open failed');
    }
    return databaseFactoryFfi.openDatabase(path, options: options);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}

class _RecordingFocus extends FocusPlatformGateway {
  int starts = 0;
  int pauses = 0;
  int stops = 0;

  @override
  Future<void> startTimer({
    String? sessionId,
    required String title,
    required DateTime endsAt,
    required FocusPolicyMode mode,
    List<String> allowedPackageNames = const [],
    String taskTypeName = '收集箱',
    int? maxAppExits,
    bool paused = false,
    int appExitCount = 0,
    int interruptionCount = 0,
  }) async {
    starts++;
  }

  @override
  Future<void> pauseTimer() async {
    pauses++;
  }

  @override
  Future<void> stopTimer() async {
    stops++;
  }
}
