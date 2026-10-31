import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/localization/language_preference.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/focus/pages/focus_page.dart';

void main() {
  testWidgets(
    'an empty workspace can start, pause, repeat and finish free focus',
    (tester) async {
      final controller = await _pumpFocus(tester);
      expect(controller.tasks, isEmpty);
      expect(find.text('自由专注（暂不关联任务）'), findsOneWidget);
      await _tapText(tester, '开始专注');
      expect(controller.activeFocusSession?.taskId, isNull);
      expect(controller.activeFocusSession?.status, FocusSessionStatus.running);
      expect(find.text('自由专注'), findsOneWidget);

      await _tapText(tester, '暂停');
      expect(controller.activeFocusSession?.status, FocusSessionStatus.paused);
      expect(find.text('专注已暂停'), findsOneWidget);
      await _tapText(tester, '继续');
      expect(controller.activeFocusSession?.status, FocusSessionStatus.running);
      await _tapText(tester, '完成专注');

      expect(controller.activeFocusSession, isNull);
      expect(
        controller.focusSessions.single.status,
        FocusSessionStatus.completed,
      );
      expect(controller.focusSessions.single.taskId, isNull);
      expect(find.text('本次专注已记录'), findsOneWidget);
      final completeTask = find.ancestor(
        of: find.text('完成任务'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(tester.widget<FilledButton>(completeTask).onPressed, isNull);
      final firstSession = controller.focusSessions.single;
      await _tapText(tester, '再专注一次');
      expect(controller.activeFocusSession?.taskId, isNull);
      expect(controller.activeFocusSession?.status, FocusSessionStatus.running);
      expect(controller.activeFocusSession?.id, isNot(firstSession.id));
      expect(
        controller.activeFocusSession?.plannedDurationSeconds,
        firstSession.plannedDurationSeconds,
      );
      expect(controller.focusSessions, hasLength(2));
      expect(controller.tasks, isEmpty);
      await _tapText(tester, '完成专注');
      await _tapText(tester, '暂不关联');
      expect(controller.focusSessions, hasLength(2));
      expect(
        controller.focusSessions.every(
          (session) =>
              session.taskId == null &&
              session.status == FocusSessionStatus.completed,
        ),
        isTrue,
      );
      expect(controller.tasks, isEmpty);
      expect(tester.takeException(), isNull);
      await _disposeFocus(tester, controller);
    },
  );

  testWidgets(
    'failed association keeps the selection and allows a safe retry',
    (tester) async {
      final store = _FailingAssociationStore();
      final controller = await _pumpFocus(tester, store: store);
      final task = await controller.createTask(title: '写入重试后关联的任务');
      await tester.pumpAndSettle();
      await _tapText(tester, '开始专注');
      _recordElapsedFocus(controller);
      await _tapText(tester, '完成专注');
      final original = controller.focusSessions.single.toBody();
      final sessionId = controller.focusSessions.single.id;
      await _tapAssociationButton(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(task.title).last);
      await tester.pumpAndSettle();

      final attemptsBefore = store.focusWriteAttempts;
      store.failNextFocusWrite = true;
      await _tapText(tester, '保存关联');
      expect(find.textContaining('关联未保存，请重试'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>).last,
            )
            .initialValue,
        task.id,
      );
      final saveButton = find.ancestor(
        of: find.text('保存关联'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
      expect(controller.focusSessions.single.toBody(), original);
      expect(
        (await store.readDocuments('focus_session')).single.body['task_id'],
        isNull,
      );

      await _tapText(tester, '保存关联');
      expect(store.focusWriteAttempts, attemptsBefore + 2);
      expect(find.textContaining('关联未保存，请重试'), findsNothing);
      expect(controller.focusSessions, hasLength(1));
      final associated = controller.focusSessions.single;
      expect(associated.id, sessionId);
      expect(associated.taskId, task.id);
      expect({...associated.toBody(), 'task_id': null}, original);
      final persisted = (await store.readDocuments('focus_session')).single;
      expect(persisted.id, sessionId);
      expect(persisted.body['task_id'], task.id);
      expect(controller.taskById(task.id)!.isCompleted, isFalse);
      await _tapText(tester, '暂不完成任务');
      expect(tester.takeException(), isNull);
      await _disposeFocus(tester, controller);
    },
  );

  testWidgets(
    'a task removed while selecting an association stays actionable',
    (tester) async {
      final store = MemoryDocumentStore();
      final controller = await _pumpFocus(tester, store: store);
      final task = await controller.createTask(title: '选择后被同步删除的任务');
      await tester.pumpAndSettle();
      await _tapText(tester, '开始专注');
      await _tapText(tester, '完成专注');
      await _tapAssociationButton(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(task.title).last);
      await tester.pumpAndSettle();

      await store.deleteDocument('task', task.id, enqueue: false);
      await controller.retryInitialization();
      await _tapText(tester, '保存关联');
      expect(find.textContaining('关联未保存，请重试'), findsOneWidget);
      expect(find.textContaining('还没有任务，可先新建任务'), findsOneWidget);
      expect(controller.focusSessions.single.taskId, isNull);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('暂不关联').last);
      await tester.pumpAndSettle();
      await _tapText(tester, '暂不关联');
      await _disposeFocus(tester, controller);
    },
  );

  testWidgets('review can create and associate a task without completing it', (
    tester,
  ) async {
    final controller = await _pumpFocus(tester);
    await _tapText(tester, '开始专注');
    _recordElapsedFocus(controller);
    await _tapText(tester, '完成专注');
    final original = controller.focusSessions.single.toBody();
    expect(
      controller.focusSessions.single.actualDurationSeconds,
      greaterThan(0),
    );

    await _tapAssociationButton(tester);
    expect(find.textContaining('还没有任务，可先新建任务'), findsOneWidget);
    await _tapText(tester, '新建任务');
    await tester.enterText(find.byType(TextFormField).first, '专注之后整理出的任务');
    await _tapText(tester, '保存任务');
    await _tapText(tester, '保存关联');

    final task = controller.tasks.single;
    final session = controller.focusSessions.single;
    expect(task.title, '专注之后整理出的任务');
    expect(task.isCompleted, isFalse);
    expect(session.taskId, task.id);
    expect({...session.toBody(), 'task_id': null}, original);
    expect(
      controller.actualSecondsForTask(task.id),
      session.actualDurationSeconds,
    );
    expect(find.text('本次专注已记录'), findsOneWidget);
    expect(find.text(task.title), findsOneWidget);
    await _tapText(tester, '暂不完成任务');
    expect(controller.taskById(task.id)!.isCompleted, isFalse);
    expect(tester.takeException(), isNull);
    await _disposeFocus(tester, controller);
  });

  testWidgets('history can associate free focus with an existing task later', (
    tester,
  ) async {
    final controller = await _pumpFocus(tester);
    final task = await controller.createTask(title: '稍后归属的已有任务');
    await tester.pumpAndSettle();
    await _tapText(tester, '开始专注');
    _recordElapsedFocus(controller);
    await _tapText(tester, '完成专注');
    final original = controller.focusSessions.single.toBody();
    await _tapText(tester, '暂不关联');
    await _tapText(tester, '历史');
    await _tapText(tester, '自由专注');
    await _tapText(tester, '关联任务');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(task.title).last);
    await tester.pumpAndSettle();
    await _tapText(tester, '保存关联');

    final session = controller.focusSessions.single;
    expect(session.taskId, task.id);
    expect({...session.toBody(), 'task_id': null}, original);
    expect(controller.taskById(task.id)!.isCompleted, isFalse);
    expect(find.text(task.title), findsOneWidget);
    expect(find.text('自由专注'), findsNothing);
    expect(tester.takeException(), isNull);
    await _disposeFocus(tester, controller);
  });

  testWidgets(
    'a selected task can be changed back to free focus before start',
    (tester) async {
      final controller = await _pumpFocus(tester);
      final task = await controller.createTask(title: '可选但不必关联的任务');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(task.title).last);
      await tester.pumpAndSettle();
      expect(find.text(task.title), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自由专注（暂不关联任务）').last);
      await tester.pumpAndSettle();
      await _tapText(tester, '开始专注');
      expect(controller.activeFocusSession?.taskId, isNull);
      expect(controller.activeFocusSession?.status, FocusSessionStatus.running);
      expect(find.text('自由专注'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _disposeFocus(tester, controller);
    },
  );

  testWidgets('guard free focus uses the inbox application whitelist', (
    tester,
  ) async {
    final gateway = _GuardGateway();
    final controller = await _pumpFocus(tester, gateway: gateway);
    await controller.setAppWhitelist(null, {'org.example.reader'});
    final project = await controller.createProject(
      name: '其他项目',
      color: '#123456',
    );
    await controller.setAppWhitelist(project.id, {'org.example.other'});
    await tester.pumpAndSettle();
    await _tapText(tester, '深度守护');
    expect(find.text('收集箱白名单'), findsOneWidget);
    await _tapText(tester, '开始专注');

    expect(controller.tasks, isEmpty);
    expect(controller.activeFocusSession?.taskId, isNull);
    expect(gateway.mode, FocusPolicyMode.guard);
    expect(gateway.title, '自由专注');
    expect(gateway.taskTypeName, '收集箱');
    expect(gateway.packages, ['org.example.reader']);
    expect(tester.takeException(), isNull);
    await _disposeFocus(tester, controller);
  });
}

Future<AppController> _pumpFocus(
  WidgetTester tester, {
  FocusPlatformGateway gateway = const FocusPlatformGateway(),
  MemoryDocumentStore? store,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 1000);
  addTearDown(tester.view.reset);
  final controller = AppController(
    repository: WorkspaceRepository(store ?? MemoryDocumentStore()),
    focusPlatform: gateway,
  );
  await controller.initialize();
  await controller.setLanguagePreference(LanguagePreference.chinese);
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: FocusPage(onOpenSettings: () {}, onFocusEnded: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _tapText(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapAssociationButton(WidgetTester tester) async {
  final button = find.ancestor(
    of: find.text('关联任务'),
    matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void _recordElapsedFocus(AppController controller) {
  final session = controller.activeFocusSession!;
  controller.focusSessions = [
    FocusSessionItem.fromDocument(session.id, {
      ...session.toBody(),
      'started_at': DateTime.now()
          .subtract(const Duration(seconds: 95))
          .toUtc()
          .toIso8601String(),
    }),
  ];
}

Future<void> _disposeFocus(
  WidgetTester tester,
  AppController controller,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
}

class _FailingAssociationStore extends MemoryDocumentStore {
  bool failNextFocusWrite = false;
  int focusWriteAttempts = 0;

  @override
  Future<void> putDocument(
    String entityType,
    String id,
    Map<String, Object?> body, {
    bool enqueue = true,
    String accountId = DocumentStore.localAccountId,
  }) async {
    if (entityType == 'focus_session') {
      focusWriteAttempts++;
      if (failNextFocusWrite) {
        failNextFocusWrite = false;
        throw StateError('模拟专注记录写入失败');
      }
    }
    await super.putDocument(
      entityType,
      id,
      body,
      enqueue: enqueue,
      accountId: accountId,
    );
  }
}

class _GuardGateway extends FocusPlatformGateway {
  FocusPolicyMode? mode;
  String? title;
  String? taskTypeName;
  List<String> packages = [];

  @override
  Future<bool> hasUsageAccess() async => true;

  @override
  Future<bool> hasOverlayPermission() async => true;

  @override
  Future<void> startTimer({
    String? sessionId,
    required String title,
    String? titleKey,
    required DateTime endsAt,
    required FocusPolicyMode mode,
    List<String> allowedPackageNames = const [],
    String? taskTypeName,
    String? taskTypeKey,
    int? maxAppExits,
    bool paused = false,
    bool focusDesktopEnabled = false,
    int appExitCount = 0,
    int interruptionCount = 0,
  }) async {
    this.title = title;
    this.mode = mode;
    this.taskTypeName = taskTypeName;
    packages = allowedPackageNames;
  }
}
