import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              action != null &&
              (constraints.maxWidth < 480 ||
                  MediaQuery.textScalerOf(context).scale(16) > 22);
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: AppSpacing.xs),
                Align(alignment: AlignmentDirectional.centerEnd, child: action),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: heading),
              if (action != null) ...[
                const SizedBox(width: AppSpacing.sm),
                action!,
              ],
            ],
          );
        },
      ),
    );
  }
}
