import '../../core/localization/app_localizations.dart';

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
      if (task.priority != TaskPriority.none)
        context.tr('{arg0}优先级', args: {'arg0': task.priority.label}),
      if (project != null) project!.name,
      if (planBlock != null)
        context.tr(
          '计划 {arg0}–{arg1}',
          args: {
            'arg0': formatClock(planBlock!.startsAt),
            'arg1': formatClock(planBlock!.endsAt),
          },
        ),
      if (task.dueAt != null)
        context.tr(
          '{arg0}截止 {arg1}',
          args: {
            'arg0': overdue ? tr('已逾期 · ') : '',
            'arg1': formatMonthDay(task.dueAt!.toLocal()),
          },
        ),
      if (task.estimatedDurationSeconds case final seconds?)
        context.tr(
          '预计 {arg0}',
          args: {'arg0': formatDuration(seconds, compact: true)},
        ),
      if (actualSeconds > 0)
        context.tr(
          '实际 {arg0}',
          args: {'arg0': formatDuration(actualSeconds, compact: true)},
        ),
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
                      '${task.title}，${task.isCompleted ? context.tr("标记为未完成") : context.tr("标记为已完成")}',
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
                                  fontWeight: FontWeight.w400,
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
                      tooltip: context.tr('开始专注'),
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
