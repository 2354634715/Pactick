import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

class EditorDismissalController {
  Future<void> Function()? requestClose;
}

Future<T?> showGuardedEditor<T>(
  BuildContext context, {
  required Widget Function(EditorDismissalController dismissal) builder,
}) {
  final compact = MediaQuery.sizeOf(context).width < 600;
  final dismissal = EditorDismissalController();
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '关闭编辑器',
    barrierColor: Colors.black54,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDurations.overlay,
    pageBuilder: (context, animation, secondaryAnimation) => SafeArea(
      bottom: !compact,
      child: Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => dismissal.requestClose?.call(),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Align(
            alignment: compact ? Alignment.bottomCenter : Alignment.center,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 0 : AppSpacing.lg,
                AppSpacing.lg,
                compact ? 0 : AppSpacing.lg,
                0,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppSizes.editorMax),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(AppRadii.overlay),
                  child: builder(dismissal),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class EditorDraftGuard extends StatefulWidget {
  const EditorDraftGuard({
    required this.dirty,
    required this.saving,
    required this.child,
    this.hasChanges,
    this.savingNow,
    this.dismissal,
    super.key,
  });

  final bool dirty;
  final bool saving;
  final Widget child;
  final bool Function()? hasChanges;
  final bool Function()? savingNow;
  final EditorDismissalController? dismissal;

  @override
  State<EditorDraftGuard> createState() => EditorDraftGuardState();
}

class EditorDraftGuardState extends State<EditorDraftGuard> {
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    widget.dismissal?.requestClose = requestClose;
  }

  @override
  void dispose() {
    widget.dismissal?.requestClose = null;
    super.dispose();
  }

  Future<void> requestClose() async {
    if ((widget.savingNow?.call() ?? widget.saving) || _confirming) return;
    if (widget.hasChanges?.call() ?? widget.dirty) {
      _confirming = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('放弃未保存的修改？'),
          content: const Text('输入尚未保存。继续编辑可保留当前内容。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('放弃修改'),
            ),
          ],
        ),
      );
      _confirming = false;
      if (discard != true ||
          !mounted ||
          (widget.savingNow?.call() ?? widget.saving)) {
        return;
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !widget.dirty && !widget.saving,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) requestClose();
    },
    child: GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 300) requestClose();
      },
      child: widget.child,
    ),
  );
}

class EditorPanel extends StatelessWidget {
  const EditorPanel({
    required this.children,
    this.mainAxisSize = MainAxisSize.min,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    super.key,
  });
  final List<Widget> children;
  final MainAxisSize mainAxisSize;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final scrollAll =
          constraints.maxHeight < 300 ||
          (constraints.maxHeight < AppSizes.lowHeight && scale >= 1.8);
      if (scrollAll) {
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: crossAxisAlignment,
            children: [
              for (final child in children)
                child is Flexible ? child.child : child,
            ],
          ),
        );
      }
      return Column(
        mainAxisSize: mainAxisSize,
        crossAxisAlignment: crossAxisAlignment,
        children: children,
      );
    },
  );
}

class EditorActions extends StatelessWidget {
  const EditorActions({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: children,
      ),
    ),
  );
}
