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
        .where((task) => !task.isCompleted)
        .toList(growable: false);
    if (!openTasks.any((task) => task.id == _selectedTaskId)) {
      _selectedTaskId = openTasks.firstOrNull?.id;
    }
    _selectedPolicyId ??= controller.focusPolicies.firstOrNull?.id;

    return FeaturePageScaffold(
      title: '专注',
      subtitle: '选择任务和时长，记录实际专注时间',
      actions: [
        IconButton(
          tooltip: '专注权限',
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
          tooltip: '设置',
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
                      label: Text(compact ? '开始' : '开始专注'),
                      icon: const Icon(Icons.play_circle_outline),
                    ),
                    const ButtonSegment(
                      value: _FocusSection.history,
                      label: Text('历史'),
                      icon: Icon(Icons.history),
                    ),
                    const ButtonSegment(
                      value: _FocusSection.policies,
                      label: Text('规则'),
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
    TaskItem task,
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
      if (mounted) setState(() => _startError = '未能开始专注，请重试：$error');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Widget _buildStart(AppController controller) {
    if (!controller.tasks.any((task) => !task.isCompleted)) {
      return StatePane.empty(
        title: '先添加一个任务',
        message: '专注会关联到未完成任务，记录实际投入的时间。',
        actionLabel: '新建任务',
        onAction: () => showTaskEditor(context, controller: controller),
      );
    }
    final openTasks = controller.tasks
        .where((task) => !task.isCompleted)
        .toList(growable: false);
    final selectedTask = controller.taskById(_selectedTaskId);
    final selectedPolicy = controller.policyById(_selectedPolicyId);
    final guardSelected = selectedPolicy?.mode == FocusPolicyMode.guard;
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
                Text('本次专注', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  key: ValueKey(selectedTask?.id),
                  isExpanded: true,
                  initialValue: selectedTask?.id,
                  decoration: const InputDecoration(
                    labelText: '选择任务',
                    prefixIcon: Icon(Icons.task_alt_outlined),
                  ),
                  items: [
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
                          _selectedTaskId = value;
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
                Text('目标时长', style: Theme.of(context).textTheme.titleMedium),
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
                        label: Text('$minutes 分钟'),
                      ),
                  ],
                ),
                Slider(
                  value: _durationMinutes,
                  min: _minimumDurationMinutes,
                  max: _maximumDurationMinutes,
                  divisions: 15,
                  label: '${_durationMinutes.round()} 分钟',
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
                Text('专注规则', style: Theme.of(context).textTheme.headlineSmall),
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
                          enabled:
                              !_starting &&
                              policy.mode != FocusPolicyMode.strict,
                          title: Text(policy.name),
                          subtitle: Text(_policyDescription(policy)),
                          secondary: Icon(
                            policy.mode == FocusPolicyMode.guard
                                ? Icons.shield_outlined
                                : Icons.self_improvement_outlined,
                          ),
                        ),
                    ],
                  ),
                ),
                if (guardSelected && selectedTask != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppRadii.medium),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.apps_outlined),
                      title: Text(
                        '${controller.whitelistName(selectedTask.projectId)}白名单',
                      ),
                      subtitle: Text(
                        '${controller.appWhitelistForTask(selectedTask).length} 个应用可在本次专注中使用',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showAppWhitelistEditor(
                        context,
                        controller: controller,
                        projectId: selectedTask.projectId,
                      ),
                    ),
                  ),
                ],
                if (guardNeedsUsageAccess) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _PermissionCallout(
                    title: '深度守护需要使用情况访问',
                    message: '用于判断当前打开的应用是否在白名单中。',
                    actionLabel: '前往授权',
                    onAction: controller.openUsageAccessSettings,
                  ),
                ],
                if (guardNeedsOverlayAccess) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _PermissionCallout(
                    title: '深度守护需要悬浮窗权限',
                    message: '用于在非白名单应用上方显示「回到专注」提醒。',
                    actionLabel: '前往授权',
                    onAction: controller.openOverlayPermissionSettings,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (!controller.canStartFocus) ...[
                  const Text('此工作区已有其他设备的活跃专注。请在发起设备结束后同步；本机只能在历史中查看该记录。'),
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
                          selectedTask == null ||
                          selectedPolicy == null ||
                          selectedPolicy.mode == FocusPolicyMode.strict ||
                          guardNeedsAccess ||
                          !controller.canStartFocus
                      ? null
                      : () => _start(controller, selectedTask, selectedPolicy),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(_starting ? '正在开始…' : '开始专注'),
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
      FocusPolicyMode.normal => '允许暂停和提前结束，记录实际专注时间',
      FocusPolicyMode.guard =>
        '打开非白名单应用时显示顶部提醒，离开超过 ${policy.maxAppExits ?? 0} 次计为中断',
      FocusPolicyMode.strict => '此模式尚未开放',
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
      if (mounted) setState(() => _error = '专注状态未保存，请重试：$error');
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
          title: paused ? '专注已暂停' : '专注进行中',
          maxWidth: AppSizes.compactContentMax,
          body: Column(
            children: [
              InkWell(
                onTap: task == null
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('当前任务'),
                          content: SingleChildScrollView(
                            child: SelectableText(task.title),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Text(
                    task?.title ?? '未命名任务',
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
                  '${policy?.name ?? '专注'} · ${paused ? '已暂停' : '正在记录'}',
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
                      label: Text(_busy ? '正在保存…' : '继续'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _complete(task, policy),
                      icon: const Icon(Icons.done),
                      label: const Text('完成专注'),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _complete(task, policy),
                      icon: const Icon(Icons.done),
                      label: Text(_busy ? '正在保存…' : '完成专注'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || !canPauseActiveFocus(controller)
                          ? null
                          : _pause,
                      icon: const Icon(Icons.pause),
                      label: const Text('暂停'),
                    ),
                  ],
                  TextButton.icon(
                    onPressed: _busy ? null : () => _abandon(policy),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('提前结束'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '目标时长结束后继续记录，点击“完成专注”保存本次时间。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                policy?.mode == FocusPolicyMode.guard
                    ? '守护模式不允许暂停。${controller.whitelistName(task?.projectId)}白名单 ${controller.appWhitelistForProject(task?.projectId).length} 个应用 · 已离开 ${session.appExitCount} 次'
                    : '切到后台后继续计时，暂停期间不计入实际专注时间。',
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
      if (mounted) setState(() => _error = '专注记录未保存，请重试：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _abandon(FocusPolicyItem? policy) async {
    var reason = '';
    var saving = false;
    String? error;
    final finished = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !saving,
          child: AlertDialog(
            scrollable: true,
            title: const Text('提前结束专注？'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('保留本次实际专注时间，不会完成任务。'),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  enabled: !saving,
                  maxLength: 1000,
                  onChanged: (value) => reason = value,
                  decoration: const InputDecoration(
                    labelText: '原因',
                    hintText: '例如：需要处理紧急电话',
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
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('继续专注'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        update(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          final session = await controller.finishFocus(
                            status: FocusSessionStatus.abandoned,
                            reason: reason.trim().isEmpty
                                ? '用户提前结束'
                                : reason.trim(),
                          );
                          if (dialogContext.mounted && session != null) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (failure) {
                          if (dialogContext.mounted) {
                            update(() => error = '未保存，请重试：$failure');
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            update(() => saving = false);
                          }
                        }
                      },
                child: Text(saving ? '正在保存…' : '结束'),
              ),
            ],
          ),
        ),
      ),
    );
    if (finished == true) widget.onFocusEnded();
  }

  Future<bool> _showReview(
    NavigatorState navigator,
    FocusSessionItem session,
    TaskItem? task,
    FocusPolicyItem? policy,
  ) async {
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
              title: const Text('本次专注已记录'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('专注结束，任务状态尚未改变。'),
                  _ReviewRow(
                    label: '计划时长',
                    value: formatDuration(
                      session.plannedDurationSeconds,
                      compact: true,
                    ),
                  ),
                  _ReviewRow(
                    label: '实际专注',
                    value: formatDuration(
                      session.actualDurationSeconds,
                      compact: true,
                    ),
                  ),
                  _ReviewRow(
                    label: '中断次数',
                    value: '${session.interruptionCount} 次',
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
                  child: const Text('暂不完成任务'),
                ),
                OutlinedButton(
                  onPressed: saving || task == null || policy == null
                      ? null
                      : () async {
                          update(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            final currentTask = controller.taskById(task.id);
                            if (currentTask == null ||
                                currentTask.isCompleted) {
                              throw StateError('任务已完成或不可用');
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
                              update(() => error = '未能开始，请重试：$failure');
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              update(() => saving = false);
                            }
                          }
                        },
                  child: const Text('再专注一次'),
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
                            final currentTask = controller.taskById(task.id);
                            if (currentTask != null &&
                                !currentTask.isCompleted) {
                              await controller.toggleTask(currentTask);
                            }
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, 'complete');
                            }
                          } catch (failure) {
                            if (dialogContext.mounted) {
                              update(() => error = '任务未保存，请重试：$failure');
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              update(() => saving = false);
                            }
                          }
                        },
                  child: Text(saving ? '正在保存…' : '完成任务'),
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

class _FocusHistory extends StatelessWidget {
  const _FocusHistory({required this.controller});
  final AppController controller;
  String _status(FocusSessionItem session) => switch (session.status) {
    FocusSessionStatus.running => '其他设备专注中 · 只读',
    FocusSessionStatus.paused => '其他设备已暂停 · 只读',
    FocusSessionStatus.completed => '已完成专注',
    FocusSessionStatus.abandoned => '提前结束',
    FocusSessionStatus.interrupted => '已中断',
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
        title: '还没有专注记录',
        message: '专注结束后，计划时长和实际专注时间会显示在这里。',
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
              controller.taskById(session.taskId)?.title ?? '未命名任务',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_status(session)}\n${formatMonthDay(session.startedAt)} ${formatClock(session.startedAt)} · 计划 ${formatDuration(session.plannedDurationSeconds, compact: true)} · 已记录 ${formatDuration(session.actualDurationSeconds, compact: true)}\n设备 ${session.startedDeviceId}',
            ),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                scrollable: true,
                title: Text(
                  controller.taskById(session.taskId)?.title ?? '未命名任务',
                ),
                content: Text(
                  '${_status(session)}\n开始 ${session.startedAt}\n设备 ${session.startedDeviceId}\n计划 ${formatDuration(session.plannedDurationSeconds)}\n已记录 ${formatDuration(session.actualDurationSeconds)}\n中断 ${session.interruptionCount} 次${session.terminationReason == null ? '' : '\n原因 ${session.terminationReason}'}',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
        ],
      ],
    );
  }
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
          title: controller.usageAccessGranted ? '使用情况访问已授权' : '需要使用情况访问',
          message: controller.usageAccessGranted
              ? '深度守护可以判断当前打开的应用。'
              : '只用于在专注进行时识别前台应用。',
          actionLabel: controller.usageAccessGranted ? '重新检查' : '前往授权',
          onAction: controller.usageAccessGranted
              ? controller.refreshGuardPermissions
              : controller.openUsageAccessSettings,
        ),
        const SizedBox(height: AppSpacing.sm),
        _PermissionCallout(
          title: controller.overlayPermissionGranted ? '悬浮窗权限已授权' : '需要悬浮窗权限',
          message: controller.overlayPermissionGranted
              ? '非白名单应用打开后，屏幕顶部会显示返回提醒。'
              : '只显示顶部提醒卡片，不会遮挡整个屏幕。',
          actionLabel: controller.overlayPermissionGranted ? '重新检查' : '前往授权',
          onAction: controller.overlayPermissionGranted
              ? controller.refreshGuardPermissions
              : controller.openOverlayPermissionSettings,
        ),
        const SectionHeader(
          title: '应用白名单',
          subtitle: '按收集箱或项目分别配置；可随本地备份迁移，不上传同步服务器',
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
                '${controller.appWhitelistForProject(projectId).length} 个白名单应用',
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
        const SectionHeader(title: '专注规则'),
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
                          policy.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          policy.mode == FocusPolicyMode.guard
                              ? '顶部提醒 · 分类白名单 · 离开超过 ${policy.maxAppExits ?? 0} 次计为中断'
                              : policy.mode == FocusPolicyMode.strict
                              ? '暂不可用'
                              : '允许暂停 · 允许提前结束',
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
      if (mounted) setState(() => _error = '权限操作未完成，普通专注仍可使用。请重试：$error');
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
            child: Text(_busy ? '正在检查…' : widget.actionLabel),
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
