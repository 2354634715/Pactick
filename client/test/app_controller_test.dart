import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';

void main() {
  late AppController controller;
  late MemoryDocumentStore store;
  late RecordingFocusPlatformGateway focusPlatform;

  setUp(() async {
    store = MemoryDocumentStore();
    focusPlatform = RecordingFocusPlatformGateway();
    controller = AppController(
      repository: WorkspaceRepository(store),
      focusPlatform: focusPlatform,
    );
    await controller.initialize();
  });

  tearDown(() => controller.dispose());

  test('a new workspace starts without sample content', () {
    expect(controller.projects, isEmpty);
    expect(controller.tasks, isEmpty);
    expect(controller.planBlocks, isEmpty);
    expect(controller.focusSessions, isEmpty);
    expect(
      controller.focusPolicies.map((policy) => policy.name),
      unorderedEquals(const ['灵活专注', '深度守护']),
    );
    expect(controller.pendingOperations, 0);
    expect(controller.themePreference, ThemePreference.system);
    expect(controller.useDynamicColor, isFalse);
  });

  test('explicit appearance choices survive controller restarts', () async {
    final repository = WorkspaceRepository(store);
    await controller.setThemePreference(ThemePreference.dark);
    for (final dynamicColor in [true, false]) {
      await controller.setDynamicColor(dynamicColor);
      final restarted = AppController(
        repository: repository,
        focusPlatform: focusPlatform,
      );
      await restarted.initialize();
      expect(restarted.initializationError, isNull);
      expect(restarted.themePreference, ThemePreference.dark);
      expect(restarted.useDynamicColor, dynamicColor);
      restarted.dispose();
    }
  });

  test('an upgrade removes legacy sample content only', () async {
    final legacyStore = MemoryDocumentStore();
    const sampleProject = ProjectItem(
      id: '11111111-1111-4111-8111-111111111111',
      name: '产品规划',
      color: '#5367A5',
    );
    const sampleTask = TaskItem(
      id: '31111111-1111-4111-8111-111111111111',
      title: '旧版示例任务',
      projectId: '11111111-1111-4111-8111-111111111111',
      priority: TaskPriority.urgent,
      status: TaskStatus.open,
      rank: 10,
    );
    const userTask = TaskItem(
      id: 'user-task',
      title: '用户创建的任务',
      priority: TaskPriority.medium,
      status: TaskStatus.open,
      rank: 20,
    );
    await legacyStore.putDocument(
      'project',
      sampleProject.id,
      sampleProject.toBody(),
      enqueue: false,
    );
    await legacyStore.putDocument(
      'task',
      sampleTask.id,
      sampleTask.toBody(),
      enqueue: false,
    );
    await legacyStore.putDocument(
      'task',
      userTask.id,
      userTask.toBody(),
      enqueue: false,
    );

    final upgradedController = AppController(
      repository: WorkspaceRepository(legacyStore),
      focusPlatform: RecordingFocusPlatformGateway(),
    );
    await upgradedController.initialize();

    expect(upgradedController.projects, isEmpty);
    expect(upgradedController.tasks, hasLength(1));
    expect(upgradedController.tasks.single.id, userTask.id);
    expect(upgradedController.tasks.single.title, userTask.title);
    expect(upgradedController.pendingOperations, 0);
    upgradedController.dispose();
  });

  test('task edits are local-first and enter the pending queue', () async {
    final before = controller.tasks.length;
    final task = await controller.createTask(
      title: '验证离线写入',
      priority: TaskPriority.high,
      estimatedDurationSeconds: 30 * 60,
    );

    expect(controller.tasks, hasLength(before + 1));
    expect(controller.pendingOperations, greaterThan(0));
    expect(controller.syncPhase, SyncPhase.localOnly);
    expect(controller.syncStatusTitle, '未连接同步账户');

    await controller.toggleTask(task);
    expect(controller.taskById(task.id)!.isCompleted, isTrue);
  });

  test('a project can be created before assigning its first task', () async {
    final project = await controller.createProject(
      name: ' 新产品发布 ',
      color: '#5B67D8',
    );

    expect(project.name, '新产品发布');
    expect(controller.projects.single.id, project.id);
    expect(controller.projects.single.color, '#5B67D8');
    expect(controller.pendingOperations, 1);

    final task = await controller.createTask(
      title: '整理发布清单',
      projectId: project.id,
    );
    expect(controller.projectById(task.projectId)?.name, '新产品发布');
  });

  test(
    'task priority order survives edits, manual ranks and restarts',
    () async {
      final none = await controller.createTask(title: '未设优先级');
      final high = await controller.createTask(
        title: '高优先级第一项',
        priority: TaskPriority.high,
      );
      final low = await controller.createTask(
        title: '低优先级',
        priority: TaskPriority.low,
      );
      final urgent = await controller.createTask(
        title: '紧急优先级',
        priority: TaskPriority.urgent,
      );
      final medium = await controller.createTask(
        title: '中优先级',
        priority: TaskPriority.medium,
      );
      final otherHigh = await controller.createTask(
        title: '高优先级第二项',
        priority: TaskPriority.high,
      );
      expect(controller.tasks.map((task) => task.id), [
        urgent.id,
        high.id,
        otherHigh.id,
        medium.id,
        low.id,
        none.id,
      ]);
      expect(controller.taskById(none.id)!.rank, none.rank);
      expect(controller.taskById(urgent.id)!.rank, urgent.rank);

      await controller.updateTask(
        medium.copyWith(priority: TaskPriority.urgent),
      );
      await controller.reorderTasks([high, otherHigh], 0, 1);
      final expected = [
        urgent.id,
        medium.id,
        otherHigh.id,
        high.id,
        low.id,
        none.id,
      ];
      expect(controller.tasks.map((task) => task.id), expected);

      final restarted = AppController(
        repository: WorkspaceRepository(store),
        focusPlatform: focusPlatform,
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.initializationError, isNull);
      expect(restarted.tasks.map((task) => task.id), expected);
    },
  );

  test('Today keeps plan times and manual ranks ahead of priority', () async {
    final date = DateTime(2026, 10, 11);
    final low = await controller.createTask(
      title: '未排期低优先级',
      dueAt: date,
      priority: TaskPriority.low,
    );
    final urgent = await controller.createTask(
      title: '未排期紧急任务',
      dueAt: date,
      priority: TaskPriority.urgent,
    );
    final later = await controller.createTask(
      title: '稍后排期的紧急任务',
      priority: TaskPriority.urgent,
    );
    final earlier = await controller.createTask(
      title: '较早排期的低优先级任务',
      priority: TaskPriority.low,
    );
    await controller.scheduleTask(
      taskId: later.id,
      startsAt: date.add(const Duration(hours: 10)),
      duration: const Duration(minutes: 30),
    );
    await controller.scheduleTask(
      taskId: earlier.id,
      startsAt: date.add(const Duration(hours: 9)),
      duration: const Duration(minutes: 30),
    );
    expect(controller.tasksForDate(date).map((task) => task.id), [
      earlier.id,
      later.id,
      low.id,
      urgent.id,
    ]);
  });

  test('planned and actual time stay independent', () async {
    final task = await controller.createTask(title: '安排测试任务');
    final originalActual = controller.actualSecondsForTask(task.id);
    final start = DateTime.now().add(const Duration(days: 2));

    await controller.scheduleTask(
      taskId: task.id,
      startsAt: start,
      duration: const Duration(minutes: 75),
    );

    final block = controller.firstPlanForTask(task.id, start);
    expect(block?.durationSeconds, 75 * 60);
    expect(controller.actualSecondsForTask(task.id), originalActual);
  });

  test('only a successful server exchange can enter synced state', () async {
    expect(controller.pendingOperations, 0);
    expect(controller.syncPhase, SyncPhase.localOnly);
    expect(controller.devices, isEmpty);

    final completedAt = DateTime(2026, 8, 30, 18, 30);
    await controller.markSyncCompleted(
      completedAt: completedAt,
      serverDevices: [
        DeviceItem(
          id: 'server-device-id',
          name: '当前 Android 设备',
          platform: 'android',
          lastSeenAt: completedAt,
          isCurrent: true,
        ),
      ],
    );

    expect(controller.syncPhase, SyncPhase.synced);
    expect(controller.lastSuccessfulSyncAt, completedAt);
    expect(controller.devices.single.id, 'server-device-id');

    await controller.createTask(title: '服务端同步后的本地修改');
    expect(controller.syncPhase, SyncPhase.pending);
  });

  test('guard mode uses the whitelist for the selected task project', () async {
    const project = ProjectItem(
      id: 'test-project',
      name: '工作',
      color: '#5367A5',
    );
    const task = TaskItem(
      id: 'test-task',
      title: '项目任务',
      projectId: 'test-project',
      priority: TaskPriority.high,
      status: TaskStatus.open,
      rank: 10,
    );
    await store.putDocument(
      'project',
      project.id,
      project.toBody(),
      enqueue: false,
    );
    await store.putDocument('task', task.id, task.toBody(), enqueue: false);
    await controller.retryInitialization();

    final guardPolicy = controller.focusPolicies.firstWhere(
      (policy) => policy.mode == FocusPolicyMode.guard,
    );
    const workPackages = {'com.example.documents', 'com.example.browser'};
    const inboxPackages = {'com.example.notes'};

    await controller.setAppWhitelist(task.projectId, workPackages);
    await controller.setAppWhitelist(null, inboxPackages);
    expect(controller.pendingOperations, 0);
    await controller.startFocus(
      task: task,
      durationSeconds: 25 * 60,
      policy: guardPolicy,
    );

    expect(focusPlatform.allowedPackageNames, unorderedEquals(workPackages));
    expect(
      focusPlatform.taskTypeName,
      controller.projectById(task.projectId)!.name,
    );
    expect(focusPlatform.maxAppExits, guardPolicy.maxAppExits);

    final reloaded = AppController(
      repository: WorkspaceRepository(store),
      focusPlatform: RecordingFocusPlatformGateway(),
    );
    await reloaded.initialize();
    expect(
      reloaded.appWhitelistForProject(task.projectId),
      unorderedEquals(workPackages),
    );
    expect(
      reloaded.appWhitelistForProject(null),
      unorderedEquals(inboxPackages),
    );
    reloaded.dispose();
  });
}

class RecordingFocusPlatformGateway extends FocusPlatformGateway {
  List<String> allowedPackageNames = const [];
  String? taskTypeName;
  int? maxAppExits;

  @override
  Future<bool> hasUsageAccess() async => true;

  @override
  Future<bool> hasOverlayPermission() async => true;

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
    this.allowedPackageNames = allowedPackageNames;
    this.taskTypeName = taskTypeName;
    this.maxAppExits = maxAppExits;
  }

  @override
  Future<GuardActivityStats> getGuardActivityStats() async {
    return const GuardActivityStats(appExitCount: 0, interruptionCount: 0);
  }
}
