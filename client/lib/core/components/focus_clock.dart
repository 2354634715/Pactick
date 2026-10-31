import '../../core/localization/app_localizations.dart';

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../models/domain_models.dart';
import '../state/app_controller.dart';
import '../utilities/formatters.dart';

bool canPauseActiveFocus(AppController controller) {
  final session = controller.activeFocusSession;
  return session != null &&
      controller.isLocalFocusSession(session) &&
      controller.policyById(session.focusPolicyId)?.mode !=
          FocusPolicyMode.strict &&
      controller.policyById(session.focusPolicyId)?.allowPause != false;
}

class FocusClock extends StatelessWidget {
  const FocusClock({
    required this.controller,
    this.showRing = false,
    this.compact = false,
    super.key,
  });
  final AppController controller;
  final bool showRing;
  final bool compact;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final session = controller.activeFocusSession;
      if (session == null) return const SizedBox.shrink();
      final remaining = controller.activeFocusRemainingSeconds;
      final elapsed = controller.activeFocusElapsedSeconds;
      final reached = remaining == 0;
      final displayedSeconds = reached ? elapsed : remaining;
      final scheme = Theme.of(context).colorScheme;
      final hours = displayedSeconds ~/ 3600;
      final minutes = (displayedSeconds % 3600) ~/ 60;
      final seconds = displayedSeconds % 60;
      final clock = hours > 0
          ? '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
          : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      final style =
          (compact
                  ? Theme.of(context).textTheme.titleMedium
                  : Theme.of(context).textTheme.displayLarge)
              ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
      final time = LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: clock, style: style),
            textScaler: MediaQuery.textScalerOf(context),
            textDirection: Directionality.of(context),
          )..layout();
          final fits = painter.width <= constraints.maxWidth;
          painter.dispose();
          if (fits) {
            return Text(clock, style: style);
          }
          final digits = compact
              ? style
              : Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                );
          Widget unit(int value, String name) => Text.rich(
            TextSpan(
              text: value.toString().padLeft(2, '0'),
              style: digits,
              children: [
                TextSpan(
                  text: ' $name',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
          return Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (hours > 0) unit(hours, context.tr('时')),
              unit(minutes, context.tr('分')),
              unit(seconds, context.tr('秒')),
            ],
          );
        },
      );
      final value = Semantics(
        label: context.tr(
          '{arg0} {arg1} 小时 {arg2} 分钟 {arg3} 秒',
          args: {
            'arg0': reached ? tr('已专注') : tr('剩余'),
            'arg1': hours,
            'arg2': minutes,
            'arg3': seconds,
          },
        ),
        excludeSemantics: true,
        child: time,
      );
      final clockWidget = !showRing
          ? value
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  value,
                  const SizedBox(height: AppSpacing.lg),
                  ExcludeSemantics(
                    child: SizedBox(
                      width: double.infinity,
                      child: LinearProgressIndicator(
                        value: session.plannedDurationSeconds == 0
                            ? 0
                            : (elapsed / session.plannedDurationSeconds).clamp(
                                0.0,
                                1.0,
                              ),
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(3),
                        stopIndicatorRadius: 0,
                        backgroundColor: scheme.surfaceContainerHighest,
                        color: session.status == FocusSessionStatus.paused
                            ? scheme.secondary
                            : scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            );
      if (compact) return clockWidget;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reached)
            Semantics(
              liveRegion: true,
              child: Text(
                session.status == FocusSessionStatus.paused
                    ? context.tr('目标已到，已暂停')
                    : context.tr('目标已到，仍在记录'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            )
          else
            Text(context.tr('剩余时间')),
          const SizedBox(height: AppSpacing.sm),
          clockWidget,
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.tr(
              '{arg0}目标 {arg1}',
              args: {
                'arg0': reached
                    ? tr('已专注时间 · ')
                    : tr(
                        '已专注 {arg0} · ',
                        args: {'arg0': formatDuration(elapsed, compact: true)},
                      ),
                'arg1': formatDuration(
                  session.plannedDurationSeconds,
                  compact: true,
                ),
              },
            ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    },
  );
}
