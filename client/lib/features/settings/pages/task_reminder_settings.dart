import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/utilities/persistence_errors.dart';

class TaskReminderSettingsCard extends StatefulWidget {
  const TaskReminderSettingsCard({required this.controller, super.key});

  final AppController controller;

  @override
  State<TaskReminderSettingsCard> createState() =>
      _TaskReminderSettingsCardState();
}

class _TaskReminderSettingsCardState extends State<TaskReminderSettingsCard> {
  bool _busy = false;
  String? _error;
  Future<void> Function()? _retry;

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _retry = operation;
    });
    try {
      await operation();
      if (mounted) setState(() => _retry = null);
    } catch (error) {
      if (mounted) setState(() => _error = persistenceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final supported = controller.taskReminderPlatform.isSupported;
    final error = _error ?? controller.taskReminderErrorMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          key: const ValueKey('task-reminders-toggle'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('任务温馨提醒'),
          subtitle: const Text('默认开启。有未完成任务时，在通知栏显示一条静默提醒，完成后自动移除。'),
          value: controller.taskRemindersEnabled,
          onChanged: !supported || _busy
              ? null
              : (value) =>
                    _run(() => controller.setTaskRemindersEnabled(value)),
        ),
        if (!supported)
          const Text('任务提醒仅在安卓客户端展示。')
        else ...[
          if (controller.taskRemindersEnabled)
            Text(
              controller.taskReminderNotificationsAllowed
                  ? '系统允许任务提醒；通知只显示待办数量，不显示任务标题。'
                  : '提醒已开启，但系统尚未允许展示。请申请通知权限或检查系统提醒设置。',
            ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => controller.refreshTaskReminders(
                          requestPermission: true,
                          automatic: false,
                        ),
                      ),
                child: const Text('检查 / 申请通知权限'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        controller
                            .taskReminderPlatform
                            .openNotificationSettings,
                      ),
                child: const Text('系统提醒设置'),
              ),
            ],
          ),
        ],
        if (_busy) const LinearProgressIndicator(semanticsLabel: '正在保存任务提醒设置'),
        if (error != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(_retry ?? controller.refreshTaskReminders),
            child: const Text('重试'),
          ),
        ],
      ],
    );
  }
}
