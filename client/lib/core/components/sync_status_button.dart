import '../../core/localization/app_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../models/domain_models.dart';
import '../state/app_controller.dart';
import '../utilities/formatters.dart';

class SyncStatusButton extends StatelessWidget {
  const SyncStatusButton({
    required this.phase,
    required this.pendingCount,
    required this.onPressed,
    super.key,
  });

  final SyncPhase phase;
  final int pendingCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (phase) {
      SyncPhase.localOnly => (
        Icons.cloud_off_outlined,
        pendingCount == 0
            ? context.tr('仅本地')
            : context.tr('仅本地 · {arg0} 项更改', args: {'arg0': pendingCount}),
        scheme.onSurfaceVariant,
      ),
      SyncPhase.synced => (
        Icons.cloud_done_outlined,
        context.tr('已同步'),
        scheme.primary,
      ),
      SyncPhase.pending => (
        Icons.cloud_upload_outlined,
        pendingCount == 0
            ? context.tr('等待首次同步')
            : context.tr('{arg0} 项待同步', args: {'arg0': pendingCount}),
        scheme.tertiary,
      ),
      SyncPhase.syncing => (Icons.sync, context.tr('正在同步'), scheme.primary),
      SyncPhase.offline => (
        Icons.cloud_off_outlined,
        context.tr('离线可用'),
        scheme.onSurfaceVariant,
      ),
      SyncPhase.attention => (
        Icons.sync_problem_outlined,
        context.tr('同步异常'),
        scheme.error,
      ),
    };
    return Semantics(
      label: context.tr('同步状态：{arg0}', args: {'arg0': label}),
      button: true,
      child: IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: Badge(
          isLabelVisible: pendingCount > 0,
          label: Text('$pendingCount'),
          child: Icon(icon, color: color),
        ),
      ),
    );
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({required this.pendingCount, super.key});

  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.warningContainer,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(
          color: scheme.onWarningContainer.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: scheme.onWarningContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              pendingCount == 0
                  ? context.tr('当前无法连接服务器，仍可使用本机功能。')
                  : context.tr(
                      '已保存到本机，恢复连接后将同步 {arg0} 项更改。',
                      args: {'arg0': pendingCount},
                    ),
              style: TextStyle(color: scheme.onWarningContainer),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showSyncStatusPanel(
  BuildContext context, {
  required AppController controller,
  VoidCallback? onOpenSettings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _SyncStatusPanel(
        controller: controller,
        onOpenSettings: onOpenSettings,
      ),
    ),
  );
}

class _SyncStatusPanel extends StatelessWidget {
  const _SyncStatusPanel({required this.controller, this.onOpenSettings});

  final AppController controller;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, accent) = switch (controller.syncPhase) {
      SyncPhase.synced => (Icons.cloud_done_rounded, scheme.primary),
      SyncPhase.pending => (Icons.cloud_upload_rounded, scheme.tertiary),
      SyncPhase.syncing => (Icons.sync_rounded, scheme.primary),
      SyncPhase.offline => (Icons.cloud_off_rounded, scheme.onSurfaceVariant),
      SyncPhase.attention => (Icons.sync_problem_rounded, scheme.error),
      SyncPhase.localOnly => (Icons.phone_android_rounded, scheme.primary),
    };
    final lastSync = controller.lastSuccessfulSyncAt;

    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      widthFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.medium),
                    ),
                    child: Icon(icon, color: accent),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.syncStatusTitle,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          controller.syncStatusDescription,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('关闭'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (controller.syncPhase == SyncPhase.syncing) ...[
                const SizedBox(height: AppSpacing.md),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: AppSpacing.lg),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    _SyncCheckpoint(
                      icon: Icons.offline_pin_outlined,
                      title: context.tr('本机已保存'),
                      description: controller.pendingOperations == 0
                          ? context.tr('没有待同步的本机更改')
                          : context.tr(
                              '{arg0} 项更改已保存在本机，等待同步',
                              args: {'arg0': controller.pendingOperations},
                            ),
                      state: _CheckpointState.complete,
                    ),
                    const Divider(),
                    _SyncCheckpoint(
                      icon: Icons.cloud_outlined,
                      title: context.tr('云端副本'),
                      description: _cloudDescription(lastSync),
                      state: switch (controller.syncPhase) {
                        SyncPhase.synced => _CheckpointState.complete,
                        SyncPhase.syncing ||
                        SyncPhase.pending => _CheckpointState.inProgress,
                        SyncPhase.attention => _CheckpointState.error,
                        SyncPhase.localOnly ||
                        SyncPhase.offline => _CheckpointState.inactive,
                      },
                    ),
                    const Divider(),
                    _SyncCheckpoint(
                      icon: Icons.devices_outlined,
                      title: context.tr('已登记设备'),
                      description: controller.devices.isEmpty
                          ? context.tr('服务器尚未登记设备')
                          : context.tr(
                              '{arg0} 台设备已登记',
                              args: {'arg0': controller.devices.length},
                            ),
                      state: controller.devices.isEmpty
                          ? _CheckpointState.inactive
                          : _CheckpointState.complete,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.46),
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_moon_outlined,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        context.tr('离线时可编辑任务、调整计划和计时；连接服务器后可继续同步。'),
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: scheme.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (controller.canSync)
                    OutlinedButton.icon(
                      onPressed: controller.syncPhase == SyncPhase.syncing
                          ? null
                          : () => unawaited(controller.syncNow()),
                      icon: const Icon(Icons.sync),
                      label: Text(context.tr('立即同步')),
                    ),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.tr('关闭')),
                  ),
                  if (onOpenSettings != null)
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onOpenSettings!();
                      },
                      icon: const Icon(Icons.tune_rounded),
                      label: Text(context.tr('同步与设备设置')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _cloudDescription(DateTime? lastSync) {
    if (controller.syncPhase == SyncPhase.localOnly) return tr('尚未连接同步账户');
    if (lastSync == null) return tr('尚未完成首次同步');
    return tr(
      '上次同步：{arg0} {arg1}',
      args: {'arg0': formatMonthDay(lastSync), 'arg1': formatClock(lastSync)},
    );
  }
}

enum _CheckpointState { complete, inProgress, inactive, error }

class _SyncCheckpoint extends StatelessWidget {
  const _SyncCheckpoint({
    required this.icon,
    required this.title,
    required this.description,
    required this.state,
  });

  final IconData icon;
  final String title;
  final String description;
  final _CheckpointState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (state) {
      _CheckpointState.complete => scheme.primary,
      _CheckpointState.inProgress => scheme.tertiary,
      _CheckpointState.error => scheme.error,
      _CheckpointState.inactive => scheme.onSurfaceVariant,
    };
    final stateIcon = switch (state) {
      _CheckpointState.complete => Icons.check_circle_rounded,
      _CheckpointState.inProgress => Icons.pending_rounded,
      _CheckpointState.error => Icons.error_rounded,
      _CheckpointState.inactive => Icons.remove_circle_outline_rounded,
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(description),
      trailing: Icon(stateIcon, color: color, size: 20),
    );
  }
}
