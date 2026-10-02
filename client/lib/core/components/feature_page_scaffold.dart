import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import 'app_keyboard_scope.dart';

AppBar buildPageAppBar(
  BuildContext context, {
  required String title,
  bool low = false,
  Widget? leading,
  List<Widget> actions = const [],
}) {
  final scaler = MediaQuery.textScalerOf(context);
  final style = low
      ? Theme.of(context).textTheme.headlineSmall
      : Theme.of(context).textTheme.headlineLarge;
  final height =
      scaler.scale(style?.fontSize ?? 28) * (style?.height ?? 1.3) +
      AppSpacing.md;
  return AppBar(
    leading: leading,
    toolbarHeight: height < kToolbarHeight ? kToolbarHeight : height,
    title: Text(
      title,
      style: style,
      textScaler: scaler,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    actions: actions,
  );
}

class FeaturePageScaffold extends StatelessWidget {
  const FeaturePageScaffold({
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.leading,
    this.floatingActionButton,
    this.maxWidth = AppSizes.expandedContentMax,
    this.padding,
    this.scrollable = true,
    super.key,
  });
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final Widget? leading;
  final Widget? floatingActionButton;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inset = AppSizes.pageInset(constraints.maxWidth);
      final low = constraints.maxHeight < AppSizes.lowHeight;
      final keyboardOpen = AppKeyboardScope.visibleOf(context);
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subtitle != null) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSizes.readingContentMax,
                ),
                child: Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SizedBox(height: low ? AppSpacing.sm : AppSpacing.lg),
          ],
          if (scrollable) body else Expanded(child: body),
        ],
      );
      final padded = Padding(
        padding:
            padding ??
            EdgeInsets.fromLTRB(
              inset,
              AppSpacing.sm,
              inset,
              !scrollable || floatingActionButton == null || keyboardOpen
                  ? AppSpacing.lg
                  : AppSizes.fabScrollClearance,
            ),
        child: content,
      );
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: buildPageAppBar(
          context,
          title: title,
          low: low,
          leading: leading,
          actions: actions,
        ),
        floatingActionButton: keyboardOpen ? null : floatingActionButton,
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: scrollable
                  ? SingleChildScrollView(
                      key: PageStorageKey('page-$title'),
                      child: padded,
                    )
                  : padded,
            ),
          ),
        ),
      );
    },
  );
}
