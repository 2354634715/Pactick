import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../models/domain_models.dart';
import '../state/app_controller.dart';
import '../utilities/formatters.dart';

bool canPauseActiveFocus(AppController controller) {
  final session = controller.activeFocusSession;
  return session != null &&
      controller.isLocalFocusSession(session) &&
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
              if (hours > 0) unit(hours, '时'),
              unit(minutes, '分'),
              unit(seconds, '秒'),
            ],
          );
        },
      );
      final value = Semantics(
        label: '${reached ? '已专注' : '剩余'} $hours 小时 $minutes 分钟 $seconds 秒',
        excludeSemantics: true,
        child: time,
      );
      final clockWidget = !showRing
          ? value
          : SizedBox.square(
              dimension: 276,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ExcludeSemantics(
                    child: SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: session.plannedDurationSeconds == 0
                            ? 0
                            : (elapsed / session.plannedDurationSeconds).clamp(
                                0.0,
                                1.0,
                              ),
                        strokeWidth: 8,
                        backgroundColor: scheme.surfaceContainerHighest,
                        color: session.status == FocusSessionStatus.paused
                            ? scheme.secondary
                            : scheme.primary,
                      ),
                    ),
                  ),
                  value,
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
                    ? '目标已到，已暂停'
                    : '目标已到，仍在记录',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            )
          else
            const Text('剩余时间'),
          const SizedBox(height: AppSpacing.sm),
          clockWidget,
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${reached ? '已专注时间 · ' : '已专注 ${formatDuration(elapsed, compact: true)} · '}目标 ${formatDuration(session.plannedDurationSeconds, compact: true)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    },
  );
}
