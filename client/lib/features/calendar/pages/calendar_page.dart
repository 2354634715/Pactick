import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/components/feature_page_scaffold.dart';
import '../../../core/components/sync_status_button.dart';
import '../../../core/dialogs/plan_block_editor.dart';
import '../../../core/dialogs/task_editor.dart';
import '../../../core/models/domain_models.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/state/app_scope.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/persistence_errors.dart';

enum _CalendarMode { day, week, month }

enum _EventKind { deadline, plan, focus }

class CalendarPage extends StatefulWidget {
  const CalendarPage({required this.onOpenSettings, super.key});
  final VoidCallback onOpenSettings;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  _CalendarMode _mode = _CalendarMode.week;
  DateTime _selectedDate = _day(DateTime.now());
  bool _showAllHours = false;
  bool _scheduling = false;
  String? _scheduleError;
  (TaskItem, DateTime)? _failedSchedule;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watchData(context);
    final plannedIds = controller.planBlocks
        .map((block) => block.taskId)
        .whereType<String>()
        .toSet();
    final unscheduled = controller.tasks
        .where((task) => !task.isCompleted && !plannedIds.contains(task.id))
        .toList(growable: false);
    final events = _eventsForDate(controller, _selectedDate);
    return FeaturePageScaffold(
      title: '日历',
      actions: [
        SyncStatusButton(
          phase: controller.syncPhase,
          pendingCount: controller.pendingOperations,
          onPressed: () => showSyncStatusPanel(
            context,
            controller: controller,
            onOpenSettings: widget.onOpenSettings,
          ),
        ),
        IconButton(
          tooltip: '设置',
          onPressed: widget.onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'calendar-create-plan',
        onPressed: _scheduling ? null : () => _newPlan(controller),
        icon: const Icon(Icons.add),
        label: const Text('新建时段'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final twoPane =
              constraints.maxWidth >= AppSizes.twoPaneMinWidth &&
              MediaQuery.sizeOf(context).height >= AppSizes.lowHeight;
          final agenda = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_mode == _CalendarMode.week)
                _WeekOverview(
                  selectedDate: _selectedDate,
                  controller: controller,
                  onSelected: _selectDate,
                  onDrop: (task, date) => _scheduleAt(controller, task, date),
                  busy: _scheduling,
                ),
              if (_mode == _CalendarMode.month)
                _MonthGrid(
                  selectedDate: _selectedDate,
                  controller: controller,
                  onSelected: _selectDate,
                ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                formatFullDate(_selectedDate),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              _DayAgenda(
                date: _selectedDate,
                events: events,
                showAllHours: _showAllHours,
                onShowAllHours: () =>
                    setState(() => _showAllHours = !_showAllHours),
                onOpen: (event) => _showEvent(controller, event),
                onCreate: (date) => _newPlan(controller, start: date),
                onDrop: (task, date) => _scheduleAt(controller, task, date),
                busy: _scheduling,
              ),
            ],
          );
          final panel = _UnscheduledPanel(
            tasks: unscheduled,
            busy: _scheduling,
            onSchedule: (task) => _newPlan(controller, task: task),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      '${_selectedDate.year} 年 ${_selectedDate.month} 月',
                    ),
                  ),
                  IconButton(
                    tooltip: '上一周期',
                    onPressed: () => _move(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  TextButton(
                    onPressed: () => _selectDate(DateTime.now()),
                    child: const Text('今天'),
                  ),
                  IconButton(
                    tooltip: '下一周期',
                    onPressed: () => _move(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<_CalendarMode>(
                    segments: const [
                      ButtonSegment(value: _CalendarMode.day, label: Text('日')),
                      ButtonSegment(
                        value: _CalendarMode.week,
                        label: Text('周'),
                      ),
                      ButtonSegment(
                        value: _CalendarMode.month,
                        label: Text('月'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (selection) =>
                        setState(() => _mode = selection.first),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showUnscheduled(controller),
                    icon: const Icon(Icons.inbox_outlined),
                    label: Text('未排期 · ${unscheduled.length}'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.xs,
                children: [
                  _EventLegend(kind: _EventKind.deadline),
                  _EventLegend(kind: _EventKind.plan),
                  _EventLegend(kind: _EventKind.focus),
                ],
              ),
              if (_scheduling) ...[
                const SizedBox(height: AppSpacing.md),
                const LinearProgressIndicator(semanticsLabel: '正在保存计划时段'),
              ],
              if (_scheduleError case final message?) ...[
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  liveRegion: true,
                  child: Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(AppRadii.small),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                          if (_failedSchedule case final failure?)
                            TextButton(
                              onPressed: _scheduling
                                  ? null
                                  : () => _scheduleAt(
                                      controller,
                                      failure.$1,
                                      failure.$2,
                                    ),
                              child: const Text('重试排期'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (twoPane)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Semantics(
                        container: true,
                        explicitChildNodes: true,
                        child: agenda,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    SizedBox(
                      width: AppSizes.sidePanel,
                      child: Semantics(
                        container: true,
                        explicitChildNodes: true,
                        child: panel,
                      ),
                    ),
                  ],
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSizes.compactContentMax,
                  ),
                  child: agenda,
                ),
            ],
          );
        },
      ),
    );
  }

  void _selectDate(DateTime date) => setState(() => _selectedDate = _day(date));

  void _move(int direction) {
    _selectDate(switch (_mode) {
      _CalendarMode.day => DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day + direction,
      ),
      _CalendarMode.week => DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day + 7 * direction,
      ),
      _CalendarMode.month => DateTime(
        _selectedDate.year,
        _selectedDate.month + direction,
        1,
      ),
    });
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(math.min(1900, _selectedDate.year)),
      lastDate: DateTime(math.max(2100, _selectedDate.year), 12, 31),
    );
    if (mounted && selected != null) _selectDate(selected);
  }

  Future<void> _newPlan(
    AppController controller, {
    TaskItem? task,
    DateTime? start,
  }) async {
    final saved = await showPlanBlockEditor(
      context,
      controller: controller,
      task: task,
      suggestedStart:
          start ??
          DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            9,
          ),
    );
    if (!mounted || saved == null) return;
    _selectDate(saved.startsAt);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('计划时段已保存')));
  }

  Future<void> _scheduleAt(
    AppController controller,
    TaskItem task,
    DateTime start,
  ) async {
    if (_scheduling) return;
    setState(() {
      _scheduling = true;
      _scheduleError = null;
      _failedSchedule = null;
    });
    try {
      await controller.scheduleTask(
        taskId: task.id,
        startsAt: start,
        duration: Duration(seconds: task.estimatedDurationSeconds ?? 30 * 60),
      );
      if (!mounted) return;
      _selectDate(start);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('计划时段已保存')));
    } catch (error) {
      if (mounted) {
        setState(() {
          _scheduleError = persistenceErrorMessage(error)
              .replaceFirst('输入已保留', '任务已保留');
          _failedSchedule = (task, start);
        });
      }
    } finally {
      if (mounted) setState(() => _scheduling = false);
    }
  }

  Future<void> _showUnscheduled(AppController controller) async {
    final selected = await showModalBottomSheet<TaskItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final plannedIds = controller.planBlocks
                  .map((block) => block.taskId)
                  .whereType<String>()
                  .toSet();
              final tasks = controller.tasks
                  .where(
                    (task) =>
                        !task.isCompleted && !plannedIds.contains(task.id),
                  )
                  .toList(growable: false);
              return _UnscheduledPanel(
                tasks: tasks,
                busy: _scheduling,
                draggable: false,
                onSchedule: (task) => Navigator.pop(context, task),
              );
            },
          ),
        ),
      ),
    );
    if (mounted && selected != null) await _newPlan(controller, task: selected);
  }

  Future<void> _showEvent(
    AppController controller,
    _CalendarEvent event,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final editTask = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '日历记录详情',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: '关闭详情',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(event.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            _EventLegend(kind: event.kind),
            const SizedBox(height: AppSpacing.sm),
            Text(
              event.originalTime,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(event.status, style: Theme.of(context).textTheme.bodyMedium),
            if (event.crossesDay) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '议程仅显示与所选日期相交的时段，原始记录未拆分。',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
            if (event.task != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text('关联任务：${event.task!.title}'),
            ],
            if (event.planTitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('关联计划：${event.planTitle}'),
            ],
            if (event.kind == _EventKind.focus) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('已记录实际专注：${formatDuration(event.recordedSeconds)}'),
            ],
            if (event.kind == _EventKind.plan) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                '此处为只读详情，当前计划编辑器仅支持新增。',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (event.kind == _EventKind.deadline && event.task != null)
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑任务'),
              )
            else
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
          ],
        ),
      ),
    );
    if (mounted && editTask == true && event.task != null) {
      await showTaskEditor(context, controller: controller, task: event.task);
    }
  }
}

class _CalendarEvent {
  const _CalendarEvent({
    required this.id,
    required this.kind,
    required this.title,
    required this.startsAt,
    required this.visibleStart,
    required this.visibleEnd,
    required this.originalTime,
    required this.status,
    this.endsAt,
    this.task,
    this.planTitle,
    this.recordedSeconds = 0,
    this.crossesDay = false,
  });
  final String id;
  final _EventKind kind;
  final String title;
  final DateTime startsAt;
  final DateTime? endsAt;
  final DateTime visibleStart;
  final DateTime visibleEnd;
  final String originalTime;
  final String status;
  final TaskItem? task;
  final String? planTitle;
  final int recordedSeconds;
  final bool crossesDay;

  String get visibleTime {
    if (kind == _EventKind.deadline) return formatClock(startsAt);
    if (endsAt == null) return '${formatClock(visibleStart)} 起';
    final end =
        !_sameDay(visibleEnd, visibleStart) &&
            visibleEnd.hour == 0 &&
            visibleEnd.minute == 0
        ? '24:00'
        : formatClock(visibleEnd);
    return '${formatClock(visibleStart)}–$end';
  }
}

List<_CalendarEvent> _eventsForDate(AppController controller, DateTime date) {
  final start = _day(date);
  final end = DateTime(date.year, date.month, date.day + 1);
  final events = <_CalendarEvent>[];
  for (final task in controller.tasks) {
    final dueAt = task.dueAt?.toLocal();
    if (dueAt == null || !_sameDay(dueAt, date)) continue;
    events.add(
      _CalendarEvent(
        id: 'task-${task.id}',
        kind: _EventKind.deadline,
        title: task.title,
        startsAt: dueAt,
        visibleStart: dueAt,
        visibleEnd: dueAt,
        originalTime: '截止 ${_dateTime(dueAt)}',
        status: task.isCompleted ? '任务已完成' : '任务未完成',
        task: task,
      ),
    );
  }
  for (final block in controller.planBlocks) {
    if (!_intersects(block.startsAt, block.endsAt, start, end)) continue;
    final task = controller.taskById(block.taskId);
    events.add(
      _CalendarEvent(
        id: 'plan-${block.id}',
        kind: _EventKind.plan,
        title: task?.title ?? block.title ?? '未命名计划',
        startsAt: block.startsAt,
        endsAt: block.endsAt,
        visibleStart: block.startsAt.isBefore(start) ? start : block.startsAt,
        visibleEnd: block.endsAt.isAfter(end) ? end : block.endsAt,
        originalTime:
            '${_dateTime(block.startsAt)} 至 ${_dateTime(block.endsAt)}',
        status: switch (block.status) {
          PlanBlockStatus.scheduled => '计划 · 已安排',
          PlanBlockStatus.completed => '计划 · 已完成',
          PlanBlockStatus.cancelled => '计划 · 已取消',
        },
        task: task,
        crossesDay: !_sameDay(block.startsAt, block.endsAt),
      ),
    );
  }
  for (final session in controller.focusSessions) {
    final local = controller.isLocalFocusSession(session);
    // A remote active interval is bounded by its last sync, never by this clock.
    final lastSync = controller.lastSuccessfulSyncAt;
    final cutoff =
        session.endedAt ??
        (local
            ? DateTime.now()
            : lastSync != null && lastSync.isAfter(session.startedAt)
            ? lastSync
            : session.startedAt);
    final visible = cutoff == session.startedAt
        ? _sameDay(session.startedAt, date)
        : _intersects(session.startedAt, cutoff, start, end);
    if (!visible) continue;
    final task = controller.taskById(session.taskId);
    final plan = session.planBlockId == null
        ? null
        : controller.planBlocks
              .where((block) => block.id == session.planBlockId)
              .firstOrNull;
    final status = switch (session.status) {
      FocusSessionStatus.running => local ? '专注 · 本机进行中' : '专注 · 最近同步状态：进行中',
      FocusSessionStatus.paused => local ? '专注 · 本机已暂停' : '专注 · 最近同步状态：已暂停',
      FocusSessionStatus.completed => '专注 · 已完成',
      FocusSessionStatus.abandoned => '专注 · 提前结束',
      FocusSessionStatus.interrupted => '专注 · 已中断',
    };
    events.add(
      _CalendarEvent(
        id: 'focus-${session.id}',
        kind: _EventKind.focus,
        title: task?.title ?? '无关联任务的专注',
        startsAt: session.startedAt,
        endsAt: session.endedAt,
        visibleStart: session.startedAt.isBefore(start)
            ? start
            : session.startedAt,
        visibleEnd: cutoff.isAfter(end) ? end : cutoff,
        originalTime: session.endedAt == null
            ? '${_dateTime(session.startedAt)} 起，尚未结束'
            : '${_dateTime(session.startedAt)} 至 ${_dateTime(session.endedAt!)}',
        status: status,
        task: task,
        planTitle: plan == null
            ? null
            : controller.taskById(plan.taskId)?.title ?? plan.title ?? '未命名计划',
        recordedSeconds: session.actualDurationSeconds,
        crossesDay: !_sameDay(session.startedAt, cutoff),
      ),
    );
  }
  events.sort((a, b) {
    final time = a.visibleStart.compareTo(b.visibleStart);
    return time != 0 ? time : a.id.compareTo(b.id);
  });
  return events;
}

class _DayAgenda extends StatelessWidget {
  const _DayAgenda({
    required this.date,
    required this.events,
    required this.showAllHours,
    required this.onShowAllHours,
    required this.onOpen,
    required this.onCreate,
    required this.onDrop,
    required this.busy,
  });
  final DateTime date;
  final List<_CalendarEvent> events;
  final bool showAllHours;
  final VoidCallback onShowAllHours;
  final ValueChanged<_CalendarEvent> onOpen;
  final ValueChanged<DateTime> onCreate;
  final void Function(TaskItem, DateTime) onDrop;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final hours =
        showAllHours
              ? List.generate(24, (index) => index)
              : events.map((event) => event.visibleStart.hour).toSet().toList()
          ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${events.length} 条记录',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton(
              onPressed: onShowAllHours,
              child: Text(showAllHours ? '收起空时段' : '查看全天'),
            ),
          ],
        ),
        if (events.isEmpty && !showAllHours)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              '所选日期暂无截止、计划或专注记录。可新建时段，或为未排期任务安排时间。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        for (final hour in hours)
          _HourSlot(
            date: date,
            hour: hour,
            events: events
                .where((event) => event.visibleStart.hour == hour)
                .toList(growable: false),
            allEvents: events,
            onOpen: onOpen,
            onCreate: onCreate,
            onDrop: onDrop,
            busy: busy,
          ),
      ],
    );
  }
}

class _HourSlot extends StatelessWidget {
  const _HourSlot({
    required this.date,
    required this.hour,
    required this.events,
    required this.allEvents,
    required this.onOpen,
    required this.onCreate,
    required this.onDrop,
    required this.busy,
  });
  final DateTime date;
  final int hour;
  final List<_CalendarEvent> events;
  final List<_CalendarEvent> allEvents;
  final ValueChanged<_CalendarEvent> onOpen;
  final ValueChanged<DateTime> onCreate;
  final void Function(TaskItem, DateTime) onDrop;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final start = DateTime(date.year, date.month, date.day, hour);
    return DragTarget<TaskItem>(
      onWillAcceptWithDetails: (_) => !busy,
      onAcceptWithDetails: (details) => onDrop(details.data, start),
      builder: (context, candidates, rejected) => Material(
        color: candidates.isEmpty
            ? Colors.transparent
            : Theme.of(context).colorScheme.primaryContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(),
            if (events.isEmpty)
              TextButton.icon(
                onPressed: busy ? null : () => onCreate(start),
                icon: const Icon(Icons.add, size: 18),
                label: Text(
                  '${hour.toString().padLeft(2, '0')}:00 · ${candidates.isEmpty ? '安排时间' : '放到此时段'}',
                ),
              ),
            for (final event in events)
              _EventRow(
                event: event,
                overlap: allEvents.any(
                  (other) =>
                      other.id != event.id &&
                      other.kind != _EventKind.deadline &&
                      event.kind != _EventKind.deadline &&
                      event.visibleStart.isBefore(other.visibleEnd) &&
                      event.visibleEnd.isAfter(other.visibleStart),
                ),
                onOpen: () => onOpen(event),
              ),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.overlap,
    required this.onOpen,
  });
  final _CalendarEvent event;
  final bool overlap;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xxs,
          children: [
            Text(
              event.status,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (overlap)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.warningContainer,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  child: Text(
                    '时间重叠',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onWarningContainer,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (event.crossesDay)
          Text(
            event.originalTime,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (event.kind == _EventKind.focus && event.recordedSeconds > 0)
          Text(
            '已记录 ${formatDuration(event.recordedSeconds, compact: true)}',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
    return Semantics(
      button: true,
      excludeSemantics: true,
      label:
          '${_kindLabel(event.kind)}，${event.title}，${event.originalTime}，${event.status}${event.kind == _EventKind.focus ? '，已记录实际专注 ${event.recordedSeconds} 秒' : ''}${overlap ? '，时间重叠' : ''}，打开完整详情',
      onTap: onOpen,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final largeText =
                  MediaQuery.textScalerOf(context).scale(16) > 24 ||
                  constraints.maxWidth < 400;
              final time = Text(
                event.visibleTime,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              );
              if (largeText) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _EventLegend(kind: event.kind),
                        time,
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    details,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 116, child: time),
                  const SizedBox(width: AppSpacing.sm),
                  ExcludeSemantics(
                    child: Text(
                      _kindSymbol(event.kind),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: details),
                  const SizedBox(width: AppSpacing.xs),
                  const ExcludeSemantics(child: Icon(Icons.chevron_right)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EventLegend extends StatelessWidget {
  const _EventLegend({required this.kind});
  final _EventKind kind;

  @override
  Widget build(BuildContext context) => Text(
    '${_kindSymbol(kind)} ${_kindLabel(kind)}',
    style: Theme.of(context).textTheme.bodySmall,
  );
}

class _WeekOverview extends StatelessWidget {
  const _WeekOverview({
    required this.selectedDate,
    required this.controller,
    required this.onSelected,
    required this.onDrop,
    required this.busy,
  });
  final DateTime selectedDate;
  final AppController controller;
  final ValueChanged<DateTime> onSelected;
  final void Function(TaskItem, DateTime) onDrop;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final monday = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day - selectedDate.weekday + 1,
    );
    final cellWidth = math.max(
      AppSizes.minTouchTarget,
      MediaQuery.textScalerOf(context).scale(16) * 2 + AppSpacing.md,
    );
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const PageStorageKey('calendar-week'),
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(constraints.maxWidth, cellWidth * 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < 7; index++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final date = DateTime(
                        monday.year,
                        monday.month,
                        monday.day + index,
                      );
                      final count = controller.planBlocks
                          .where(
                            (block) => _intersects(
                              block.startsAt,
                              block.endsAt,
                              date,
                              DateTime(date.year, date.month, date.day + 1),
                            ),
                          )
                          .length;
                      return DragTarget<TaskItem>(
                        onWillAcceptWithDetails: (_) => !busy,
                        onAcceptWithDetails: (details) => onDrop(
                          details.data,
                          DateTime(date.year, date.month, date.day, 9),
                        ),
                        builder: (context, candidates, rejected) => _DateCell(
                          date: date,
                          selected: _sameDay(date, selectedDate),
                          count: count,
                          showWeekday: true,
                          highlighted: candidates.isNotEmpty,
                          onSelected: () => onSelected(date),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.selectedDate,
    required this.controller,
    required this.onSelected,
  });
  final DateTime selectedDate;
  final AppController controller;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(selectedDate.year, selectedDate.month);
    final gridStart = DateTime(
      first.year,
      first.month,
      first.day - first.weekday + 1,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final cellWidth = math.max(
      AppSizes.minTouchTarget,
      scaler.scale(16) * 2 + AppSpacing.md,
    );
    final cellHeight = scaler.scale(14) / 14 * 60 + AppSpacing.xl;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const PageStorageKey('calendar-month'),
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(constraints.maxWidth, cellWidth * 7),
          child: Column(
            children: [
              Row(
                children: [
                  for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: Center(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: cellHeight,
                ),
                itemCount: 42,
                itemBuilder: (context, index) {
                  final date = DateTime(
                    gridStart.year,
                    gridStart.month,
                    gridStart.day + index,
                  );
                  final count = controller.planBlocks
                      .where(
                        (block) => _intersects(
                          block.startsAt,
                          block.endsAt,
                          date,
                          DateTime(date.year, date.month, date.day + 1),
                        ),
                      )
                      .length;
                  return _DateCell(
                    date: date,
                    selected: _sameDay(date, selectedDate),
                    count: count,
                    inMonth: date.month == selectedDate.month,
                    onSelected: () => onSelected(date),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateCell extends StatelessWidget {
  const _DateCell({
    required this.date,
    required this.selected,
    required this.count,
    required this.onSelected,
    this.showWeekday = false,
    this.highlighted = false,
    this.inMonth = true,
  });
  final DateTime date;
  final bool selected;
  final int count;
  final VoidCallback onSelected;
  final bool showWeekday;
  final bool highlighted;
  final bool inMonth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = _sameDay(date, DateTime.now());
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: '${_date(date)}${today ? '，今天' : ''}，$count 个计划时段，选择日期',
      onTap: onSelected,
      child: Material(
        color: selected || highlighted
            ? scheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.small),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(AppRadii.small),
          child: Container(
            constraints: const BoxConstraints(
              minWidth: AppSizes.minTouchTarget,
              minHeight: AppSizes.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: today ? scheme.primary : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(AppRadii.small),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showWeekday) ...[
                  Text(
                    formatShortWeekday(date),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                ],
                Text(
                  '${date.day}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: selected
                        ? scheme.onPrimaryContainer
                        : inMonth
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (today)
                  Text('今天', style: Theme.of(context).textTheme.bodySmall),
                if (count > 0)
                  Text(
                    '▰ $count',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnscheduledPanel extends StatelessWidget {
  const _UnscheduledPanel({
    required this.tasks,
    required this.busy,
    required this.onSchedule,
    this.draggable = true,
  });
  final List<TaskItem> tasks;
  final bool busy;
  final ValueChanged<TaskItem> onSchedule;
  final bool draggable;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '未排期任务 · ${tasks.length}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        '未完成且没有任何已保存计划关联的任务。点击“安排时间”设置时段。',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      if (draggable)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            '也可长按拖到周日期或已显示的时段。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      const SizedBox(height: AppSpacing.md),
      if (tasks.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Text('没有未排期任务。'),
        ),
      for (final task in tasks)
        Builder(
          builder: (context) {
            final row = Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: AlignmentDirectional.centerStart,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('任务详情'),
                        content: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(task.title),
                              if (task.note?.isNotEmpty == true) ...[
                                const SizedBox(height: AppSpacing.md),
                                Text(task.note!),
                              ],
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    ),
                    child: Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    task.estimatedDurationSeconds == null
                        ? '未设置预计用时'
                        : '预计 ${formatDuration(task.estimatedDurationSeconds!, compact: true)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: busy ? null : () => onSchedule(task),
                      icon: const Icon(Icons.event_available_outlined),
                      label: const Text('安排时间'),
                    ),
                  ),
                  const Divider(),
                ],
              ),
            );
            if (!draggable || busy) return row;
            return LongPressDraggable<TaskItem>(
              data: task,
              feedback: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(AppRadii.small),
                child: SizedBox(
                  width: AppSizes.sidePanel,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              child: row,
            );
          },
        ),
    ],
  );
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
bool _intersects(
  DateTime start,
  DateTime end,
  DateTime dayStart,
  DateTime dayEnd,
) => start.isBefore(dayEnd) && end.isAfter(dayStart);
String _date(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String _dateTime(DateTime date) => '${_date(date)} ${formatClock(date)}';
String _kindLabel(_EventKind kind) => switch (kind) {
  _EventKind.deadline => '截止',
  _EventKind.plan => '计划时段',
  _EventKind.focus => '实际专注',
};
String _kindSymbol(_EventKind kind) => switch (kind) {
  _EventKind.deadline => '◇',
  _EventKind.plan => '▰',
  _EventKind.focus => '▥',
};
