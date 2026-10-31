import '../../core/localization/app_localizations.dart';

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../dialogs/task_editor.dart';
import '../dialogs/plan_block_editor.dart';
import '../models/domain_models.dart';
import '../state/app_controller.dart';
import '../state_views/state_pane.dart';
import '../utilities/formatters.dart';

Future<void> showTaskDetailsPanel(
  BuildContext context, {
  required AppController controller,
  required TaskItem task,
}) {
  final accountId = controller.repository.selectedAccountId;
  Widget builder(BuildContext routeContext) => _TaskDetailsRoute(
    controller: controller,
    taskId: task.id,
    accountId: accountId,
    onEdit: () {
      final current = controller.taskById(task.id);
      if (current == null ||
          controller.repository.selectedAccountId != accountId) {
        return;
      }
      Navigator.pop(routeContext);
      if (context.mounted) {
        showTaskEditor(context, controller: controller, task: current);
      }
    },
  );
  if (MediaQuery.sizeOf(context).width < 600) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) =>
          FractionallySizedBox(heightFactor: 0.9, child: builder(context)),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppSizes.editorMax,
          maxHeight: 760,
        ),
        child: builder(context),
      ),
    ),
  );
}

class TaskDetailsPanel extends StatelessWidget {
  const TaskDetailsPanel({
    required this.task,
    required this.controller,
    required this.onEdit,
    super.key,
  });

  final TaskItem task;
  final AppController controller;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(task.title, style: text.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(switch (task.status) {
          TaskStatus.open => context.tr('待办'),
          TaskStatus.completed => context.tr('已完成'),
          TaskStatus.cancelled => context.tr('已取消'),
        }, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.lg),
        Text(context.tr('备注'), style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(
          task.note?.isNotEmpty == true ? task.note! : context.tr('没有备注'),
        ),
        const SizedBox(height: AppSpacing.xl),
        _DetailField(
          label: context.tr('项目'),
          value:
              controller.projectById(task.projectId)?.name ?? context.tr('收集箱'),
        ),
        _DetailField(label: context.tr('优先级'), value: task.priority.label),
        _DetailField(
          label: context.tr('截止日期'),
          value: task.dueAt == null
              ? context.tr('未设置')
              : '${formatFullDate(task.dueAt!.toLocal())} '
                    '${formatClock(task.dueAt!.toLocal())}',
        ),
        _DetailField(
          label: context.tr('预计用时'),
          value: task.estimatedDurationSeconds == null
              ? context.tr('未设置')
              : formatDuration(task.estimatedDurationSeconds!, compact: true),
        ),
        _DetailField(
          label: context.tr('已记录实际专注'),
          value: formatDuration(
            controller.actualSecondsForTask(task.id),
            compact: true,
          ),
        ),
        _DetailField(
          label: context.tr('标签'),
          value: task.tags.isEmpty ? context.tr('没有标签') : task.tags.join('、'),
        ),
        Text(context.tr('计划时段'), style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        if (!controller.planBlocks.any((block) => block.taskId == task.id))
          Text(context.tr('尚未安排时间')),
        for (final block in controller.planBlocks.where(
          (block) => block.taskId == task.id,
        ))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(
              '${formatFullDate(block.startsAt)} ${formatClock(block.startsAt)}',
            ),
            subtitle: Text(
              '${formatDuration(block.durationSeconds, compact: true)} · ${switch (block.status) {
                PlanBlockStatus.scheduled => context.tr("已安排"),
                PlanBlockStatus.completed => context.tr("已完成"),
                PlanBlockStatus.cancelled => context.tr("已取消"),
              }}',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => showPlanBlockEditor(
              context,
              controller: controller,
              block: block,
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: task.status == TaskStatus.open
                ? () => showPlanBlockEditor(
                    context,
                    controller: controller,
                    task: task,
                  )
                : null,
            icon: const Icon(Icons.add),
            label: Text(context.tr('安排时间')),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: Text(context.tr('编辑任务')),
          ),
        ),
      ],
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _TaskDetailsRoute extends StatefulWidget {
  const _TaskDetailsRoute({
    required this.controller,
    required this.taskId,
    required this.accountId,
    required this.onEdit,
  });

  final AppController controller;
  final String taskId;
  final String accountId;
  final VoidCallback onEdit;

  @override
  State<_TaskDetailsRoute> createState() => _TaskDetailsRouteState();
}

class _TaskDetailsRouteState extends State<_TaskDetailsRoute> {
  TaskItem? _task;
  ProjectItem? _project;
  int _actualSeconds = 0;
  Object? _plans;

  @override
  void initState() {
    super.initState();
    _read();
    widget.controller.addListener(_refresh);
  }

  void _read() {
    _task = widget.controller.repository.selectedAccountId == widget.accountId
        ? widget.controller.taskById(widget.taskId)
        : null;
    _project = widget.controller.projectById(_task?.projectId);
    _actualSeconds = widget.controller.actualSecondsForTask(widget.taskId);
    _plans = widget.controller.planBlocks;
  }

  void _refresh() {
    final previous = (_task, _project, _actualSeconds, _plans);
    _read();
    if (previous != (_task, _project, _actualSeconds, _plans) && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.xs,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('任务详情'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: context.tr('关闭任务详情'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: _task == null
                ? StatePane.empty(
                    title: context.tr('当前工作区中没有这项任务'),
                    message: context.tr('关闭详情后查看当前工作区的任务。'),
                  )
                : TaskDetailsPanel(
                    task: _task!,
                    controller: widget.controller,
                    onEdit: widget.onEdit,
                  ),
          ),
        ),
      ],
    );
  }
}
