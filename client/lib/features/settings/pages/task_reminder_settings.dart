import '../../../core/localization/app_localizations.dart';

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
          title: Text(context.tr('任务温馨提醒')),
          subtitle: Text(context.tr('默认开启。有未完成任务时，在通知栏显示一条静默提醒，完成后自动移除。')),
          value: controller.taskRemindersEnabled,
          onChanged: !supported || _busy
              ? null
              : (value) =>
                    _run(() => controller.setTaskRemindersEnabled(value)),
        ),
        SwitchListTile.adaptive(
          key: const ValueKey('scheduled-task-reminders-toggle'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.alarm_outlined),
          title: Text(context.tr('截止与计划开始提醒')),
          subtitle: Text(
            context.tr('默认开启。任务到期或计划开始时显示通用通知，不显示任务正文。系统节电或后台限制可能延迟提醒。'),
          ),
          value: controller.scheduledTaskRemindersEnabled,
          onChanged: !supported || _busy
              ? null
              : (value) => _run(
                  () => controller.setScheduledTaskRemindersEnabled(value),
                ),
        ),
        if (!supported)
          Text(context.tr('任务提醒仅在安卓客户端展示。'))
        else ...[
          if (controller.taskRemindersEnabled)
            Text(
              controller.taskReminderNotificationsAllowed
                  ? context.tr('系统允许任务提醒；通知只显示待办数量，不显示任务标题。')
                  : context.tr('提醒已开启，但系统尚未允许展示。请申请通知权限或检查系统提醒设置。'),
            ),
          if (controller.scheduledTaskRemindersEnabled)
            Text(
              controller.scheduledTaskReminderNotificationsAllowed
                  ? context.tr('系统允许定时提醒。仅依据本机已保存的数据安排通知；强行停止后需重新打开应用。')
                  : context.tr('定时提醒已开启，但系统未允许通知或已关闭“截止与计划提醒”分类。'),
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
                child: Text(context.tr('检查 / 申请通知权限')),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        controller
                            .taskReminderPlatform
                            .openNotificationSettings,
                      ),
                child: Text(context.tr('系统提醒设置')),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        controller
                            .taskReminderPlatform
                            .openScheduledNotificationSettings,
                      ),
                child: Text(context.tr('定时提醒分类设置')),
              ),
            ],
          ),
        ],
        if (_busy)
          LinearProgressIndicator(semanticsLabel: context.tr('正在保存任务提醒设置')),
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
            child: Text(context.tr('重试')),
          ),
        ],
      ],
    );
  }
}
