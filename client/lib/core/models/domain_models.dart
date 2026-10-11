enum ThemePreference { system, light, dark }

enum SyncPhase { localOnly, synced, pending, syncing, offline, attention }

enum TaskPriority { none, low, medium, high, urgent }

extension TaskPriorityLabel on TaskPriority {
  String get label => switch (this) {
    TaskPriority.none => '无',
    TaskPriority.low => '低',
    TaskPriority.medium => '中',
    TaskPriority.high => '高',
    TaskPriority.urgent => '紧急',
  };
}

enum TaskStatus { open, completed, cancelled }

enum PlanBlockStatus { scheduled, completed, cancelled }

enum FocusPolicyMode { normal, guard, strict }

extension FocusPolicyModeLabel on FocusPolicyMode {
  String get label => switch (this) {
    FocusPolicyMode.normal => '普通模式',
    FocusPolicyMode.guard => '守护模式',
    FocusPolicyMode.strict => '严格模式',
  };
}

enum FocusSessionStatus { running, paused, completed, abandoned, interrupted }

class ProjectItem {
  const ProjectItem({
    required this.id,
    required this.name,
    required this.color,
    this.archived = false,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String color;
  final bool archived;
  final int sortOrder;

  factory ProjectItem.fromDocument(String id, Map<String, Object?> body) {
    return ProjectItem(
      id: id,
      name: body['name']! as String,
      color: body['color'] as String? ?? '#5367A5',
      archived: body['archived'] as bool? ?? false,
      sortOrder: body['sort_order'] as int? ?? 0,
    );
  }

  Map<String, Object?> toBody() => {
    'name': name,
    'color': color,
    'archived': archived,
    'sort_order': sortOrder,
  };

  ProjectItem copyWith({
    String? name,
    String? color,
    bool? archived,
    int? sortOrder,
  }) {
    return ProjectItem(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      archived: archived ?? this.archived,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.priority,
    required this.status,
    required this.rank,
    this.note,
    this.projectId,
    this.dueAt,
    this.estimatedDurationSeconds,
    this.completedAt,
    this.recurrenceRuleId,
    this.tags = const [],
  });

  final String id;
  final String title;
  final String? note;
  final String? projectId;
  final TaskPriority priority;
  final DateTime? dueAt;
  final int? estimatedDurationSeconds;
  final TaskStatus status;
  final DateTime? completedAt;
  final String? recurrenceRuleId;
  final double rank;
  final List<String> tags;

  bool get isCompleted => status == TaskStatus.completed;

  static int compareByPriority(TaskItem left, TaskItem right) {
    final priority = right.priority.index.compareTo(left.priority.index);
    if (priority != 0) return priority;
    final rank = left.rank.compareTo(right.rank);
    if (rank != 0) return rank;
    return left.id.compareTo(right.id);
  }

  factory TaskItem.fromDocument(String id, Map<String, Object?> body) {
    return TaskItem(
      id: id,
      title: body['title']! as String,
      note: body['note'] as String?,
      projectId: body['project_id'] as String?,
      priority: TaskPriority.values.byName(
        body['priority'] as String? ?? TaskPriority.none.name,
      ),
      dueAt: _dateTime(body['due_at']),
      estimatedDurationSeconds: body['estimated_duration_seconds'] as int?,
      status: TaskStatus.values.byName(
        body['status'] as String? ?? TaskStatus.open.name,
      ),
      completedAt: _dateTime(body['completed_at']),
      recurrenceRuleId: body['recurrence_rule_id'] as String?,
      rank: (body['rank'] as num?)?.toDouble() ?? 0,
      tags: (body['tags'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Map<String, Object?> toBody() => {
    'title': title,
    'note': note,
    'project_id': projectId,
    'priority': priority.name,
    'due_at': dueAt?.toUtc().toIso8601String(),
    'estimated_duration_seconds': estimatedDurationSeconds,
    'status': status.name,
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'recurrence_rule_id': recurrenceRuleId,
    'rank': rank,
    'tags': tags,
  };

  TaskItem copyWith({
    String? title,
    String? note,
    String? projectId,
    TaskPriority? priority,
    DateTime? dueAt,
    int? estimatedDurationSeconds,
    TaskStatus? status,
    DateTime? completedAt,
    String? recurrenceRuleId,
    double? rank,
    List<String>? tags,
    bool clearNote = false,
    bool clearProject = false,
    bool clearDueAt = false,
    bool clearEstimatedDuration = false,
    bool clearCompletedAt = false,
    bool clearRecurrence = false,
  }) {
    return TaskItem(
      id: id,
      title: title ?? this.title,
      note: clearNote ? null : note ?? this.note,
      projectId: clearProject ? null : projectId ?? this.projectId,
      priority: priority ?? this.priority,
      dueAt: clearDueAt ? null : dueAt ?? this.dueAt,
      estimatedDurationSeconds: clearEstimatedDuration
          ? null
          : estimatedDurationSeconds ?? this.estimatedDurationSeconds,
      status: status ?? this.status,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      recurrenceRuleId: clearRecurrence
          ? null
          : recurrenceRuleId ?? this.recurrenceRuleId,
      rank: rank ?? this.rank,
      tags: tags ?? this.tags,
    );
  }
}

class PlanBlockItem {
  const PlanBlockItem({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.timeZone,
    required this.status,
    this.taskId,
    this.title,
    this.originalPlanBlockId,
  });

  final String id;
  final String? taskId;
  final String? title;
  final DateTime startsAt;
  final DateTime endsAt;
  final String timeZone;
  final PlanBlockStatus status;
  final String? originalPlanBlockId;

  int get durationSeconds => endsAt.difference(startsAt).inSeconds;

  factory PlanBlockItem.fromDocument(String id, Map<String, Object?> body) {
    return PlanBlockItem(
      id: id,
      taskId: body['task_id'] as String?,
      title: body['title'] as String?,
      startsAt: DateTime.parse(body['starts_at']! as String).toLocal(),
      endsAt: DateTime.parse(body['ends_at']! as String).toLocal(),
      timeZone: body['time_zone'] as String? ?? 'Asia/Shanghai',
      status: PlanBlockStatus.values.byName(
        body['status'] as String? ?? PlanBlockStatus.scheduled.name,
      ),
      originalPlanBlockId: body['original_plan_block_id'] as String?,
    );
  }

  Map<String, Object?> toBody() => {
    'task_id': taskId,
    'title': title,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt.toUtc().toIso8601String(),
    'time_zone': timeZone,
    'status': status.name,
    'original_plan_block_id': originalPlanBlockId,
  };
}

class FocusPolicyItem {
  const FocusPolicyItem({
    required this.id,
    required this.name,
    required this.mode,
    required this.allowPause,
    required this.earlyExitMode,
    required this.notificationMode,
    this.earlyExitWaitSeconds,
    this.maxAppExits,
    this.allowedAppIds = const [],
    this.emergencyAppCategories = const ['phone', 'maps', 'authentication'],
  });

  final String id;
  final String name;
  final FocusPolicyMode mode;
  final bool allowPause;
  final String earlyExitMode;
  final int? earlyExitWaitSeconds;
  final int? maxAppExits;
  final List<String> allowedAppIds;
  final List<String> emergencyAppCategories;
  final String notificationMode;

  factory FocusPolicyItem.fromDocument(String id, Map<String, Object?> body) {
    return FocusPolicyItem(
      id: id,
      name: body['name']! as String,
      mode: FocusPolicyMode.values.byName(body['mode']! as String),
      allowPause: body['allow_pause'] as bool? ?? true,
      earlyExitMode: body['early_exit_mode'] as String? ?? 'allow',
      earlyExitWaitSeconds: body['early_exit_wait_seconds'] as int?,
      maxAppExits: body['max_app_exits'] as int?,
      allowedAppIds: (body['allowed_app_ids'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      emergencyAppCategories:
          (body['emergency_app_categories'] as List<Object?>? ?? const [])
              .whereType<String>()
              .toList(growable: false),
      notificationMode:
          body['notification_mode'] as String? ?? 'sound_and_vibrate',
    );
  }

  Map<String, Object?> toBody() => {
    'name': name,
    'mode': mode.name,
    'allow_pause': allowPause,
    'early_exit_mode': earlyExitMode,
    'early_exit_wait_seconds': earlyExitWaitSeconds,
    'max_app_exits': maxAppExits,
    'allowed_app_ids': allowedAppIds,
    'emergency_app_categories': emergencyAppCategories,
    'notification_mode': notificationMode,
  };
}

class FocusSessionItem {
  const FocusSessionItem({
    required this.id,
    required this.plannedDurationSeconds,
    required this.startedAt,
    required this.startedDeviceId,
    required this.status,
    required this.timeZone,
    this.taskId,
    this.planBlockId,
    this.focusPolicyId,
    this.endedAt,
    this.pauseStartedAt,
    this.pausedDurationSeconds = 0,
    this.actualDurationSeconds = 0,
    this.terminationReason,
    this.appExitCount = 0,
    this.interruptionCount = 0,
  });

  final String id;
  final String? taskId;
  final String? planBlockId;
  final String? focusPolicyId;
  final int plannedDurationSeconds;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime? pauseStartedAt;
  final int pausedDurationSeconds;
  final int actualDurationSeconds;
  final String startedDeviceId;
  final FocusSessionStatus status;
  final String? terminationReason;
  final String timeZone;
  final int appExitCount;
  final int interruptionCount;

  bool get isActive =>
      status == FocusSessionStatus.running ||
      status == FocusSessionStatus.paused;

  factory FocusSessionItem.fromDocument(String id, Map<String, Object?> body) {
    return FocusSessionItem(
      id: id,
      taskId: body['task_id'] as String?,
      planBlockId: body['plan_block_id'] as String?,
      focusPolicyId: body['focus_policy_id'] as String?,
      plannedDurationSeconds: body['planned_duration_seconds']! as int,
      startedAt: DateTime.parse(body['started_at']! as String).toLocal(),
      endedAt: _dateTime(body['ended_at'])?.toLocal(),
      pauseStartedAt: _dateTime(body['pause_started_at'])?.toLocal(),
      pausedDurationSeconds: body['paused_duration_seconds'] as int? ?? 0,
      actualDurationSeconds: body['actual_duration_seconds'] as int? ?? 0,
      startedDeviceId: body['started_device_id'] as String? ?? 'android-local',
      status: FocusSessionStatus.values.byName(body['status']! as String),
      terminationReason: body['termination_reason'] as String?,
      timeZone: body['time_zone'] as String? ?? 'Asia/Shanghai',
      appExitCount: body['app_exit_count'] as int? ?? 0,
      interruptionCount: body['interruption_count'] as int? ?? 0,
    );
  }

  Map<String, Object?> toBody() => {
    'task_id': taskId,
    'plan_block_id': planBlockId,
    'focus_policy_id': focusPolicyId,
    'planned_duration_seconds': plannedDurationSeconds,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt?.toUtc().toIso8601String(),
    'pause_started_at': pauseStartedAt?.toUtc().toIso8601String(),
    'pause_intervals': const <Object?>[],
    'paused_duration_seconds': pausedDurationSeconds,
    'actual_duration_seconds': actualDurationSeconds,
    'started_device_id': startedDeviceId,
    'status': status.name,
    'termination_reason': terminationReason,
    'time_zone': timeZone,
    'app_exit_count': appExitCount,
    'interruption_count': interruptionCount,
  };

  FocusSessionItem copyWith({
    DateTime? endedAt,
    DateTime? pauseStartedAt,
    int? pausedDurationSeconds,
    int? actualDurationSeconds,
    FocusSessionStatus? status,
    String? terminationReason,
    int? appExitCount,
    int? interruptionCount,
    bool clearEndedAt = false,
    bool clearPauseStartedAt = false,
  }) {
    return FocusSessionItem(
      id: id,
      taskId: taskId,
      planBlockId: planBlockId,
      focusPolicyId: focusPolicyId,
      plannedDurationSeconds: plannedDurationSeconds,
      startedAt: startedAt,
      endedAt: clearEndedAt ? null : endedAt ?? this.endedAt,
      pauseStartedAt: clearPauseStartedAt
          ? null
          : pauseStartedAt ?? this.pauseStartedAt,
      pausedDurationSeconds:
          pausedDurationSeconds ?? this.pausedDurationSeconds,
      actualDurationSeconds:
          actualDurationSeconds ?? this.actualDurationSeconds,
      startedDeviceId: startedDeviceId,
      status: status ?? this.status,
      terminationReason: terminationReason ?? this.terminationReason,
      timeZone: timeZone,
      appExitCount: appExitCount ?? this.appExitCount,
      interruptionCount: interruptionCount ?? this.interruptionCount,
    );
  }
}

class DeviceItem {
  const DeviceItem({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastSeenAt,
    this.isCurrent = false,
  });

  final String id;
  final String name;
  final String platform;
  final DateTime lastSeenAt;
  final bool isCurrent;
}

class DailyStatItem {
  const DailyStatItem({
    required this.date,
    required this.plannedDurationSeconds,
    required this.actualDurationSeconds,
    required this.completedTasks,
  });

  final DateTime date;
  final int plannedDurationSeconds;
  final int actualDurationSeconds;
  final int completedTasks;
}

DateTime? _dateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.parse(value);
}
