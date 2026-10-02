import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.supportingText,
    this.accent,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? supportingText;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    return Semantics(
      label: '$label，$value${supportingText == null ? '' : '，$supportingText'}',
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 3, color: color.withValues(alpha: 0.78)),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.11),
                          borderRadius: BorderRadius.circular(AppRadii.small),
                        ),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(value, style: Theme.of(context).textTheme.headlineSmall),
                  if (supportingText != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      supportingText!,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MetricGrid extends StatelessWidget {
  const MetricGrid({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 920
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}
