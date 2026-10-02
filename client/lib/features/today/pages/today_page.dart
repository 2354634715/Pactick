import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/components/feature_page_scaffold.dart';
import '../../../core/components/section_header.dart';
import '../../../core/components/sync_status_button.dart';
import '../../../core/components/task_card.dart';
import '../../../core/components/task_details_panel.dart';
import '../../../core/dialogs/task_editor.dart';
import '../../../core/models/domain_models.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/state/app_scope.dart';
import '../../../core/state_views/state_pane.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/persistence_errors.dart';

enum _TodayFilter { all, planned, manual }

enum _TodayAction { edit, focus, up, down }

class TodayPage extends StatefulWidget {
  const TodayPage({
    required this.onOpenSettings,
    required this.onOpenCalendar,
    required this.onOpenFocus,
    super.key,
  });
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenFocus;
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  final _listController = ScrollController();
  final _plansController = ScrollController();
  final _busyTasks = <String>{};
  DateTime _selectedDate = DateTime.now();
  bool _showProcessed = false;
  bool _sorting = false;
  _TodayFilter _filter = _TodayFilter.all;

  @override
  void dispose() {
    _listController.dispose();
    _plansController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watchData(context);
    final all = controller.tasksForDate(_selectedDate);
    final items = all
        .where((task) {
          if (_showProcessed != task.isCompleted) return false;
          final planned =
              controller.firstPlanForTask(task.id, _selectedDate) != null;
          return switch (_filter) {
            _TodayFilter.all => true,
            _TodayFilter.planned => planned,
            _TodayFilter.manual => !planned,
          };
        })
        .toList(growable: false);
    final planned = items
        .where(
          (task) => controller.firstPlanForTask(task.id, _selectedDate) != null,
        )
        .toList(growable: false);
    final manual = items
        .where(
          (task) => controller.firstPlanForTask(task.id, _selectedDate) == null,
        )
        .toList(growable: false);
    final standalone =
        controller.planBlocks
            .where(
              (block) =>
                  block.taskId == null &&
                  _sameDay(block.startsAt, _selectedDate),
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final plannedSeconds = controller.planBlocks
        .where((block) => _sameDay(block.startsAt, _selectedDate))
        .fold(0, (sum, block) => sum + block.durationSeconds);
    final actualSeconds = controller.focusSessions
        .where((session) => _sameDay(session.startedAt, _selectedDate))
        .fold(0, (sum, session) => sum + session.actualDurationSeconds);
    final completed = all.where((task) => task.isCompleted).length;

    return FeaturePageScaffold(
      title: '今日',
      subtitle: formatFullDate(_selectedDate),
      scrollable: false,
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
        heroTag: 'today-create-task',
        onPressed: () => showTaskEditor(
          context,
          controller: controller,
          suggestedDueAt: _selectedDate,
        ),
        icon: const Icon(Icons.add),
        label: const Text('新建任务'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final sidePlans =
              standalone.isNotEmpty &&
              constraints.maxWidth >= AppSizes.twoPaneMinWidth &&
              constraints.maxHeight >= AppSizes.lowHeight;
          final list = CustomScrollView(
            key: const PageStorageKey('today-list'),
            controller: _listController,
            slivers: [
              SliverToBoxAdapter(
                child: _header(
                  plannedSeconds,
                  actualSeconds,
                  completed,
                  all.length,
                ),
              ),
              if (items.isEmpty)
                SliverToBoxAdapter(child: _empty(controller))
              else ...[
                if (planned.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: SectionHeader(title: '当天有排期'),
                  ),
                  SliverList.builder(
                    itemCount: planned.length,
                    itemBuilder: (context, index) => _taskRow(
                      controller,
                      planned[index],
                      const [],
                      index: index,
                    ),
                  ),
                ],
                if (manual.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: SectionHeader(
                      title: '当天无排期',
                      subtitle: '可用更多菜单上移、下移，或拖动排序',
                    ),
                  ),
                  SliverReorderableList(
                    itemCount: manual.length,
                    onReorderItem: (oldIndex, newIndex) =>
                        _reorder(controller, manual, oldIndex, newIndex),
                    itemBuilder: (context, index) => _taskRow(
                      controller,
                      manual[index],
                      manual,
                      index: index,
                    ),
                  ),
                ],
              ],
              if (!sidePlans && standalone.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: SectionHeader(title: '其他计划时段', subtitle: '这些计划没有关联任务'),
                ),
                SliverList.builder(
                  itemCount: standalone.length,
                  itemBuilder: (context, index) => _planRow(standalone[index]),
                ),
              ],
              const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.xxl + AppSpacing.lg),
              ),
            ],
          );
          if (!sidePlans) return list;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: list),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(
                width: AppSizes.sidePanel,
                child: ListView(
                  key: const PageStorageKey('today-standalone-plans'),
                  controller: _plansController,
                  children: [
                    const SectionHeader(
                      title: '其他计划时段',
                      subtitle: '这些计划没有关联任务',
                    ),
                    for (final block in standalone) _planRow(block),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(
    int plannedSeconds,
    int actualSeconds,
    int completed,
    int total,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dateNavigation(),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          children: [
            _SummaryStat(
              label: '计划时长',
              value: formatDuration(plannedSeconds, compact: true),
            ),
            _SummaryStat(
              label: '已记录实际专注',
              value: formatDuration(actualSeconds, compact: true),
            ),
            _SummaryStat(label: '已完成任务', value: '$completed / $total'),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: Text(
                '今日安排',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: '当天筛选说明',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('当天任务与筛选'),
                  content: const Text(
                    '这里显示当天截止或有待执行排期的任务。'
                    '“当天有排期”按当前已保存的当天计划判断，包括已完成或取消的计划；'
                    '未关联任务的计划单独显示。无当天排期的任务可调整次序，不改变截止日期。',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.info_outline),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final done in [false, true])
              ChoiceChip(
                selected: _showProcessed == done,
                label: Text(done ? '已完成' : '待办'),
                onSelected: (_) => setState(() => _showProcessed = done),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final filter in _TodayFilter.values)
              FilterChip(
                selected: _filter == filter,
                label: Text(switch (filter) {
                  _TodayFilter.all => '全部',
                  _TodayFilter.planned => '当天有排期',
                  _TodayFilter.manual => '当天无排期',
                }),
                onSelected: (_) => setState(() => _filter = filter),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (_sorting) const LinearProgressIndicator(semanticsLabel: '正在保存任务顺序'),
      ],
    );
  }

  Widget _dateNavigation() {
    final today = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: '前一天',
              onPressed: () => setState(
                () => _selectedDate = _selectedDate.subtract(
                  const Duration(days: 1),
                ),
              ),
              icon: const Icon(Icons.chevron_left),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(today.year - 10),
                  lastDate: DateTime(today.year + 10),
                );
                if (date != null && mounted) {
                  setState(() => _selectedDate = date);
                }
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(formatFullDate(_selectedDate)),
            ),
            IconButton(
              tooltip: '后一天',
              onPressed: () => setState(
                () =>
                    _selectedDate = _selectedDate.add(const Duration(days: 1)),
              ),
              icon: const Icon(Icons.chevron_right),
            ),
            if (!_sameDay(_selectedDate, today))
              TextButton(
                onPressed: () => setState(() => _selectedDate = today),
                child: const Text('回到今天'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < 7; index++) ...[
                _dateButton(
                  DateTime(today.year, today.month, today.day + index - 2),
                ),
                const SizedBox(width: AppSpacing.xxs),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _dateButton(DateTime date) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _sameDay(date, _selectedDate);
    return Semantics(
      button: true,
      selected: selected,
      label: formatFullDate(date),
      excludeSemantics: true,
      onTap: () => setState(() => _selectedDate = date),
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(
            AppSizes.minTouchTarget,
            AppSizes.minTouchTarget,
          ),
          backgroundColor: selected ? scheme.primaryContainer : null,
          foregroundColor: selected
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
        onPressed: () => setState(() => _selectedDate = date),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Text(formatShortWeekday(date)), Text(date.day.toString())],
        ),
      ),
    );
  }

  Widget _empty(AppController controller) {
    final filtered = _filter != _TodayFilter.all || _showProcessed;
    return StatePane.empty(
      title: controller.tasks.isEmpty ? '尚无任务' : '当前日期和筛选下没有任务',
      message: controller.tasks.isEmpty
          ? '使用“新建任务”记录任务；也可在日历中直接创建计划时段。'
          : '可切换日期或筛选，在日历中查看和安排时间。',
      actionLabel: filtered ? '查看当天全部待办' : '查看日历',
      onAction: filtered
          ? () => setState(() {
              _filter = _TodayFilter.all;
              _showProcessed = false;
            })
          : widget.onOpenCalendar,
    );
  }

  Widget _taskRow(
    AppController controller,
    TaskItem task,
    List<TaskItem> manual, {
    required int index,
  }) {
    final block = controller.firstPlanForTask(task.id, _selectedDate);
    final busy = _sorting || _busyTasks.contains(task.id);
    final additionalPlans =
        controller.planBlocks
            .where(
              (candidate) =>
                  candidate.taskId == task.id &&
                  _sameDay(candidate.startsAt, _selectedDate),
            )
            .length -
        1;
    return Column(
      key: ValueKey(task.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskCard(
          task: task,
          project: controller.projectById(task.projectId),
          planBlock: block,
          actualSeconds: controller.actualSecondsForTask(
            task.id,
            date: _selectedDate,
          ),
          enabled: !busy,
          onToggle: (_) => _toggleTask(controller, task.id),
          onTap: () =>
              showTaskDetailsPanel(context, controller: controller, task: task),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busyTasks.contains(task.id))
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    semanticsLabel: '正在保存任务',
                  ),
                )
              else
                PopupMenuButton<_TodayAction>(
                  key: ValueKey('today-more-${task.id}'),
                  enabled: !busy,
                  tooltip: '${task.title}的更多操作',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (action) {
                    switch (action) {
                      case _TodayAction.edit:
                        final current = controller.taskById(task.id);
                        if (current != null) {
                          showTaskEditor(
                            context,
                            controller: controller,
                            task: current,
                          );
                        }
                      case _TodayAction.focus:
                        _startFocus(controller, task.id);
                      case _TodayAction.up:
                        _reorder(controller, manual, index, index - 1);
                      case _TodayAction.down:
                        _reorder(controller, manual, index, index + 1);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: _TodayAction.edit,
                      child: Text('编辑任务'),
                    ),
                    if (!task.isCompleted)
                      PopupMenuItem(
                        value: _TodayAction.focus,
                        child: Text(
                          controller.activeFocusSession == null
                              ? '开始专注'
                              : '返回当前专注',
                        ),
                      ),
                    if (manual.isNotEmpty) ...[
                      PopupMenuItem(
                        value: _TodayAction.up,
                        enabled: index > 0,
                        child: const Text('上移'),
                      ),
                      PopupMenuItem(
                        value: _TodayAction.down,
                        enabled: index < manual.length - 1,
                        child: const Text('下移'),
                      ),
                    ],
                  ],
                ),
              if (manual.isNotEmpty && !busy)
                ReorderableDragStartListener(
                  index: index,
                  child: Semantics(
                    label: '拖动排序，也可在更多菜单选择上移或下移',
                    child: const Tooltip(
                      message: '拖动排序；更多菜单也可上移、下移',
                      child: SizedBox.square(
                        dimension: AppSizes.minTouchTarget,
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (additionalPlans > 0 && block != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 56),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: widget.onOpenCalendar,
                child: Text('另 $additionalPlans 个时段 · 查看日历'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _planRow(PlanBlockItem block) {
    final end = _sameDay(block.startsAt, block.endsAt)
        ? formatClock(block.endsAt)
        : '${formatMonthDay(block.endsAt)} ${formatClock(block.endsAt)}';
    final status = switch (block.status) {
      PlanBlockStatus.scheduled => '计划',
      PlanBlockStatus.completed => '已完成计划',
      PlanBlockStatus.cancelled => '已取消计划',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.schedule_outlined),
      title: Text(
        block.title ?? '未命名计划',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('$status · ${formatClock(block.startsAt)}–$end'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(block.title ?? '未命名计划'),
          content: Text(
            '$status\n${formatFullDate(block.startsAt)} ${formatClock(block.startsAt)}\n至 ${formatFullDate(block.endsAt)} ${formatClock(block.endsAt)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onOpenCalendar();
              },
              child: const Text('查看日历'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reorder(
    AppController controller,
    List<TaskItem> tasks,
    int oldIndex,
    int newIndex,
  ) async {
    if (_sorting ||
        _busyTasks.isNotEmpty ||
        oldIndex == newIndex ||
        newIndex < 0 ||
        newIndex >= tasks.length) {
      return;
    }
    final accountId = controller.repository.selectedAccountId;
    final date = _selectedDate;
    final currentTasks = tasks
        .map((task) => controller.taskById(task.id))
        .whereType<TaskItem>()
        .toList(growable: false);
    if (currentTasks.length != tasks.length ||
        currentTasks.any(
          (task) => controller.firstPlanForTask(task.id, date) != null,
        )) {
      _message('列表已变化，请在当前列表重新排序。');
      return;
    }
    setState(() => _sorting = true);
    try {
      await controller.reorderTasks(currentTasks, oldIndex, newIndex);
      if (controller.repository.selectedAccountId == accountId) {
        _message('任务顺序已保存');
      }
    } catch (error) {
      _error(
        error,
        retry: () {
          if (controller.repository.selectedAccountId != accountId ||
              !_sameDay(_selectedDate, date)) {
            _message('工作区或日期已变化，请在当前列表重新排序。');
            return;
          }
          final current = controller
              .tasksForDate(date)
              .where(
                (task) =>
                    controller.firstPlanForTask(task.id, date) == null &&
                    _showProcessed == task.isCompleted,
              )
              .toList(growable: false);
          final from = current.indexWhere(
            (task) => task.id == tasks[oldIndex].id,
          );
          final destination = current.indexWhere(
            (task) => task.id == tasks[newIndex].id,
          );
          if (from >= 0 && destination >= 0) {
            _reorder(controller, current, from, destination);
          }
        },
      );
    } finally {
      if (mounted) setState(() => _sorting = false);
    }
  }

  Future<void> _toggleTask(AppController controller, String id) async {
    if (!mounted || _busyTasks.contains(id)) return;
    final previous = controller.taskById(id);
    if (previous == null) return;
    final accountId = controller.repository.selectedAccountId;
    setState(() => _busyTasks.add(id));
    try {
      await controller.toggleTask(previous);
      final applied = controller.taskById(id);
      if (!mounted ||
          applied == null ||
          controller.repository.selectedAccountId != accountId) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(applied.isCompleted ? '任务已完成' : '任务已恢复待办'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () =>
                _undoTask(controller, previous, applied, accountId),
          ),
        ),
      );
    } catch (error) {
      _error(
        error,
        retry: () {
          if (controller.repository.selectedAccountId == accountId) {
            _toggleTask(controller, id);
          } else {
            _message('工作区已变化，请在当前工作区重新操作。');
          }
        },
      );
    } finally {
      if (mounted) setState(() => _busyTasks.remove(id));
    }
  }

  Future<void> _undoTask(
    AppController controller,
    TaskItem previous,
    TaskItem applied,
    String accountId,
  ) async {
    if (!mounted) return;
    final current = controller.taskById(previous.id);
    if (controller.repository.selectedAccountId != accountId ||
        current == null ||
        current.status != applied.status ||
        current.completedAt != applied.completedAt) {
      _message('任务状态或工作区已变化，无法撤销这次操作。');
      return;
    }
    if (_busyTasks.contains(current.id)) return;
    setState(() => _busyTasks.add(current.id));
    try {
      await controller.updateTask(
        current.copyWith(
          status: previous.status,
          completedAt: previous.completedAt,
          clearCompletedAt: previous.completedAt == null,
        ),
      );
      if (controller.repository.selectedAccountId == accountId) {
        _message('已撤销任务状态更改');
      }
    } catch (error) {
      _error(
        error,
        retry: () => _undoTask(controller, previous, applied, accountId),
      );
    } finally {
      if (mounted) setState(() => _busyTasks.remove(current.id));
    }
  }

  Future<void> _startFocus(AppController controller, String id) async {
    if (!mounted || _busyTasks.contains(id)) return;
    if (controller.activeFocusSession != null || !controller.canStartFocus) {
      widget.onOpenFocus();
      return;
    }
    final task = controller.taskById(id);
    final policy = controller.focusPolicies.firstOrNull;
    if (task == null || task.isCompleted || policy == null) return;
    final accountId = controller.repository.selectedAccountId;
    setState(() => _busyTasks.add(id));
    try {
      await controller.startFocus(
        task: task,
        durationSeconds: task.estimatedDurationSeconds ?? 25 * 60,
        policy: policy,
      );
      if (mounted && controller.repository.selectedAccountId == accountId) {
        widget.onOpenFocus();
      }
    } catch (error) {
      _error(
        error,
        retry: () {
          if (controller.repository.selectedAccountId == accountId) {
            _startFocus(controller, id);
          } else {
            _message('工作区已变化，请在当前工作区重新操作。');
          }
        },
      );
    } finally {
      if (mounted) setState(() => _busyTasks.remove(id));
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _error(Object error, {required VoidCallback retry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(persistenceErrorMessage(error)),
        action: SnackBarAction(label: '重试', onPressed: retry),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
