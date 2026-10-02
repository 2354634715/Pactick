import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/components/feature_page_scaffold.dart';
import '../../../core/components/section_header.dart';
import '../../../core/models/domain_models.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/state/app_scope.dart';
import '../../../core/state/session_controller.dart';
import '../../../core/state/session_scope.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/persistence_errors.dart';
import '../../../data/update/client_update_service.dart';
import 'local_data_settings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.onClose,
    this.clientUpdateService,
    super.key,
  });
  final VoidCallback onClose;
  final ClientUpdateService? clientUpdateService;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watchData(context);
    final session = SessionScope.of(context);
    return FeaturePageScaffold(
      title: '设置',
      subtitle: '外观、专注权限、可选同步与本机数据',
      leading: BackButton(onPressed: onClose),
      body: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSizes.readingContentMax,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: '外观'),
              _AppearanceCard(controller: controller),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: '专注与权限'),
              _FocusPermissionCard(controller: controller),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: Text('暂不可用'),
                subtitle: Text('任务与计划提醒、专注震动反馈、严格模式尚未实现。普通专注无需守护权限。'),
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: '同步与设备'),
              if (session.user case final user?)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text(user.initials)),
                  title: Text(user.displayName),
                  subtitle: Text(user.email),
                )
              else
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.offline_bolt_outlined),
                  title: Text('本地工作区'),
                  subtitle: Text('无需账户，数据保存在本机；登录只用于可选同步'),
                ),
              const SyncSettingsCard(),
              _DevicesCard(controller: controller, sessionController: session),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: '数据备份与工作区'),
              const LocalDataCard(),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: '关于'),
              ReleasesAboutCard(service: clientUpdateService),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppearanceCard extends StatefulWidget {
  const _AppearanceCard({required this.controller});
  final AppController controller;
  @override
  State<_AppearanceCard> createState() => _AppearanceCardState();
}

class _AppearanceCardState extends State<_AppearanceCard> {
  bool _saving = false;
  String? _error;
  Future<void> Function()? _retry;

  Future<void> _save(Future<void> Function() operation) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _retry = operation;
    });
    try {
      await operation();
      if (mounted) setState(() => _retry = null);
    } catch (error) {
      if (mounted) setState(() => _error = persistenceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final labels = {
      ThemePreference.system: '跟随系统',
      ThemePreference.light: '浅色',
      ThemePreference.dark: '深色',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('主题模式', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final option in labels.entries)
              ChoiceChip(
                label: Text(option.value),
                selected: controller.themePreference == option.key,
                onSelected: _saving
                    ? null
                    : (_) => _save(
                        () => controller.setThemePreference(option.key),
                      ),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('使用系统动态色'),
          subtitle: const Text('默认使用红、近黑与米白配色。开启后使用系统动态色；不支持时仍使用默认配色。'),
          value: controller.useDynamicColor,
          onChanged: _saving
              ? null
              : (value) => _save(() => controller.setDynamicColor(value)),
        ),
        if (_saving) const LinearProgressIndicator(semanticsLabel: '正在保存外观设置'),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: _saving || _retry == null
                      ? null
                      : () => _save(_retry!),
                  child: const Text('重试保存'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FocusPermissionCard extends StatefulWidget {
  const _FocusPermissionCard({required this.controller});
  final AppController controller;
  @override
  State<_FocusPermissionCard> createState() => _FocusPermissionCardState();
}

class _FocusPermissionCardState extends State<_FocusPermissionCard> {
  bool _busy = false;
  String? _message;
  bool _failed = false;
  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = '权限操作未完成：$error。普通模式仍可使用。';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _permission({
    required IconData icon,
    required String title,
    required String description,
    required Future<void> Function() action,
    String label = '检查 / 申请',
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icon)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: _busy ? null : () => _run(action),
            child: Text(label),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _permission(
          icon: Icons.verified_user_outlined,
          title: '使用情况访问',
          description: controller.usageAccessGranted
              ? '已授权 · 守护模式用它识别前台应用'
              : '未授权 · 守护模式需要此权限，普通模式仍可使用',
          action: controller.openUsageAccessSettings,
          label: controller.usageAccessGranted ? '检查系统设置' : '打开授权设置',
        ),
        const Divider(),
        _permission(
          icon: Icons.layers_outlined,
          title: '显示在其他应用上层',
          description: controller.overlayPermissionGranted
              ? '已授权 · 守护模式用它显示离开应用提醒'
              : '未授权 · 无法开始守护模式，普通模式仍可使用',
          action: controller.openOverlayPermissionSettings,
          label: controller.overlayPermissionGranted ? '检查系统设置' : '打开授权设置',
        ),
        const Divider(),
        _permission(
          icon: Icons.notifications_outlined,
          title: '前台计时通知',
          description: '用于专注期间的系统通知展示。本接口未提供持续查询状态；拒绝后系统展示受限，本地计时操作仍可使用。',
          action: () async {
            final granted = await controller.focusPlatform
                .requestNotificationPermission();
            if (mounted) {
              setState(() {
                _failed = !granted;
                _message = granted
                    ? '本次权限检查返回允许通知展示。'
                    : '本次未获通知权限；系统通知展示受限，本地计时仍可使用。';
              });
            }
          },
        ),
        if (_busy) const LinearProgressIndicator(semanticsLabel: '正在执行权限操作'),
        if (_message != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _message!,
              style: TextStyle(
                color: _failed
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _DevicesCard extends StatefulWidget {
  const _DevicesCard({
    required this.controller,
    required this.sessionController,
  });

  final AppController controller;
  final SessionController sessionController;
  @override
  State<_DevicesCard> createState() => _DevicesCardState();
}

class _DevicesCardState extends State<_DevicesCard> {
  final Set<String> _revoking = {};
  AppController get controller => widget.controller;
  SessionController get sessionController => widget.sessionController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusIcon = switch (controller.syncPhase) {
      SyncPhase.localOnly => Icons.cloud_off_outlined,
      SyncPhase.synced => Icons.cloud_done_outlined,
      SyncPhase.pending => Icons.cloud_upload_outlined,
      SyncPhase.syncing => Icons.sync,
      SyncPhase.offline => Icons.cloud_off_outlined,
      SyncPhase.attention => Icons.sync_problem_outlined,
    };
    final statusColor = switch (controller.syncPhase) {
      SyncPhase.synced || SyncPhase.syncing => scheme.primary,
      SyncPhase.pending => scheme.tertiary,
      SyncPhase.attention => scheme.error,
      SyncPhase.localOnly || SyncPhase.offline => scheme.onSurfaceVariant,
    };
    final lastSync = controller.lastSuccessfulSyncAt;
    final statusDescription =
        controller.syncPhase == SyncPhase.synced && lastSync != null
        ? '上次成功同步：${formatMonthDay(lastSync)} ${formatClock(lastSync)}'
        : controller.syncStatusDescription;
    return Column(
      children: [
        ListTile(
          leading: Icon(statusIcon, color: statusColor),
          title: Text(controller.syncStatusTitle),
          subtitle: Text(statusDescription),
          trailing: switch (controller.syncPhase) {
            SyncPhase.localOnly when !controller.canSync => const Chip(
              label: Text('仅本地'),
            ),
            SyncPhase.syncing => const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            _ => IconButton(
              key: const ValueKey('sync-now'),
              tooltip: '立即同步',
              onPressed: controller.canSync
                  ? () => unawaited(controller.syncNow())
                  : null,
              icon: const Icon(Icons.sync),
            ),
          },
        ),
        const Divider(),
        if (controller.devices.isEmpty)
          ListTile(
            leading: Icon(Icons.phone_android),
            title: Text(sessionController.device?.name ?? '此 Android 设备'),
            subtitle: Text(
              controller.syncPhase == SyncPhase.offline
                  ? '当前设备 · 离线'
                  : sessionController.isAuthenticated
                  ? '当前设备 · 等待同步'
                  : '当前设备 · 仅本地使用',
            ),
            trailing: const Chip(label: Text('当前')),
          )
        else
          for (final device in controller.devices) ...[
            ListTile(
              leading: Icon(
                device.platform == 'android'
                    ? Icons.phone_android
                    : Icons.computer,
              ),
              title: Text(device.name),
              subtitle: Text(
                device.isCurrent
                    ? '当前设备'
                    : '上次使用：${formatMonthDay(device.lastSeenAt)} ${formatClock(device.lastSeenAt)}',
              ),
              trailing: device.isCurrent
                  ? const Chip(label: Text('当前'))
                  : IconButton(
                      tooltip: '撤销设备登录',
                      onPressed: _revoking.contains(device.id)
                          ? null
                          : () => _confirmRevoke(context, device),
                      icon: _revoking.contains(device.id)
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                semanticsLabel: '正在撤销设备登录',
                              ),
                            )
                          : const Icon(Icons.logout),
                    ),
            ),
            if (device != controller.devices.last) const Divider(),
          ],
      ],
    );
  }

  Future<void> _confirmRevoke(BuildContext context, DeviceItem device) async {
    if (_revoking.contains(device.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.devices_other_outlined),
        title: Text('撤销“${device.name}”的登录'),
        content: const Text('该设备的登录将失效。本机数据不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销登录'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      setState(() => _revoking.add(device.id));
      try {
        final revoked = await controller.revokeDevice(device.id);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(revoked ? '已撤销“${device.name}”的登录' : '撤销失败，请检查网络后重试'),
          ),
        );
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('撤销未完成：$error')));
        }
      } finally {
        if (mounted) setState(() => _revoking.remove(device.id));
      }
    }
  }
}
