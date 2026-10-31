import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/calendar/system_calendar_models.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/state/system_calendar_controller.dart';
import '../../../core/utilities/formatters.dart';

Future<void> showSystemCalendarSettings(
  BuildContext context,
  AppController app,
) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(builder: (_) => SystemCalendarSettingsPage(app: app)),
);

class SystemCalendarSettingsTile extends StatelessWidget {
  const SystemCalendarSettingsTile({required this.app, super.key});
  final AppController app;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app.systemCalendar,
    builder: (context, _) {
      final calendar = app.systemCalendar;
      return ListTile(
        leading: const Icon(Icons.calendar_month_outlined),
        title: Text(context.tr('系统日历')),
        subtitle: Text(
          calendar.enabled
              ? calendar.configuration.calendar?.displayName ??
                    context.tr('已启用系统日历同步')
              : context.tr('默认关闭；连接 Android 日历，双向更新普通计划。'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showSystemCalendarSettings(context, app),
      );
    },
  );
}

class SystemCalendarSettingsPage extends StatefulWidget {
  const SystemCalendarSettingsPage({required this.app, super.key});
  final AppController app;

  @override
  State<SystemCalendarSettingsPage> createState() =>
      _SystemCalendarSettingsPageState();
}

class _SystemCalendarSettingsPageState
    extends State<SystemCalendarSettingsPage> {
  SystemCalendarController get calendar => widget.app.systemCalendar;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(calendar.refreshAccess());
  }

  Future<void> _chooseCalendar() async {
    final accountId = widget.app.repository.selectedAccountId;
    await calendar.requestAccess();
    if (!mounted || !calendar.permissions.canRead) return;
    if (accountId != widget.app.repository.selectedAccountId) {
      setState(() => _message = tr('工作区已切换，请重新选择系统日历。'));
      return;
    }
    if (calendar.calendars.isEmpty) {
      setState(() => _message = tr('没有可读取的日历，请先在系统日历中添加或启用日历。'));
      return;
    }
    final selected = await showDialog<SystemCalendarInfo>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.tr('选择系统日历')),
        children: [
          for (final info in calendar.calendars)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, info),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (info.accountLabel.isNotEmpty) Text(info.accountLabel),
                  Text(
                    info.writable ? context.tr('可读取和写入') : context.tr('只读日历'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    if (accountId != widget.app.repository.selectedAccountId) {
      setState(() => _message = tr('工作区已切换，请重新选择系统日历。'));
      return;
    }
    await _enable(selected, accountId: accountId);
  }

  Future<void> _enable(SystemCalendarInfo selected, {String? accountId}) async {
    final expectedAccount =
        accountId ?? widget.app.repository.selectedAccountId;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('启用系统日历同步？')),
        content: SingleChildScrollView(
          child: Text(
            context.tr(
              '系统日程将成为当前工作区的普通计划；已有普通计划也会写入所选可写日历。启用账户同步时，导入内容可能上传到当前服务器；系统日历也可能由其账户服务商同步。私密任务箱不参与。两侧同时修改或任一侧删除时，需要手动选择保留的版本。',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('启用同步')),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    if (expectedAccount != widget.app.repository.selectedAccountId) {
      setState(() => _message = tr('工作区已切换，请重新选择系统日历。'));
      return;
    }
    if (!calendar.permissions.canRead ||
        (selected.writable && !calendar.permissions.canWrite)) {
      await calendar.requestAccess(write: selected.writable);
      if (!mounted || !calendar.permissions.canRead) return;
    }
    if (expectedAccount != widget.app.repository.selectedAccountId) return;
    await calendar.configure(enabled: true, calendar: selected);
    if (mounted) await calendar.syncNow();
  }

  Future<void> _resolve(
    SystemCalendarConflict conflict,
    SystemCalendarConflictChoice choice,
  ) async {
    final accountId = widget.app.repository.selectedAccountId;
    final deletesSystem =
        choice == SystemCalendarConflictChoice.local && conflict.local == null;
    final deletesClient =
        choice == SystemCalendarConflictChoice.system &&
        conflict.remote == null;
    if (deletesSystem || deletesClient) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('确认同步删除？')),
          content: Text(
            deletesSystem
                ? context.tr('这将删除系统日历中的这一次日程，不会删除整个重复系列。')
                : context.tr('这将删除客户端中的这个计划时段，任务与专注记录保留。'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('确认删除')),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    if (accountId != widget.app.repository.selectedAccountId) {
      if (mounted) setState(() => _message = tr('工作区已切换，请重新选择系统日历。'));
      return;
    }
    await calendar.syncNow(resolutions: {conflict.id: choice});
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: calendar,
    builder: (context, _) {
      final config = calendar.configuration;
      final info = config.calendar;
      final result = calendar.lastResult;
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('系统日历'))),
        body: Align(
          alignment: AlignmentDirectional.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.readingContentMax,
            ),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(context.tr('将系统日程导入普通计划，也可将客户端计划写入所选日历。')),
                const SizedBox(height: AppSpacing.md),
                if (!calendar.supported)
                  Text(context.tr('仅 Android 客户端支持系统日历。'))
                else ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('系统日历同步')),
                    subtitle: Text(info?.displayName ?? context.tr('尚未选择日历')),
                    value: config.enabled,
                    onChanged: calendar.busy || info == null
                        ? null
                        : (value) {
                            if (value) {
                              unawaited(_enable(info));
                            } else {
                              unawaited(calendar.configure(enabled: false));
                            }
                          },
                  ),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month_outlined),
                        onPressed: calendar.busy ? null : _chooseCalendar,
                        label: Text(context.tr('选择系统日历')),
                      ),
                      if (info?.writable == true &&
                          !calendar.permissions.canWrite)
                        OutlinedButton(
                          onPressed: calendar.busy
                              ? null
                              : () => calendar.requestAccess(write: true),
                          child: Text(context.tr('允许写入日历')),
                        ),
                      if (info != null)
                        FilledButton.icon(
                          icon: const Icon(Icons.sync),
                          onPressed: calendar.busy || !calendar.enabled
                              ? null
                              : () => calendar.syncNow(),
                          label: Text(context.tr('立即同步日历')),
                        ),
                    ],
                  ),
                  if (info != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    if (info.accountLabel.isNotEmpty) Text(info.accountLabel),
                    Text(
                      info.writable && calendar.permissions.canWrite
                          ? context.tr('双向同步标题、起止时间和全天日期。')
                          : context.tr('当前仅导入系统日程；日历只读或未获得写入权限。'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      context.tr('同步范围'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      context.tr(
                        '读取过去 30 天及所选未来范围内的日程。已关联且移出范围的日程会单独核对，不按消失处理。',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final days in [30, 90, 180, 365])
                          ChoiceChip(
                            label: Text(
                              context.tr('未来 {arg0} 天', args: {'arg0': days}),
                            ),
                            selected: config.futureDays == days,
                            onSelected: calendar.busy
                                ? null
                                : (_) => calendar.configure(
                                    enabled: config.enabled,
                                    futureDays: days,
                                  ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Text(context.tr('仅在应用前台、返回应用或手动操作时同步；关闭此连接不会删除任何一侧的数据。')),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    context.tr('导入的普通计划可随当前账户同步上传；所选系统日历也可能同步到其账户服务商。私密箱不参与。'),
                  ),
                  if (calendar.busy) ...[
                    const SizedBox(height: AppSpacing.md),
                    LinearProgressIndicator(
                      semanticsLabel: context.tr('正在同步系统日历'),
                    ),
                  ],
                  if (calendar.errorMessage case final message?) ...[
                    const SizedBox(height: AppSpacing.md),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: calendar.busy
                          ? null
                          : () async {
                              await calendar.refreshAccess();
                              await calendar.syncNow();
                            },
                      child: Text(context.tr('重试')),
                    ),
                  ],
                  if (result != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      context.tr(
                        '本次导入 {arg0} 项，导出 {arg1} 项，更新 {arg2} 项。',
                        args: {
                          'arg0': result.imported,
                          'arg1': result.exported,
                          'arg2': result.updated,
                        },
                      ),
                    ),
                    if (result.skipped > 0)
                      Text(
                        context.tr(
                          '跳过 {arg0} 项无法表示或属于其他工作区的日程。',
                          args: {'arg0': result.skipped},
                        ),
                      ),
                    if (result.lastSyncedAt case final date?)
                      Text(
                        context.tr(
                          '最近同步：{arg0}',
                          args: {
                            'arg0':
                                '${formatMonthDay(date.toLocal())} ${formatClock(date.toLocal())}',
                          },
                        ),
                      ),
                    for (final conflict in result.conflicts)
                      _conflict(context, conflict),
                  ],
                ],
                if (_message case final message?) ...[
                  const SizedBox(height: AppSpacing.md),
                  Semantics(liveRegion: true, child: Text(message)),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _conflict(
    BuildContext context,
    SystemCalendarConflict conflict,
  ) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Text(switch (conflict.kind) {
          SystemCalendarConflictKind.bothChanged => context.tr('两侧均有更改'),
          SystemCalendarConflictKind.localDeleted => context.tr('客户端计划已删除'),
          SystemCalendarConflictKind.remoteDeleted => context.tr('系统日程已删除'),
          SystemCalendarConflictKind.readOnly => context.tr('系统日程不可写入'),
          SystemCalendarConflictKind.unsupported => context.tr('日程格式暂不支持写入'),
        }, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        _version(context, context.tr('客户端版本'), conflict.local),
        _version(context, context.tr('系统版本'), conflict.remote),
        if (!conflict.canKeepClient && !conflict.canKeepSystem)
          Text(context.tr('请先在系统日历中调整日程格式或写入权限，再重新同步。')),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton(
              onPressed: calendar.busy || !conflict.canKeepClient
                  ? null
                  : () =>
                        _resolve(conflict, SystemCalendarConflictChoice.local),
              child: Text(context.tr('保留客户端版本')),
            ),
            OutlinedButton(
              onPressed: calendar.busy || !conflict.canKeepSystem
                  ? null
                  : () =>
                        _resolve(conflict, SystemCalendarConflictChoice.system),
              child: Text(context.tr('保留系统版本')),
            ),
          ],
        ),
        Text(context.tr('未选择时保留两侧内容。选择后若日程又变化，将重新检查冲突。')),
      ],
    ),
  );

  Widget _version(
    BuildContext context,
    String label,
    SystemCalendarEventData? value,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        if (value == null)
          Text(context.tr('已删除'))
        else ...[
          Text(value.title.isEmpty ? '—' : value.title),
          Text(
            '${formatFullDate(value.startsAt)} ${formatClock(value.startsAt)} – '
            '${formatFullDate(value.endsAt)} ${formatClock(value.endsAt)}',
          ),
          Text(value.allDay ? context.tr('全天日程') : value.timeZone),
        ],
      ],
    ),
  );
}
