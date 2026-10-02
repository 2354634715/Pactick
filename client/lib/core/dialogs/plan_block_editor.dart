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
  DateTime? suggestedStart,
}) {
  return showGuardedEditor<PlanBlockItem>(
    context,
    builder: (dismissal) => PlanBlockEditor(
      controller: controller,
      initialTask: task,
      suggestedStart: suggestedStart,
      dismissal: dismissal,
    ),
  );
}

class PlanBlockEditor extends StatefulWidget {
  const PlanBlockEditor({
    required this.controller,
    this.initialTask,
    this.suggestedStart,
    this.dismissal,
    super.key,
  });

  final AppController controller;
  final EditorDismissalController? dismissal;
  final TaskItem? initialTask;
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
  String? _taskId;
  late DateTime _date;
  late TimeOfDay _time;
  double _durationMinutes = 45;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final start = widget.suggestedStart ?? DateTime.now();
    _taskId = widget.initialTask?.id;
    _date = DateTime(start.year, start.month, start.day);
    _time = TimeOfDay.fromDateTime(start);
    _durationMinutes =
        ((widget.initialTask?.estimatedDurationSeconds ?? 45 * 60) / 60).clamp(
          15,
          240,
        );
    _initialDraft = _draft;
    _titleController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  String get _draft => jsonEncode([
    _titleController.text,
    _taskId,
    _date.toIso8601String(),
    _time.hour,
    _time.minute,
    _durationMinutes,
  ]);

  @override
  void dispose() {
    _titleFocus.dispose();
    _titleController.dispose();
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
                      '添加日程',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
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
                        decoration: const InputDecoration(
                          labelText: '关联任务',
                          prefixIcon: Icon(Icons.task_alt_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              '不关联任务',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          for (final task in widget.controller.tasks.where(
                            (task) => !task.isCompleted,
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
                          decoration: const InputDecoration(
                            labelText: '日程标题',
                            prefixIcon: Icon(Icons.title),
                          ),
                          validator: (value) =>
                              _taskId == null && (value?.trim().isEmpty ?? true)
                              ? '请输入日程标题'
                              : null,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      _PickerField(
                        icon: Icons.calendar_today_outlined,
                        label: '日期',
                        value: formatMonthDay(_date),
                        onTap: _saving ? null : _pickDate,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _PickerField(
                        icon: Icons.schedule,
                        label: '开始时间',
                        value: _time.format(context),
                        onTap: _saving ? null : _pickTime,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Card(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '计划时长 · ${formatDuration((_durationMinutes * 60).round(), compact: true)}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Slider(
                                value: _durationMinutes,
                                min: 15,
                                max: 240,
                                divisions: 15,
                                label: '${_durationMinutes.round()} 分钟',
                                onChanged: _saving
                                    ? null
                                    : (value) {
                                        setState(
                                          () => _durationMinutes = value,
                                        );
                                      },
                              ),
                            ],
                          ),
                        ),
                      ),
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
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => _guardKey.currentState?.requestClose(),
                  child: const Text('取消'),
                ),

                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('加入日历'),
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
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (value != null && mounted) setState(() => _date = value);
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null && mounted) setState(() => _time = value);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      _titleFocus.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final startsAt = DateTime(
        _date.year,
        _date.month,
        _date.day,
        _time.hour,
        _time.minute,
      );
      final block = await widget.controller.scheduleTask(
        taskId: _taskId,
        title: _titleController.text.trim(),
        startsAt: startsAt,
        duration: Duration(minutes: _durationMinutes.round()),
      );
      if (!mounted) return;
      Navigator.pop(context, block);
    } catch (error) {
      if (mounted) setState(() => _saveError = persistenceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
