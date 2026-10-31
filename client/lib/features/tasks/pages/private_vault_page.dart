import '../../../core/localization/app_localizations.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/domain_models.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/state/app_scope.dart';
import '../../../core/state/private_vault_controller.dart';
import '../../../data/platform/backup_file_gateway.dart';
import '../../focus/widgets/focus_desktop_controls.dart';

const _privacyChannel = MethodChannel('pactick/private_vault');

Future<void> showPrivateVault(
  BuildContext context, {
  String? importTaskId,
}) async {
  final app = AppScope.read(context);
  if (Platform.isAndroid) {
    try {
      await _privacyChannel.invokeMethod<void>('setSecure', {'enabled': true});
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('无法启用私密页面内容保护，请重新启动应用后重试。'))),
        );
      }
      return;
    }
  }
  if (!context.mounted) return;
  try {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PrivateVaultPage(app: app, importTaskId: importTaskId),
      ),
    );
  } finally {
    app.privateVault.lock();
    if (Platform.isAndroid) {
      try {
        await _privacyChannel.invokeMethod<void>('setSecure', {
          'enabled': false,
        });
      } catch (_) {
        /* Keeping FLAG_SECURE enabled is the safer failure mode. */
      }
    }
  }
}

/// Editors remain inside this route so locking can discard every private view.
class PrivateVaultPage extends StatefulWidget {
  const PrivateVaultPage({required this.app, this.importTaskId, super.key});
  final AppController app;
  final String? importTaskId;
  @override
  State<PrivateVaultPage> createState() => _PrivateVaultPageState();
}

enum _PrivateView { tasks, editTask, plan, password, backup, restore, import }

class _PrivateVaultPageState extends State<PrivateVaultPage> {
  PrivateVaultController get vault => widget.app.privateVault;
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _oldPassword = TextEditingController();
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _tags = TextEditingController();
  final _due = TextEditingController();
  final _estimate = TextEditingController();
  final _category = TextEditingController();
  final _planStart = TextEditingController();
  final _planEnd = TextEditingController();
  final _duration = TextEditingController(text: '25');
  _PrivateView _view = _PrivateView.tasks;
  TaskItem? _editingTask;
  PlanBlockItem? _editingPlan;
  String? _selectedProject;
  String? _importTaskId;
  String? _restoreEncoded;
  TaskPriority _priority = TaskPriority.none;
  String? _message;
  bool _failed = false;
  bool _working = false;
  bool _confirmPublicExport = false;
  String? _exportTaskId;
  late int _lockGeneration;
  Timer? _retryTicker;
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  List<TextEditingController> get _fields => [
    _password,
    _confirmation,
    _oldPassword,
    _title,
    _note,
    _tags,
    _due,
    _estimate,
    _category,
    _planStart,
    _planEnd,
    _duration,
  ];

  @override
  void initState() {
    super.initState();
    _lockGeneration = vault.lockGeneration;
    _importTaskId = widget.importTaskId;
    vault.addListener(_vaultChanged);
    _retryTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !vault.isUnlocked && vault.retryAfter != null) {
        setState(() {});
      }
    });
  }

  void _vaultChanged() {
    if (!mounted) return;
    if (_lockGeneration != vault.lockGeneration) {
      _lockGeneration = vault.lockGeneration;
      for (final field in _fields) {
        field.clear();
      }
      _editingTask = null;
      _editingPlan = null;
      _selectedProject = null;
      _exportTaskId = null;
      _confirmPublicExport = false;
      _message = null;
      _view = _PrivateView.tasks;
      FocusManager.instance.primaryFocus?.unfocus();
      // Dropdown menus belong to the navigator; remove any retained labels.
      final route = ModalRoute.of(context);
      if (route != null && route.isActive && !route.isCurrent) {
        Navigator.of(context).popUntil((candidate) => candidate == route);
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    vault.removeListener(_vaultChanged);
    _retryTicker?.cancel();
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool returnToList = true,
  }) async {
    if (_working || vault.isBusy) return;
    setState(() {
      _working = true;
      _message = null;
      _failed = false;
    });
    final generation = vault.lockGeneration;
    try {
      await action();
      if (!mounted || generation != vault.lockGeneration) return;
      setState(() {
        if (returnToList && _view != _PrivateView.restore) {
          _view = _PrivateView.tasks;
        }
        _password.clear();
        _confirmation.clear();
        _oldPassword.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message = switch (error) {
          PrivateVaultException() => error.message,
          FormatException() => context.tr('数据或日期格式无效，原数据未改变。'),
          StateError() => error.message.toString(),
          _ => context.tr('操作未完成，原数据保留。请重试或从密文备份恢复。'),
        };
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool secret = false,
    int lines = 1,
    String? hint,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: controller,
      obscureText: secret,
      maxLines: lines,
      enabled: !_working && !vault.isBusy,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _button(
    String label,
    Future<void> Function() action, {
    bool primary = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: primary
        ? FilledButton(
            onPressed: _working || vault.isBusy ? null : () => _run(action),
            child: Text(label),
          )
        : OutlinedButton(
            onPressed: _working || vault.isBusy ? null : () => _run(action),
            child: Text(label),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final retry = vault.retryAfter?.difference(DateTime.now()).inSeconds ?? 0;
    return PopScope(
      canPop: _view == _PrivateView.tasks,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() {
            _view = _PrivateView.tasks;
            _editingTask = null;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('私密任务箱')),
          actions: [
            if (vault.isUnlocked)
              IconButton(
                tooltip: context.tr('锁定私密任务箱'),
                icon: const Icon(Icons.lock_outline),
                onPressed: vault.lock,
              ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_working || vault.isBusy) const LinearProgressIndicator(),
                if (vault.timerWarning != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(vault.timerWarning!),
                    trailing: TextButton(
                      onPressed: _working
                          ? null
                          : () => _run(
                              vault.retryNativeFocus,
                              returnToList: false,
                            ),
                      child: Text(context.tr('重试通知')),
                    ),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _message!,
                        style: TextStyle(
                          color: _failed
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                    ),
                  ),
                if (!vault.supported)
                  Text(context.tr('当前存储后端不支持私密任务箱。'))
                else if (_view == _PrivateView.restore)
                  ..._restoreView()
                else if (!vault.isUnlocked) ...[
                  Text(
                    vault.configured
                        ? context.tr('输入此工作区的私密任务箱密码。')
                        : context.tr('设置独立密码，至少 8 个字符。密码遗失后无法恢复内容。'),
                  ),
                  const SizedBox(height: 16),
                  _field(context.tr('私密任务箱密码'), _password, secret: true),
                  if (!vault.configured)
                    _field(context.tr('再次输入密码'), _confirmation, secret: true),
                  FilledButton(
                    onPressed: _working || vault.isBusy || retry > 0
                        ? null
                        : () => _run(() async {
                            if (vault.configured) {
                              await vault.unlock(_password.text);
                            } else {
                              await vault.configure(
                                _password.text,
                                _confirmation.text,
                              );
                            }
                            if (_importTaskId != null) {
                              await widget.app.systemCalendar
                                  .protectLocalMutation(
                                    () => vault.importLocalTask(_importTaskId!),
                                  );
                              _importTaskId = null;
                              await widget.app.refreshAfterPrivateTransfer();
                            }
                          }),
                    child: Text(
                      retry > 0
                          ? context.tr('{arg0} 秒后重试', args: {'arg0': retry + 1})
                          : vault.configured
                          ? context.tr('解锁')
                          : context.tr('设置密码'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr(
                      '私密任务、分类、计划和专注记录仅保存在本机密文中，不参与账户同步。应用进入后台、切换工作区或退出私密箱后重新锁定。',
                    ),
                  ),
                  if (widget.importTaskId != null)
                    Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        context.tr(
                          '解锁后转入选定任务及其专属关联记录，仅支持原始本地工作区中从未尝试同步的任务。历史备份可能仍保存转入前的正文。',
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  _button(context.tr('恢复私密密文备份'), _openRestore),
                  if (vault.configured)
                    _button(context.tr('导出私密密文备份'), _saveBackup),
                  if (vault.hasActiveFocus)
                    Text(
                      context.tr(
                        '私密任务专注剩余 {arg0}；解锁后可查看或结束。',
                        args: {'arg0': _remaining()},
                      ),
                    ),
                  if (vault.hasActiveFocus)
                    OpenFocusDesktopButton(controller: widget.app),
                ] else
                  ...switch (_view) {
                    _PrivateView.editTask => _taskEditor(),
                    _PrivateView.plan => _planEditor(),
                    _PrivateView.password => _passwordView(),
                    _PrivateView.backup => _backupView(),
                    _PrivateView.import => _importView(),
                    _ => _tasksView(),
                  },
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _remaining() =>
      '${vault.remainingFocusSeconds ~/ 60}:${(vault.remainingFocusSeconds % 60).toString().padLeft(2, '0')}';

  List<Widget> _tasksView() => [
    Text(context.tr('此处的内容仅在解锁期间显示。普通任务列表、搜索、日历和统计不读取私密数据。')),
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _working ? null : () => _editTask(null),
          icon: const Icon(Icons.add),
          label: Text(context.tr('新建私密任务')),
        ),
        OutlinedButton(
          onPressed: _working
              ? null
              : () => setState(() => _view = _PrivateView.import),
          child: Text(context.tr('转入本地任务')),
        ),
        OutlinedButton(
          onPressed: _working
              ? null
              : () => setState(() => _view = _PrivateView.password),
          child: Text(context.tr('修改密码')),
        ),
        OutlinedButton(
          onPressed: _working
              ? null
              : () => setState(() => _view = _PrivateView.backup),
          child: Text(context.tr('密文备份')),
        ),
      ],
    ),
    if (vault.hasActiveFocus) ...[
      Card(
        child: ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: Text(
            context.tr('私密任务专注 · {arg0}', args: {'arg0': _remaining()}),
          ),
          subtitle: Text(context.tr('锁定后继续计时；系统通知仅显示“私密任务”。')),
          trailing: TextButton(
            onPressed: _working ? null : () => _run(vault.stopFocus),
            child: Text(context.tr('结束')),
          ),
        ),
      ),
      OpenFocusDesktopButton(controller: widget.app),
    ],
    const SizedBox(height: 16),
    if (vault.tasks.isEmpty) Text(context.tr('还没有私密任务。')),
    for (final task in vault.tasks)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(task.title),
                value: task.isCompleted,
                onChanged: _working
                    ? null
                    : (value) => _run(
                        () => vault.saveTask(
                          task.copyWith(
                            status: value!
                                ? TaskStatus.completed
                                : TaskStatus.open,
                            completedAt: value ? DateTime.now() : null,
                            clearCompletedAt: !value,
                          ),
                        ),
                      ),
              ),
              if (task.note?.isNotEmpty == true) Text(task.note!),
              Text(
                context.tr(
                  '优先级：{arg0}{arg1}',
                  args: {
                    'arg0': task.priority.label,
                    'arg1': task.dueAt == null
                        ? ''
                        : tr(
                            ' · 截止：{arg0}',
                            args: {
                              'arg0': _dateFormat.format(task.dueAt!.toLocal()),
                            },
                          ),
                  },
                ),
              ),
              if (task.projectId != null)
                Text(
                  context.tr(
                    '分类：{arg0}',
                    args: {
                      'arg0':
                          vault.projects
                              .where((p) => p.id == task.projectId)
                              .firstOrNull
                              ?.name ??
                          '',
                    },
                  ),
                ),
              if (task.tags.isNotEmpty)
                Text(
                  context.tr('标签：{arg0}', args: {'arg0': task.tags.join('、')}),
                ),
              for (final block in vault.planBlocks.where(
                (p) => p.taskId == task.id,
              ))
                TextButton(
                  onPressed: _working ? null : () => _editPlan(task, block),
                  child: Text(
                    context.tr(
                      '计划 {arg0} — {arg1} · 修改',
                      args: {
                        'arg0': _dateFormat.format(block.startsAt),
                        'arg1': _dateFormat.format(block.endsAt),
                      },
                    ),
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _working ? null : () => _editTask(task),
                    child: Text(context.tr('编辑')),
                  ),
                  TextButton(
                    onPressed: _working ? null : () => _editPlan(task, null),
                    child: Text(context.tr('安排时间')),
                  ),
                  if (task.status == TaskStatus.open)
                    TextButton(
                      onPressed: _working || vault.hasActiveFocus
                          ? null
                          : () => _run(
                              () => vault.startFocus(
                                task.id,
                                int.tryParse(_duration.text) ?? 25,
                              ),
                            ),
                      child: Text(context.tr('开始专注')),
                    ),
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => setState(() {
                            _exportTaskId = task.id;
                            _confirmPublicExport = true;
                          }),
                    child: Text(context.tr('移出私密箱')),
                  ),
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => _run(() => vault.removeTask(task.id)),
                    child: Text(context.tr('删除')),
                  ),
                ],
              ),
              if (_confirmPublicExport && _exportTaskId == task.id) ...[
                Text(
                  context.tr(
                    '移出后，任务及关联记录将作为普通数据显示并进入普通备份；启用账户或系统日历同步时，也会允许上传或写入系统日历。',
                  ),
                ),
                _button(context.tr('确认移出并允许普通存储'), () async {
                  await widget.app.systemCalendar.protectLocalMutation(
                    () => vault.exportTaskToOrdinary(task.id),
                  );
                  await widget.app.refreshAfterPrivateTransfer();
                  _confirmPublicExport = false;
                  _exportTaskId = null;
                }),
              ],
            ],
          ),
        ),
      ),
    const SizedBox(height: 16),
    _field(context.tr('新建私密分类'), _category),
    _button(context.tr('保存私密分类'), () async {
      await vault.saveProject(_category.text);
      _category.clear();
    }),
    _field(context.tr('专注时长（分钟）'), _duration, keyboard: TextInputType.number),
    if (vault.focusSessions.isNotEmpty) ...[
      Text(
        context.tr('私密专注记录'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      for (final session in vault.focusSessions)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            vault.tasks
                    .where((task) => task.id == session.taskId)
                    .firstOrNull
                    ?.title ??
                context.tr('私密任务'),
          ),
          subtitle: Text(
            context.tr(
              '{arg0} · {arg1} 分钟 · {arg2}',
              args: {
                'arg0': _dateFormat.format(session.startedAt),
                'arg1': session.actualDurationSeconds ~/ 60,
                'arg2': switch (session.status) {
                  FocusSessionStatus.running => tr('进行中'),
                  FocusSessionStatus.paused => tr('暂停'),
                  FocusSessionStatus.completed => tr('完成'),
                  FocusSessionStatus.abandoned => tr('提前结束'),
                  FocusSessionStatus.interrupted => tr('中断'),
                },
              },
            ),
          ),
        ),
    ],
  ];

  void _editTask(TaskItem? task) => setState(() {
    _editingTask = task;
    _title.text = task?.title ?? '';
    _note.text = task?.note ?? '';
    _tags.text = task?.tags.join('，') ?? '';
    _priority = task?.priority ?? TaskPriority.none;
    _selectedProject = task?.projectId;
    _due.text = task?.dueAt == null
        ? ''
        : _dateFormat.format(task!.dueAt!.toLocal());
    _estimate.text = task?.estimatedDurationSeconds == null
        ? ''
        : '${task!.estimatedDurationSeconds! ~/ 60}';
    _view = _PrivateView.editTask;
  });

  List<Widget> _taskEditor() => [
    _field(context.tr('任务标题'), _title),
    _field(context.tr('备注'), _note, lines: 4),
    DropdownButtonFormField<String?>(
      initialValue: _selectedProject,
      decoration: InputDecoration(labelText: context.tr('私密分类')),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(context.tr('无分类'))),
        for (final project in vault.projects)
          DropdownMenuItem(value: project.id, child: Text(project.name)),
      ],
      onChanged: _working
          ? null
          : (value) => setState(() => _selectedProject = value),
    ),
    const SizedBox(height: 16),
    DropdownButtonFormField<TaskPriority>(
      initialValue: _priority,
      decoration: InputDecoration(labelText: context.tr('优先级')),
      items: [
        for (final priority in TaskPriority.values)
          DropdownMenuItem(value: priority, child: Text(priority.label)),
      ],
      onChanged: _working
          ? null
          : (value) => setState(() => _priority = value!),
    ),
    const SizedBox(height: 16),
    _field(context.tr('标签'), _tags, hint: context.tr('多个标签使用逗号分隔')),
    _field(context.tr('截止时间（可留空）'), _due, hint: '2026-10-17 20:00'),
    _field(context.tr('预计分钟数（可留空）'), _estimate, keyboard: TextInputType.number),
    _button(context.tr('保存私密任务'), () async {
      final minutes = _estimate.text.trim().isEmpty
          ? null
          : int.tryParse(_estimate.text.trim());
      if (_estimate.text.trim().isNotEmpty &&
          (minutes == null || minutes < 1)) {
        throw PrivateVaultException(context.tr('预计时长须为正整数。'));
      }
      final task = TaskItem(
        id: _editingTask?.id ?? const Uuid().v4(),
        title: _title.text.trim(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        projectId: _selectedProject,
        priority: _priority,
        dueAt: _due.text.trim().isEmpty
            ? null
            : _dateFormat.parseStrict(_due.text.trim()),
        estimatedDurationSeconds: minutes == null ? null : minutes * 60,
        status: _editingTask?.status ?? TaskStatus.open,
        completedAt: _editingTask?.completedAt,
        recurrenceRuleId: _editingTask?.recurrenceRuleId,
        rank: _editingTask?.rank ?? vault.tasks.length.toDouble(),
        tags: _tags.text
            .split(RegExp('[,，]'))
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList(),
      );
      await vault.saveTask(task);
      _title.clear();
      _note.clear();
      _tags.clear();
      _editingTask = null;
    }, primary: true),
  ];

  void _editPlan(TaskItem task, PlanBlockItem? plan) => setState(() {
    _editingTask = task;
    _editingPlan = plan;
    final start =
        plan?.startsAt ?? DateTime.now().add(const Duration(minutes: 5));
    _planStart.text = _dateFormat.format(start);
    _planEnd.text = _dateFormat.format(
      plan?.endsAt ?? start.add(const Duration(minutes: 30)),
    );
    _view = _PrivateView.plan;
  });
  List<Widget> _planEditor() => [
    Text(_editingTask!.title, style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 16),
    _field(context.tr('开始时间'), _planStart, hint: '2026-10-17 20:00'),
    _field(context.tr('结束时间'), _planEnd, hint: '2026-10-17 20:30'),
    Text(context.tr('私密计划保存在密文中，仅在私密箱显示，不生成含任务正文的系统提醒。')),
    _button(
      context.tr('保存私密计划'),
      () => vault.savePlanBlock(
        PlanBlockItem(
          id: _editingPlan?.id ?? const Uuid().v4(),
          taskId: _editingTask!.id,
          startsAt: _dateFormat.parseStrict(_planStart.text.trim()),
          endsAt: _dateFormat.parseStrict(_planEnd.text.trim()),
          timeZone: DateTime.now().timeZoneName,
          status: _editingPlan?.status ?? PlanBlockStatus.scheduled,
        ),
      ),
      primary: true,
    ),
  ];
  List<Widget> _passwordView() => [
    Text(context.tr('修改密码需要验证旧密码，并重新加密当前内容。旧备份仍使用导出时的密码；不提供绕过密码的重置。')),
    const SizedBox(height: 16),
    _field(context.tr('旧密码'), _oldPassword, secret: true),
    _field(context.tr('新密码'), _password, secret: true),
    _field(context.tr('再次输入新密码'), _confirmation, secret: true),
    _button(
      context.tr('修改密码'),
      () => vault.changePassword(
        _oldPassword.text,
        _password.text,
        _confirmation.text,
      ),
      primary: true,
    ),
  ];
  List<Widget> _backupView() => [
    Text(
      context.tr(
        '私密备份包含密文、随机盐和算法参数。新设备使用备份与导出时的原密码即可恢复；恢复创建新的本地工作区并保持锁定。密码遗失后无法恢复。',
      ),
    ),
    const SizedBox(height: 16),
    _button(context.tr('保存私密密文备份文件'), _saveBackup, primary: true),
    _button(context.tr('打开私密密文备份文件'), _openRestore),
    Text(context.tr('完整本地备份 v2 也包含私密箱密文。普通正文与私密密文使用不同存储；导出不会把私密内容解密为 JSON。')),
  ];
  Future<void> _saveBackup() async {
    final encoded = await vault.exportEncryptedBackup();
    if (await const BackupFileGateway().saveJson(
      encoded,
      suggestedName: 'pactick-private-vault.json',
    )) {
      if (mounted) {
        setState(() {
          _message = context.tr('私密密文备份已保存。');
          _failed = false;
        });
      }
    }
  }

  Future<void> _openRestore() async {
    final encoded = await const BackupFileGateway().openJson();
    if (encoded != null && mounted) {
      setState(() {
        _restoreEncoded = encoded;
        _password.clear();
        _view = _PrivateView.restore;
      });
    }
  }

  List<Widget> _restoreView() => [
    Text(
      context.tr(
        '输入此备份导出时使用的密码。通过认证后新建本地工作区；当前工作区保留，恢复后请在“设置 → 数据备份与工作区”中打开恢复的工作区。',
      ),
    ),
    const SizedBox(height: 16),
    _field(context.tr('备份密码'), _password, secret: true),
    _button(context.tr('验证并恢复到新的本地工作区'), () async {
      if (_restoreEncoded == null) {
        throw PrivateVaultException(context.tr('请先选择备份文件。'));
      }
      await vault.restoreEncryptedBackup(_restoreEncoded!, _password.text);
      _restoreEncoded = null;
      vault.lock();
      if (mounted) {
        setState(
          () => _message = context.tr('已创建恢复工作区，原工作区保留。请从设置打开恢复工作区后解锁。'),
        );
      }
    }, primary: true),
  ];
  List<Widget> _importView() => [
    Text(
      context.tr(
        '仅原始本地工作区中从未尝试同步的任务可以转入。任务及专属计划、专注和待发送修改在同一事务中迁移；关联其他任务或正在专注时拒绝操作。历史备份和系统快照可能仍保留原正文。',
      ),
    ),
    const SizedBox(height: 16),
    for (final task in widget.app.tasks)
      ListTile(
        title: Text(task.title),
        trailing: const Icon(Icons.lock_outline),
        onTap: _working
            ? null
            : () => _run(() async {
                await widget.app.systemCalendar.protectLocalMutation(
                  () => vault.importLocalTask(task.id),
                );
                await widget.app.refreshAfterPrivateTransfer();
              }),
      ),
    if (widget.app.tasks.isEmpty) Text(context.tr('普通工作区中没有可选择的任务。')),
  ];
}
