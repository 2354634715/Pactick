import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../models/domain_models.dart';
import '../utilities/formatters.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({
    required this.task,
    required this.onToggle,
    required this.onTap,
    this.project,
    this.planBlock,
    this.actualSeconds = 0,
    this.onStartFocus,
    this.trailing,
    this.enabled = true,
    this.selected = false,
    super.key,
  });
  final TaskItem task;
  final ProjectItem? project;
  final PlanBlockItem? planBlock;
  final int actualSeconds;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onTap;
  final VoidCallback? onStartFocus;
  final Widget? trailing;
  final bool enabled;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hex = project?.color.replaceFirst('#', '');
    final parsed = hex == null ? null : int.tryParse(hex, radix: 16);
    final projectColor = parsed == null
        ? null
        : hex!.length == 6
        ? Color(0xFF000000 | parsed)
        : hex.length == 8
        ? Color(((parsed & 0xFF) << 24) | (parsed >> 8))
        : null;
    final now = DateTime.now();
    final overdue =
        task.dueAt != null &&
        !task.isCompleted &&
        task.dueAt!.isBefore(DateTime(now.year, now.month, now.day));
    final metadata = <String>[
      if (task.priority != TaskPriority.none) '${task.priority.label}优先级',
      if (project != null) project!.name,
      if (planBlock != null)
        '计划 ${formatClock(planBlock!.startsAt)}–${formatClock(planBlock!.endsAt)}',
      if (task.dueAt != null)
        '${overdue ? '已逾期 · ' : ''}截止 ${formatMonthDay(task.dueAt!.toLocal())}',
      if (task.estimatedDurationSeconds case final seconds?)
        '预计 ${formatDuration(seconds, compact: true)}',
      if (actualSeconds > 0)
        '实际 ${formatDuration(actualSeconds, compact: true)}',
      for (final tag in task.tags) '#$tag',
    ];
    return Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: AppSizes.minTouchTarget,
                height: AppSizes.minTouchTarget,
                child: Semantics(
                  label:
                      '${task.title}，${task.isCompleted ? '标记为未完成' : '标记为已完成'}',
                  child: Checkbox(
                    value: task.isCompleted,
                    onChanged: enabled ? onToggle : null,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Semantics(
                  selected: selected,
                  button: true,
                  enabled: enabled,
                  child: InkWell(
                    onTap: enabled ? onTap : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  decoration: task.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: task.isCompleted
                                      ? scheme.onSurfaceVariant
                                      : scheme.onSurface,
                                ),
                          ),
                          if (metadata.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text.rich(
                              TextSpan(
                                children: [
                                  if (projectColor != null)
                                    WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: ExcludeSemantics(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            right: AppSpacing.xxs,
                                          ),
                                          child: SizedBox.square(
                                            dimension: AppSpacing.xs,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: projectColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  TextSpan(text: metadata.join(' · ')),
                                ],
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!task.isCompleted && onStartFocus != null)
                    IconButton(
                      tooltip: '开始专注',
                      onPressed: enabled ? onStartFocus : null,
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                  ?trailing,
                ],
              ),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }
}
