import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/components/feature_page_scaffold.dart';
import '../../../core/components/section_header.dart';
import '../../../core/components/sync_status_button.dart';
import '../../../core/models/domain_models.dart';
import '../../../core/state/app_scope.dart';
import '../../../core/state_views/state_pane.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({required this.onOpenSettings, super.key});
  final VoidCallback onOpenSettings;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  int _rangeDays = 7;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watchData(context);
    final stats = controller.statisticsForLastDays(_rangeDays);
    final planned = stats.fold(
      0,
      (sum, item) => sum + item.plannedDurationSeconds,
    );
    final actual = stats.fold(
      0,
      (sum, item) => sum + item.actualDurationSeconds,
    );
    final completed = stats.fold(0, (sum, item) => sum + item.completedTasks);
    final empty = planned == 0 && actual == 0 && completed == 0;
    return FeaturePageScaffold(
      title: '统计',
      maxWidth: AppSizes.compactContentMax,
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('近 7 天')),
                  ButtonSegment(value: 28, label: Text('近 4 周')),
                ],
                selected: {_rangeDays},
                onSelectionChanged: (selection) =>
                    setState(() => _rangeDays = selection.first),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${_fullDate(stats.first.date)} 至 ${_fullDate(stats.last.date)} · 当前工作区',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _MetricSummary(
            planned: planned,
            actual: actual,
            completed: completed,
          ),
          if (empty) ...[
            const SizedBox(height: AppSpacing.lg),
            StatePane.empty(
              title: '还没有统计记录',
              message: '本期没有计划时长、已记录专注或完成任务。添加计划或记录专注后，这里显示对应日期的数据。',
            ),
          ] else ...[
            const SectionHeader(title: '每日计划与实际', subtitle: '使用相同长度基准，单位为分钟'),
            _DailyComparison(stats: stats),
            const SectionHeader(title: '本期对比'),
            Text(
              planned == 0
                  ? '本期没有计划时段，不计算实际与计划的比例。已记录实际专注 ${_minutes(actual)} 分钟，完成 $completed 项任务。'
                  : '已记录实际专注比计划${actual >= planned ? '多' : '少'} ${_minutes((actual - planned).abs())} 分钟；实际 / 计划 ${(actual / planned * 100).round()}%。此比例不表示任务完成率。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Text(
            '计划与专注按开始日期归属；实际取已保存的专注时长，进行中计时的即时经过时间不计入此值。完成任务按完成日期统计。跨日记录不按日拆分，取消或中断状态仍按现有记录计入。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricSummary extends StatelessWidget {
  const _MetricSummary({
    required this.planned,
    required this.actual,
    required this.completed,
  });
  final int planned;
  final int actual;
  final int completed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 600 &&
            MediaQuery.textScalerOf(context).scale(16) <= 24;
        final metrics = [
          _Metric(
            label: '计划时长',
            value: _minutes(planned),
            unit: '分钟',
            source: '日历计划时段',
            semanticsValue: '${_minutes(planned)} 分钟',
            inline: !wide,
          ),
          _Metric(
            label: '已记录实际专注',
            value: _minutes(actual),
            unit: '分钟',
            source: '已保存专注时长',
            semanticsValue: '${_minutes(actual)} 分钟',
            inline: !wide,
          ),
          _Metric(
            label: '完成任务',
            value: '$completed',
            unit: '项',
            source: '按完成日期',
            semanticsValue: '$completed 项',
            inline: !wide,
          ),
        ];
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                if (index > 0) const SizedBox(width: AppSpacing.lg),
                Expanded(child: metrics[index]),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var index = 0; index < metrics.length; index++) ...[
              if (index > 0) const Divider(height: AppSpacing.xl),
              metrics[index],
            ],
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.unit,
    required this.source,
    required this.semanticsValue,
    required this.inline,
  });
  final String label;
  final String value;
  final String unit;
  final String source;
  final String semanticsValue;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = Wrap(
      spacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Text(
          value,
          style: theme.textTheme.displayMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text(unit, style: theme.textTheme.bodySmall),
        ),
      ],
    );
    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          source,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$label，$semanticsValue，$source',
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (inline &&
              constraints.maxWidth >= 340 &&
              MediaQuery.textScalerOf(context).scale(16) <= 20) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: description),
                const SizedBox(width: AppSpacing.md),
                Flexible(child: number),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              description,
              const SizedBox(height: AppSpacing.xs),
              number,
            ],
          );
        },
      ),
    );
  }
}

class _DailyComparison extends StatelessWidget {
  const _DailyComparison({required this.stats});
  final List<DailyStatItem> stats;

  @override
  Widget build(BuildContext context) {
    final maximum = stats.fold<int>(
      1,
      (current, item) => math.max(
        current,
        math.max(item.plannedDurationSeconds, item.actualDurationSeconds),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in stats)
          Semantics(
            container: true,
            excludeSemantics: true,
            label:
                '${_fullDate(item.date)}，计划 ${_minutes(item.plannedDurationSeconds)} 分钟，已记录实际专注 ${_minutes(item.actualDurationSeconds)} 分钟，完成 ${item.completedTasks} 项任务',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      Text(
                        '${item.date.month}/${item.date.day}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '完成 ${item.completedTasks} 项',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _ComparisonBar(
                    label: '计划',
                    seconds: item.plannedDurationSeconds,
                    maximum: maximum,
                    outlined: true,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _ComparisonBar(
                    label: '实际',
                    seconds: item.actualDurationSeconds,
                    maximum: maximum,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Divider(),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ComparisonBar extends StatelessWidget {
  const _ComparisonBar({
    required this.label,
    required this.seconds,
    required this.maximum,
    this.outlined = false,
  });
  final String label;
  final int seconds;
  final int maximum;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xxs,
          children: [
            Text(
              '${outlined ? '▰' : '▥'} $label',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              seconds == 0
                  ? outlined
                        ? '0 分钟 · 无计划'
                        : '0 分钟 · 无记录'
                  : '${_minutes(seconds)} 分钟',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        if (seconds > 0)
          ExcludeSemantics(
            child: SizedBox(
              height: AppSpacing.xs,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: (seconds / maximum).clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: outlined ? null : theme.colorScheme.primary,
                      border: outlined
                          ? Border.all(color: theme.colorScheme.outline)
                          : null,
                      borderRadius: BorderRadius.circular(AppSpacing.xxs),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          )
        else
          const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}

String _minutes(int seconds) {
  if (seconds % 60 == 0) return '${seconds ~/ 60}';
  return (seconds / 60).toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

String _fullDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
