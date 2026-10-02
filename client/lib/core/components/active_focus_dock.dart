import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../models/domain_models.dart';
import '../state/app_controller.dart';
import 'focus_clock.dart';

class ActiveFocusDock extends StatefulWidget {
  const ActiveFocusDock({
    required this.controller,
    required this.onOpen,
    super.key,
  });
  final AppController controller;
  final VoidCallback onOpen;
  @override
  State<ActiveFocusDock> createState() => _ActiveFocusDockState();
}

class _ActiveFocusDockState extends State<ActiveFocusDock> {
  bool _busy = false;
  String? _error;
  Future<void> _toggle() async {
    if (_busy || !canPauseActiveFocus(widget.controller)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.controller.activeFocusSession?.status ==
          FocusSessionStatus.paused) {
        await widget.controller.resumeFocus();
      } else {
        await widget.controller.pauseFocus();
      }
    } catch (error) {
      if (mounted) setState(() => _error = '专注状态未保存，请重试：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final session = controller.activeFocusSession;
    if (session == null) return const SizedBox.shrink();
    final task = controller.taskById(session.taskId);
    final paused = session.status == FocusSessionStatus.paused;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: widget.onOpen,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task?.title ?? '未命名任务',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Wrap(
                              spacing: AppSpacing.xs,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Semantics(
                                  liveRegion: true,
                                  child: Text(paused ? '已暂停' : '专注中'),
                                ),
                                FocusClock(
                                  controller: controller,
                                  compact: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (canPauseActiveFocus(controller))
                    IconButton(
                      tooltip: paused ? '继续专注' : '暂停专注',
                      onPressed: _busy ? null : _toggle,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(paused ? Icons.play_arrow : Icons.pause),
                    ),
                  IconButton(
                    tooltip: '打开专注页面',
                    onPressed: widget.onOpen,
                    icon: const Icon(Icons.open_in_full),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
