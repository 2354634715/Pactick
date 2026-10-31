import '../../../core/localization/app_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/components/feature_page_scaffold.dart';
import '../../../core/components/focus_clock.dart';
import '../../../core/dialogs/task_editor.dart';
import '../../../core/components/section_header.dart';
import '../../../core/components/sync_status_button.dart';
import '../../../core/models/domain_models.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/state/app_scope.dart';
import '../../../core/state_views/state_pane.dart';
import '../../../core/utilities/formatters.dart';
import '../dialogs/app_whitelist_editor.dart';
import '../widgets/focus_desktop_controls.dart';

enum _FocusSection { start, history, policies }

class FocusPage extends StatefulWidget {
  const FocusPage({
    required this.onOpenSettings,
    required this.onFocusEnded,
    super.key,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onFocusEnded;

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  static const _minimumDurationMinutes = 15.0;
  static const _maximumDurationMinutes = 240.0;

  _FocusSection _section = _FocusSection.start;
  String? _selectedTaskId;
  String? _selectedPolicyId;
  double _durationMinutes = 45;
  bool _starting = false;
  String? _startError;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watchData(context);
    if (controller.activeFocusSession != null) {
      return _ActiveFocusView(
        controller: controller,
        onFocusEnded: widget.onFocusEnded,
      );
    }
    final openTasks = controller.tasks
        .where((task) => task.status == TaskStatus.open)
        .toList(growable: false);
    if (!openTasks.any((task) => task.id == _selectedTaskId)) {
      _selectedTaskId = null;
    }
    _selectedPolicyId ??= controller.focusPolicies.firstOrNull?.id;

    return FeaturePageScaffold(
      title: context.tr('专注'),
      subtitle: context.tr('可直接开始，结束后再关联任务'),
      actions: [
        IconButton(
          tooltip: context.tr('专注权限'),
          onPressed: () => setState(() => _section = _FocusSection.policies),
          icon: Badge(
            isLabelVisible: !controller.guardPermissionsGranted,
            child: const Icon(Icons.shield_outlined),
          ),
        ),
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
          tooltip: context.tr('设置'),
          onPressed: widget.onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 400;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<_FocusSection>(
                  segments: [
                    ButtonSegment(
                      value: _FocusSection.start,
                      label: Text(
                        compact ? context.tr('开始') : context.tr('开始专注'),
                      ),
                      icon: const Icon(Icons.play_circle_outline),
                    ),
                    ButtonSegment(
                      value: _FocusSection.history,
                      label: Text(context.tr('历史')),
                      icon: Icon(Icons.history),
                    ),
                    ButtonSegment(
                      value: _FocusSection.policies,
                      label: Text(context.tr('规则')),
                      icon: Icon(Icons.tune),
                    ),
                  ],
                  selected: {_section},
                  onSelectionChanged: (selection) {
                    setState(() => _section = selection.first);
                  },
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          switch (_section) {
            _FocusSection.start => _buildStart(controller),
            _FocusSection.history => _FocusHistory(controller: controller),
            _FocusSection.policies => _FocusPolicies(controller: controller),
          },
        ],
      ),
    );
  }

  Future<void> _start(
    AppController controller,
    TaskItem? task,
    FocusPolicyItem policy,
  ) async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _startError = null;
    });
    try {
      await controller.startFocus(
        task: task,
        durationSeconds: (_durationMinutes * 60).round(),
        policy: policy,
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _startError = context.tr(
            '未能开始专注，请重试：{arg0}',
            args: {'arg0': error},
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Widget _buildStart(AppController controller) {
    final openTasks = controller.tasks
        .where((task) => task.status == TaskStatus.open)
        .toList(growable: false);
    final selectedTask = controller.taskById(_selectedTaskId);
    final selectedPolicy = controller.policyById(_selectedPolicyId);
    final guardSelected =
        selectedPolicy != null && selectedPolicy.mode != FocusPolicyMode.normal;
    final guardNeedsUsageAccess =
        guardSelected && !controller.usageAccessGranted;
    final guardNeedsOverlayAccess =
        guardSelected && !controller.overlayPermissionGranted;
    final guardNeedsAccess = guardNeedsUsageAccess || guardNeedsOverlayAccess;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppSizes.twoPaneMinWidth;
        final configuration = Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('本次专注'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  key: ValueKey(selectedTask?.id),
                  isExpanded: true,
                  initialValue: selectedTask?.id ?? '',
                  decoration: InputDecoration(
                    labelText: context.tr('关联任务（可选）'),
                    helperText: context.tr('未关联时记为“自由专注”，结束后可补充关联'),
                    helperMaxLines: 2,
                    prefixIcon: Icon(Icons.task_alt_outlined),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(context.tr('自由专注（暂不关联任务）')),
                    ),
                    for (final task in openTasks)
                      DropdownMenuItem(
                        value: task.id,
                        child: Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _starting
                      ? null
                      : (value) => setState(() {
                          _selectedTaskId = value == '' ? null : value;
                          final task = controller.taskById(value);
                          if (task?.estimatedDurationSeconds
                              case final seconds?) {
                            _durationMinutes = (seconds / 60).clamp(
                              _minimumDurationMinutes,
                              _maximumDurationMinutes,
                            );
                          }
                        }),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  context.tr('目标时长'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final minutes in [25, 45, 60, 90])
                      ChoiceChip(
                        selected: _durationMinutes.round() == minutes,
                        onSelected: _starting
                            ? null
                            : (_) {
                                setState(
                                  () => _durationMinutes = minutes.toDouble(),
                                );
                              },
                        label: Text(
                          context.tr('{arg0} 分钟', args: {'arg0': minutes}),
                        ),
                      ),
                  ],
                ),
                Slider(
                  value: _durationMinutes,
                  min: _minimumDurationMinutes,
                  max: _maximumDurationMinutes,
                  divisions: 15,
                  label: context.tr(
                    '{arg0} 分钟',
                    args: {'arg0': _durationMinutes.round()},
                  ),
                  onChanged: _starting
                      ? null
                      : (value) => setState(() => _durationMinutes = value),
                ),
                Text(
                  formatDuration(
                    (_durationMinutes * 60).round(),
                    compact: true,
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
          ),
        );
        final policies = Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('专注规则'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                RadioGroup<String>(
                  groupValue: _selectedPolicyId,
                  onChanged: (value) {
                    setState(() => _selectedPolicyId = value);
                  },
                  child: Column(
                    children: [
                      for (final policy in controller.focusPolicies)
                        RadioListTile<String>(
                          value: policy.id,
                          enabled: !_starting,
                          title: Text(policy.displayName),
                          subtitle: Text(_policyDescription(policy)),
                          secondary: Icon(
                            policy.mode != FocusPolicyMode.normal
                                ? Icons.shield_outlined
                                : Icons.self_improvement_outlined,
                          ),
                        ),
                    ],
                  ),
                ),
                if (guardSelected) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: const Icon(Icons.apps_outlined),
                      title: Text(
                        context.tr(
                          '{arg0}白名单',
                          args: {
                            'arg0': controller.whitelistName(
                              selectedTask?.projectId,
                            ),
                          },
                        ),
                      ),
                      subtitle: Text(
                        context.tr(
                          '{arg0} 个应用可在本次专注中使用',
                          args: {
                            'arg0': controller
                                .appWhitelistForProject(selectedTask?.projectId)
                                .length,
                          },
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showAppWhitelistEditor(
                        context,
                        controller: controller,
                        projectId: selectedTask?.projectId,
                      ),
                    ),
                  ),
                ],
                if (guardNeedsUsageAccess) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _PermissionCallout(
                    title: context.tr('深度守护需要使用情况访问'),
                    message: context.tr('用于判断当前打开的应用是否在白名单中。'),
                    actionLabel: context.tr('前往授权'),
                    onAction: controller.openUsageAccessSettings,
                  ),
                ],
                if (guardNeedsOverlayAccess) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _PermissionCallout(
                    title: context.tr('深度守护需要悬浮窗权限'),
                    message: context.tr('用于在非白名单应用上方显示「回到专注」提醒。'),
                    actionLabel: context.tr('前往授权'),
                    onAction: controller.openOverlayPermissionSettings,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (!controller.canStartFocus) ...[
                  Text(
                    context.tr('此工作区已有其他设备的活跃专注。请在发起设备结束后同步；本机只能在历史中查看该记录。'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_startError != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _startError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                FilledButton.icon(
                  onPressed:
                      _starting ||
                          selectedPolicy == null ||
                          guardNeedsAccess ||
                          !controller.canStartFocus
                      ? null
                      : () => _start(controller, selectedTask, selectedPolicy),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    _starting ? context.tr('正在开始…') : context.tr('开始专注'),
                  ),
                ),
              ],
            ),
          ),
        );
        if (!wide) {
          return Column(
            children: [
              configuration,
              const SizedBox(height: AppSpacing.md),
              policies,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: configuration),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: policies),
          ],
        );
      },
    );
  }

  String _policyDescription(FocusPolicyItem policy) {
    return switch (policy.mode) {
      FocusPolicyMode.normal => context.tr('允许暂停和提前结束，记录实际专注时间'),
      FocusPolicyMode.guard => context.tr(
        '打开非白名单应用时显示顶部提醒，离开超过 {arg0} 次计为中断',
        args: {'arg0': policy.maxAppExits ?? 0},
      ),
      FocusPolicyMode.strict => context.tr(
        '禁止暂停和提前完成；非白名单应用计为中断；紧急结束需等待 30 秒并填写原因',
      ),
    };
  }
}

class _ActiveFocusView extends StatefulWidget {
  const _ActiveFocusView({
    required this.controller,
    required this.onFocusEnded,
  });
  final AppController controller;
  final VoidCallback onFocusEnded;
  @override
  State<_ActiveFocusView> createState() => _ActiveFocusViewState();
}

class _ActiveFocusViewState extends State<_ActiveFocusView> {
  bool _busy = false;
  String? _error;
  AppController get controller => widget.controller;

  Future<void> _pause() async {
    if (_busy || !canPauseActiveFocus(controller)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (controller.activeFocusSession?.status == FocusSessionStatus.paused) {
        await controller.resumeFocus();
      } else {
        await controller.pauseFocus();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = context.tr('专注状态未保存，请重试：{arg0}', args: {'arg0': error}),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = controller.activeFocusSession;
    if (session == null) return const SizedBox.shrink();
    final task = controller.taskById(session.taskId);
    final policy = controller.policyById(session.focusPolicyId);
    final paused = session.status == FocusSessionStatus.paused;
    return LayoutBuilder(
      builder: (context, constraints) {
        final low = constraints.maxHeight < AppSizes.lowHeight;
        final ring =
            !low &&
            MediaQuery.textScalerOf(context).scale(16) <= 20 &&
            constraints.maxWidth >= 360;
        return FeaturePageScaffold(
          title: paused ? context.tr('专注已暂停') : context.tr('专注进行中'),
          maxWidth: AppSizes.compactContentMax,
          body: Column(
            children: [
              InkWell(
                onTap: task == null
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(context.tr('当前任务')),
                          content: SingleChildScrollView(
                            child: SelectableText(task.title),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(context.tr('关闭')),
                            ),
                          ],
                        ),
                      ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Text(
                    controller.focusSessionTitle(session),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                liveRegion: true,
                child: Text(
                  '${policy?.displayName ?? context.tr("专注")} · ${paused ? context.tr("已暂停") : context.tr("正在记录")}',
                ),
              ),
              SizedBox(height: low ? AppSpacing.md : AppSpacing.xl),
              FocusClock(controller: controller, showRing: ring),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (paused) ...[
                    FilledButton.icon(
                      onPressed: _busy || !canPauseActiveFocus(controller)
                          ? null
                          : _pause,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        _busy ? context.tr('正在保存…') : context.tr('继续'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _busy ||
                              (policy?.mode == FocusPolicyMode.strict &&
                                  controller.activeFocusRemainingSeconds > 0)
                          ? null
                          : () => _complete(task, policy),
                      icon: const Icon(Icons.done),
                      label: Text(context.tr('完成专注')),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      onPressed:
                          _busy ||
                              (policy?.mode == FocusPolicyMode.strict &&
                                  controller.activeFocusRemainingSeconds > 0)
                          ? null
                          : () => _complete(task, policy),
                      icon: const Icon(Icons.done),
                      label: Text(
                        _busy ? context.tr('正在保存…') : context.tr('完成专注'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || !canPauseActiveFocus(controller)
                          ? null
                          : _pause,
                      icon: const Icon(Icons.pause),
                      label: Text(context.tr('暂停')),
                    ),
                  ],
                  TextButton.icon(
                    onPressed: _busy ? null : () => _abandon(policy),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(context.tr('提前结束')),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              OpenFocusDesktopButton(controller: controller),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.tr('目标时长结束后继续记录，点击“完成专注”保存本次时间。'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                policy?.mode != FocusPolicyMode.normal
                    ? context.tr(
                        '{arg0}模式不允许暂停。{arg1}白名单 {arg2} 个应用 · 已离开 {arg3} 次',
                        args: {
                          'arg0': policy?.mode == FocusPolicyMode.strict
                              ? tr('严格')
                              : tr('守护'),
                          'arg1': controller.whitelistName(task?.projectId),
                          'arg2': controller
                              .appWhitelistForProject(task?.projectId)
                              .length,
                          'arg3': session.appExitCount,
                        },
                      )
                    : context.tr('切到后台后继续计时，暂停期间不计入实际专注时间。'),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _complete(TaskItem? task, FocusPolicyItem? policy) async {
    if (_busy) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await controller.finishFocus();
      if (session == null || !navigator.mounted) return;
      final result = await _showReview(navigator, session, task, policy);
      if (result) widget.onFocusEnded();
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = context.tr('专注记录未保存，请重试：{arg0}', args: {'arg0': error}),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _abandon(FocusPolicyItem? policy) async {
    final finished = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _EarlyFocusExitDialog(controller: controller, policy: policy),
    );
    if (finished == true) widget.onFocusEnded();
  }

  Future<bool> _showReview(
    NavigatorState navigator,
    FocusSessionItem session,
    TaskItem? task,
    FocusPolicyItem? policy,
  ) async {
    final accountId = controller.repository.selectedAccountId;
    var saving = false;
    String? error;
    final result = await navigator.push<String>(
      DialogRoute<String>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => PopScope(
            canPop: !saving,
            child: AlertDialog(
              scrollable: true,
              title: Text(context.tr('本次专注已记录')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(context.tr('专注结束，任务状态尚未改变。')),
                  _ReviewRow(
                    label: context.tr('关联任务'),
                    value: controller.focusSessionTitle(session),
                  ),
                  if (controller.canAssociateFocusSessionTask(session))
                    OutlinedButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              final associated =
                                  await _showFocusTaskAssociation(
                                    context,
                                    controller: controller,
                                    session: session,
                                    expectedAccountId: accountId,
                                  );
                              if (associated != null && dialogContext.mounted) {
                                update(() {
                                  task = associated;
                                  session = controller.focusSessions.firstWhere(
                                    (item) => item.id == session.id,
                                  );
                                });
                              }
                            },
                      icon: const Icon(Icons.link),
                      label: Text(context.tr('关联任务')),
                    ),
                  _ReviewRow(
                    label: context.tr('计划时长'),
                    value: formatDuration(
                      session.plannedDurationSeconds,
                      compact: true,
                    ),
                  ),
                  _ReviewRow(
                    label: context.tr('实际专注'),
                    value: formatDuration(
                      session.actualDurationSeconds,
                      compact: true,
                    ),
                  ),
                  _ReviewRow(
                    label: context.tr('中断次数'),
                    value: context.tr(
                      '{arg0} 次',
                      args: {'arg0': session.interruptionCount},
                    ),
                  ),
                  if (error != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.pop(dialogContext, 'keep'),
                  child: Text(
                    task == null ? context.tr('暂不关联') : context.tr('暂不完成任务'),
                  ),
                ),
                OutlinedButton(
                  onPressed: saving || policy == null
                      ? null
                      : () async {
                          update(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            final currentTask = controller.taskById(task?.id);
                            if (task != null &&
                                (currentTask == null ||
                                    currentTask.status != TaskStatus.open)) {
                              throw StateError(context.tr('任务已完成或不可用'));
                            }
                            await controller.startFocus(
                              task: currentTask,
                              durationSeconds: session.plannedDurationSeconds,
                              policy: policy,
                            );
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, 'continue');
                            }
                          } catch (failure) {
                            if (dialogContext.mounted) {
                              update(
                                () => error = context.tr(
                                  '未能开始，请重试：{arg0}',
                                  args: {'arg0': failure},
                                ),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              update(() => saving = false);
                            }
                          }
                        },
                  child: Text(context.tr('再专注一次')),
                ),
                FilledButton(
                  onPressed: saving || task == null
                      ? null
                      : () async {
                          update(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            final currentTask = controller.taskById(task?.id);
                            if (currentTask != null &&
                                !currentTask.isCompleted) {
                              await controller.toggleTask(currentTask);
                            }
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, 'complete');
                            }
                          } catch (failure) {
                            if (dialogContext.mounted) {
                              update(
                                () => error = context.tr(
                                  '任务未保存，请重试：{arg0}',
                                  args: {'arg0': failure},
                                ),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              update(() => saving = false);
                            }
                          }
                        },
                  child: Text(
                    saving ? context.tr('正在保存…') : context.tr('完成任务'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return result != 'continue';
  }
}

class _EarlyFocusExitDialog extends StatefulWidget {
  const _EarlyFocusExitDialog({required this.controller, this.policy});
  final AppController controller;
  final FocusPolicyItem? policy;

  @override
  State<_EarlyFocusExitDialog> createState() => _EarlyFocusExitDialogState();
}

class _EarlyFocusExitDialogState extends State<_EarlyFocusExitDialog> {
  final _reason = TextEditingController();
  late final Timer _ticker;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.beginEarlyFocusExit();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    widget.controller.cancelEarlyFocusExit();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_saving || widget.controller.earlyExitRemainingSeconds > 0) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = await widget.controller.finishFocus(
        status: FocusSessionStatus.abandoned,
        reason:
            _reason.text.trim().isEmpty &&
                widget.policy?.mode != FocusPolicyMode.strict
            ? context.tr('用户提前结束')
            : _reason.text.trim(),
      );
      if (mounted && session != null) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(
          () => _error = context.tr('未保存，请重试：{arg0}', args: {'arg0': failure}),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.controller.earlyExitRemainingSeconds;
    final requiresReason =
        widget.policy?.mode == FocusPolicyMode.strict ||
        widget.policy?.earlyExitMode == 'reason';
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text(context.tr('提前结束专注？')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('保留本次实际专注时间，不会完成任务。')),
            if (remaining > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.tr(
                  '还需等待 {arg0} 秒，可随时返回继续专注。',
                  args: {'arg0': remaining},
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _reason,
              enabled: !_saving,
              maxLength: 1000,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: requiresReason
                    ? context.tr('原因（必填）')
                    : context.tr('原因'),
                hintText: context.tr('例如：需要处理紧急电话'),
              ),
            ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: Text(context.tr('继续专注')),
          ),
          FilledButton(
            onPressed:
                _saving ||
                    remaining > 0 ||
                    (requiresReason && _reason.text.trim().isEmpty)
                ? null
                : _finish,
            child: Text(
              _saving
                  ? context.tr('正在保存…')
                  : remaining > 0
                  ? context.tr('等待 {arg0} 秒', args: {'arg0': remaining})
                  : context.tr('结束'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusHistory extends StatelessWidget {
  const _FocusHistory({required this.controller});
  final AppController controller;
  String _status(FocusSessionItem session) => switch (session.status) {
    FocusSessionStatus.running => tr('其他设备专注中 · 只读'),
    FocusSessionStatus.paused => tr('其他设备已暂停 · 只读'),
    FocusSessionStatus.completed => tr('已完成专注'),
    FocusSessionStatus.abandoned => tr('提前结束'),
    FocusSessionStatus.interrupted => tr('已中断'),
  };
  @override
  Widget build(BuildContext context) {
    final sessions = controller.focusSessions
        .where(
          (session) =>
              !session.isActive || !controller.isLocalFocusSession(session),
        )
        .toList();
    if (sessions.isEmpty) {
      return StatePane.empty(
        title: context.tr('还没有专注记录'),
        message: context.tr('专注结束后，计划时长和实际专注时间会显示在这里。'),
      );
    }
    return Column(
      children: [
        for (final session in sessions) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              session.status == FocusSessionStatus.completed
                  ? Icons.done
                  : Icons.history,
            ),
            title: Text(
              controller.focusSessionTitle(session),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              context.tr(
                '{arg0}\n{arg1} {arg2} · 计划 {arg3} · 已记录 {arg4}\n设备 {arg5}',
                args: {
                  'arg0': _status(session),
                  'arg1': formatMonthDay(session.startedAt),
                  'arg2': formatClock(session.startedAt),
                  'arg3': formatDuration(
                    session.plannedDurationSeconds,
                    compact: true,
                  ),
                  'arg4': formatDuration(
                    session.actualDurationSeconds,
                    compact: true,
                  ),
                  'arg5': session.startedDeviceId,
                },
              ),
            ),
            trailing: controller.canAssociateFocusSessionTask(session)
                ? const Icon(Icons.link)
                : null,
            onTap: () async {
              final accountId = controller.repository.selectedAccountId;
              final associate = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  scrollable: true,
                  title: Text(controller.focusSessionTitle(session)),
                  content: Text(
                    context.tr(
                      '{arg0}\n开始 {arg1}\n设备 {arg2}\n计划 {arg3}\n已记录 {arg4}\n中断 {arg5} 次{arg6}',
                      args: {
                        'arg0': _status(session),
                        'arg1': session.startedAt,
                        'arg2': session.startedDeviceId,
                        'arg3': formatDuration(session.plannedDurationSeconds),
                        'arg4': formatDuration(session.actualDurationSeconds),
                        'arg5': session.interruptionCount,
                        'arg6': session.terminationReason == null
                            ? ''
                            : tr(
                                '\n原因 {arg0}',
                                args: {'arg0': session.terminationReason},
                              ),
                      },
                    ),
                  ),
                  actions: [
                    if (controller.canAssociateFocusSessionTask(session))
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(context.tr('关联任务')),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.tr('关闭')),
                    ),
                  ],
                ),
              );
              if (associate == true && context.mounted) {
                await _showFocusTaskAssociation(
                  context,
                  controller: controller,
                  session: session,
                  expectedAccountId: accountId,
                );
              }
            },
          ),
          const Divider(),
        ],
      ],
    );
  }
}

Future<TaskItem?> _showFocusTaskAssociation(
  BuildContext context, {
  required AppController controller,
  required FocusSessionItem session,
  String? expectedAccountId,
}) {
  final accountId =
      expectedAccountId ?? controller.repository.selectedAccountId;
  void checkWorkspace() {
    if (accountId != controller.repository.selectedAccountId ||
        controller.isSwitchingSyncAccount) {
      throw StateError(tr('工作区已切换，请关闭弹窗后重新选择记录。'));
    }
  }

  String? selectedTaskId;
  var saving = false;
  String? error;
  return showDialog<TaskItem>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) {
        final tasks = controller.tasks;
        if (!tasks.any((task) => task.id == selectedTaskId)) {
          selectedTaskId = null;
        }
        return PopScope(
          canPop: !saving,
          child: AlertDialog(
            scrollable: true,
            title: Text(context.tr('关联任务')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.tr('关联后，本次专注时长计入所选任务；任务完成状态不变，关联后不能更换任务。')),
                const SizedBox(height: AppSpacing.md),
                if (tasks.isEmpty)
                  Text(context.tr('还没有任务，可先新建任务。暂不关联时保留“自由专注”名称。'))
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedTaskId),
                    initialValue: selectedTaskId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: context.tr('选择任务')),
                    items: [
                      for (final task in tasks)
                        DropdownMenuItem(
                          value: task.id,
                          child: Text(
                            task.isCompleted
                                ? context.tr(
                                    '{arg0}（已完成）',
                                    args: {'arg0': task.title},
                                  )
                                : task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) => update(() => selectedTaskId = value),
                  ),
                TextButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          update(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            checkWorkspace();
                            final task = await showTaskEditor(
                              context,
                              controller: controller,
                            );
                            checkWorkspace();
                            if (dialogContext.mounted && task != null) {
                              update(() => selectedTaskId = task.id);
                            }
                          } catch (failure) {
                            if (dialogContext.mounted) {
                              update(
                                () => error = context.tr(
                                  '未能选择新任务：{arg0}',
                                  args: {'arg0': failure},
                                ),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              update(() => saving = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('新建任务')),
                ),
                if (error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: Text(context.tr('暂不关联')),
              ),
              FilledButton(
                onPressed: saving || selectedTaskId == null
                    ? null
                    : () async {
                        update(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          checkWorkspace();
                          final task = controller.taskById(selectedTaskId);
                          if (task == null) throw StateError(tr('任务已不可用'));
                          await controller.associateFocusSessionTask(
                            sessionId: session.id,
                            task: task,
                          );
                          checkWorkspace();
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, task);
                          }
                        } catch (failure) {
                          if (dialogContext.mounted) {
                            update(
                              () => error = context.tr(
                                '关联未保存，请重试：{arg0}',
                                args: {'arg0': failure},
                              ),
                            );
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            update(() => saving = false);
                          }
                        }
                      },
                child: Text(saving ? context.tr('正在保存…') : context.tr('保存关联')),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _FocusPolicies extends StatelessWidget {
  const _FocusPolicies({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PermissionCallout(
          title: controller.usageAccessGranted
              ? context.tr('使用情况访问已授权')
              : context.tr('需要使用情况访问'),
          message: controller.usageAccessGranted
              ? context.tr('深度守护可以判断当前打开的应用。')
              : context.tr('只用于在专注进行时识别前台应用。'),
          actionLabel: controller.usageAccessGranted
              ? context.tr('重新检查')
              : context.tr('前往授权'),
          onAction: controller.usageAccessGranted
              ? controller.refreshGuardPermissions
              : controller.openUsageAccessSettings,
        ),
        const SizedBox(height: AppSpacing.sm),
        _PermissionCallout(
          title: controller.overlayPermissionGranted
              ? context.tr('悬浮窗权限已授权')
              : context.tr('需要悬浮窗权限'),
          message: controller.overlayPermissionGranted
              ? context.tr('非白名单应用打开后，屏幕顶部会显示返回提醒。')
              : context.tr('只显示顶部提醒卡片，不会遮挡整个屏幕。'),
          actionLabel: controller.overlayPermissionGranted
              ? context.tr('重新检查')
              : context.tr('前往授权'),
          onAction: controller.overlayPermissionGranted
              ? controller.refreshGuardPermissions
              : controller.openOverlayPermissionSettings,
        ),
        SectionHeader(
          title: context.tr('应用白名单'),
          subtitle: context.tr('按收集箱或项目分别配置；可随本地备份迁移，不上传同步服务器'),
        ),
        for (final projectId in <String?>[
          null,
          ...controller.projects.map((project) => project.id),
        ]) ...[
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              leading: CircleAvatar(
                child: Icon(
                  projectId == null
                      ? Icons.inbox_outlined
                      : Icons.folder_outlined,
                ),
              ),
              title: Text(controller.whitelistName(projectId)),
              subtitle: Text(
                context.tr(
                  '{arg0} 个白名单应用',
                  args: {
                    'arg0': controller.appWhitelistForProject(projectId).length,
                  },
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showAppWhitelistEditor(
                context,
                controller: controller,
                projectId: projectId,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        SectionHeader(title: context.tr('专注规则')),
        for (final policy in controller.focusPolicies) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    child: Icon(
                      policy.mode == FocusPolicyMode.guard
                          ? Icons.shield_outlined
                          : Icons.self_improvement_outlined,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          policy.displayName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          policy.mode == FocusPolicyMode.guard
                              ? context.tr(
                                  '顶部提醒 · 分类白名单 · 离开超过 {arg0} 次计为中断',
                                  args: {'arg0': policy.maxAppExits ?? 0},
                                )
                              : policy.mode == FocusPolicyMode.strict
                              ? context.tr(
                                  '禁止暂停和提前完成；非白名单应用计为中断；紧急结束需等待 30 秒并填写原因',
                                )
                              : context.tr('允许暂停 · 允许提前结束'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Chip(label: Text(policy.mode.label)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _PermissionCallout extends StatefulWidget {
  const _PermissionCallout({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;
  @override
  State<_PermissionCallout> createState() => _PermissionCalloutState();
}

class _PermissionCalloutState extends State<_PermissionCallout> {
  bool _busy = false;
  String? _error;
  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onAction();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = context.tr(
            '权限操作未完成，普通专注仍可使用。请重试：{arg0}',
            args: {'arg0': error},
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xxs),
        Text(widget.message),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton(
            onPressed: _busy ? null : _run,
            child: Text(_busy ? context.tr('正在检查…') : widget.actionLabel),
          ),
        ),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
