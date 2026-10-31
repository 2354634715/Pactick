import '../../core/localization/app_localizations.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../models/domain_models.dart';
import '../state/app_controller.dart';
import '../utilities/formatters.dart';
import '../utilities/persistence_errors.dart';
import 'editor_frame.dart';

Future<PlanBlockItem?> showPlanBlockEditor(
  BuildContext context, {
  required AppController controller,
  TaskItem? task,
  PlanBlockItem? block,
  DateTime? suggestedStart,
}) {
  return showGuardedEditor<PlanBlockItem>(
    context,
    builder: (dismissal) => PlanBlockEditor(
      controller: controller,
      initialTask: task,
      block: block,
      suggestedStart: suggestedStart,
      dismissal: dismissal,
    ),
  );
}

class PlanBlockEditor extends StatefulWidget {
  const PlanBlockEditor({
    required this.controller,
    this.initialTask,
    this.block,
    this.suggestedStart,
    this.dismissal,
    super.key,
  });

  final AppController controller;
  final EditorDismissalController? dismissal;
  final TaskItem? initialTask;
  final PlanBlockItem? block;
  final DateTime? suggestedStart;

  @override
  State<PlanBlockEditor> createState() => _PlanBlockEditorState();
}

class _PlanBlockEditorState extends State<PlanBlockEditor> {
  final _formKey = GlobalKey<FormState>();
  final _titleFocus = FocusNode();
  final _guardKey = GlobalKey<EditorDraftGuardState>();
  late final String _initialDraft;
  final _titleController = TextEditingController();
  final _durationController = TextEditingController();
  late final String _accountId;
  String? _taskId;
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final block = widget.block;
    _accountId = widget.controller.repository.selectedAccountId;
    final start = block?.startsAt ?? widget.suggestedStart ?? DateTime.now();
    _taskId =
        block?.taskId ??
        (widget.initialTask?.status == TaskStatus.open
            ? widget.initialTask?.id
            : null);
    _titleController.text =
        block?.title ??
        widget.controller.taskById(block?.taskId)?.title ??
        widget.initialTask?.title ??
        '';
    _date = DateTime(start.year, start.month, start.day);
    _time = TimeOfDay.fromDateTime(start);
    final seconds =
        block?.durationSeconds ??
        widget.initialTask?.estimatedDurationSeconds ??
        45 * 60;
    _durationController.text = seconds % 60 == 0
        ? '${seconds ~/ 60}'
        : '${seconds / 60}';
    _initialDraft = _draft;
    _titleController.addListener(() {
      if (mounted) setState(() {});
    });
    _durationController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  String get _draft => jsonEncode([
    _titleController.text,
    _taskId,
    _date.toIso8601String(),
    _time.hour,
    _time.minute,
    _durationController.text,
  ]);

  @override
  void dispose() {
    _titleFocus.dispose();
    _titleController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: EditorDraftGuard(
        key: _guardKey,
        dismissal: widget.dismissal,
        dirty: _draft != _initialDraft,
        hasChanges: () => _draft != _initialDraft,
        savingNow: () => _saving,
        saving: _saving,
        child: EditorPanel(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.block == null
                          ? context.tr('添加日程')
                          : context.tr('编辑计划时段'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('关闭'),
                    onPressed: _saving
                        ? null
                        : () => _guardKey.currentState?.requestClose(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String?>(
                        isExpanded: true,
                        initialValue: _taskId,
                        decoration: InputDecoration(
                          labelText: context.tr('关联任务'),
                          prefixIcon: Icon(Icons.task_alt_outlined),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              context.tr('不关联任务'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_taskId != null &&
                              widget.controller.taskById(_taskId) == null)
                            DropdownMenuItem<String?>(
                              value: _taskId,
                              child: Text(context.tr('原关联任务已不存在，请重新选择')),
                            ),
                          for (final task in widget.controller.tasks.where(
                            (task) =>
                                task.status == TaskStatus.open ||
                                (widget.block != null &&
                                    task.id == widget.block!.taskId),
                          ))
                            DropdownMenuItem<String?>(
                              value: task.id,
                              child: Text(
                                task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        validator: (value) =>
                            value != null &&
                                widget.controller.taskById(value) == null
                            ? context.tr('请更换关联任务，或取消关联并填写标题')
                            : null,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _taskId = value),
                      ),
                      if (_taskId == null) ...[
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          enabled: !_saving,
                          controller: _titleController,
                          focusNode: _titleFocus,
                          decoration: InputDecoration(
                            labelText: context.tr('日程标题'),
                            prefixIcon: Icon(Icons.title),
                          ),
                          validator: (value) =>
                              _taskId == null && (value?.trim().isEmpty ?? true)
                              ? context.tr('请输入日程标题')
                              : null,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      _PickerField(
                        icon: Icons.calendar_today_outlined,
                        label: context.tr('日期'),
                        value: formatMonthDay(_date),
                        onTap: _saving ? null : _pickDate,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _PickerField(
                        icon: Icons.schedule,
                        label: context.tr('开始时间'),
                        value: _time.format(context),
                        onTap: _saving ? null : _pickTime,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        key: const ValueKey('plan-duration-minutes'),
                        controller: _durationController,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: context.tr('计划时长（分钟）'),
                          prefixIcon: Icon(Icons.timelapse),
                        ),
                        validator: (value) {
                          final minutes = double.tryParse(value ?? '');
                          return minutes == null ||
                                  !minutes.isFinite ||
                                  minutes <= 0 ||
                                  (minutes * 60).round() < 1
                              ? context.tr('请输入大于零的时长（至少 1 秒）')
                              : null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(context.tr('修改计划不会改变已记录的实际专注时长。')),
                    ],
                  ),
                ),
              ),
            ),
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _saveError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            EditorActions(
              children: [
                if (widget.block != null)
                  TextButton.icon(
                    key: const ValueKey('delete-plan-block'),
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(context.tr('删除时段')),
                  ),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => _guardKey.currentState?.requestClose(),
                  child: Text(context.tr('取消')),
                ),

                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(
                    widget.block == null
                        ? context.tr('加入日历')
                        : context.tr('保存修改'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(
        _date.year < DateTime.now().year - 1
            ? _date.year
            : DateTime.now().year - 1,
      ),
      lastDate: DateTime(
        _date.year > DateTime.now().year + 10
            ? _date.year + 1
            : DateTime.now().year + 10,
      ),
    );
    if (value != null && mounted) setState(() => _date = value);
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null && mounted) setState(() => _time = value);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_checkWorkspace()) return;
    if (!_formKey.currentState!.validate()) {
      _titleFocus.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final original = widget.block?.startsAt;
      final startsAt =
          original != null &&
              original.year == _date.year &&
              original.month == _date.month &&
              original.day == _date.day &&
              original.hour == _time.hour &&
              original.minute == _time.minute
          ? original
          : DateTime(
              _date.year,
              _date.month,
              _date.day,
              _time.hour,
              _time.minute,
            );
      final duration = Duration(
        seconds: (double.parse(_durationController.text) * 60).round(),
      );
      final block = widget.block == null
          ? await widget.controller.scheduleTask(
              taskId: _taskId,
              title: _titleController.text.trim(),
              startsAt: startsAt,
              duration: duration,
            )
          : await widget.controller.updatePlanBlock(
              block: widget.block!,
              taskId: _taskId,
              title: _titleController.text.trim(),
              startsAt: startsAt,
              duration: duration,
            );
      if (!mounted) return;
      Navigator.pop(context, block);
    } catch (error) {
      if (mounted) setState(() => _saveError = persistenceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (!_checkWorkspace()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('删除计划时段？')),
        content: Text(context.tr('仅删除这个计划时段，关联任务和已记录的实际专注保留。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('删除')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _saving) return;
    if (!_checkWorkspace()) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.controller.deletePlanBlock(widget.block!);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _saveError = persistenceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _checkWorkspace() {
    if (widget.controller.repository.selectedAccountId != _accountId) {
      setState(() => _saveError = context.tr('工作区已切换，请关闭编辑器后重新打开。'));
      return false;
    }
    final block = widget.block;
    if (block != null &&
        !widget.controller.planBlocks.any(
          (current) => current.id == block.id,
        )) {
      setState(() => _saveError = context.tr('这个计划时段已删除，请关闭编辑器查看当前日历。'));
      return false;
    }
    return true;
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.medium),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        child: Row(
          children: [
            Expanded(child: Text(value)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
