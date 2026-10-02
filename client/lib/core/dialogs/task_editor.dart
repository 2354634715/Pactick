import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../models/domain_models.dart';
import '../state/app_controller.dart';
import '../utilities/formatters.dart';
import '../utilities/persistence_errors.dart';
import 'editor_frame.dart';
import 'project_editor.dart';

Future<TaskItem?> showTaskEditor(
  BuildContext context, {
  required AppController controller,
  TaskItem? task,
  DateTime? suggestedDueAt,
}) {
  return showGuardedEditor<TaskItem>(
    context,
    builder: (dismissal) => TaskEditor(
      controller: controller,
      task: task,
      suggestedDueAt: suggestedDueAt,
      dismissal: dismissal,
    ),
  );
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({
    required this.controller,
    this.task,
    this.suggestedDueAt,
    this.dismissal,
    super.key,
  });

  final AppController controller;
  final EditorDismissalController? dismissal;
  final TaskItem? task;
  final DateTime? suggestedDueAt;

  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final _formKey = GlobalKey<FormState>();
  final _titleFocus = FocusNode();
  final _guardKey = GlobalKey<EditorDraftGuardState>();
  late final String _initialDraft;
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late final TextEditingController _tagsController;
  String? _projectId;
  late TaskPriority _priority;
  DateTime? _dueAt;
  late bool _hasEstimate;
  late double _estimateMinutes;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title);
    _noteController = TextEditingController(text: task?.note);
    _tagsController = TextEditingController(text: task?.tags.join('、'));
    _projectId = task?.projectId;
    _priority = task?.priority ?? TaskPriority.none;
    _dueAt = task?.dueAt ?? widget.suggestedDueAt;
    _hasEstimate = task?.estimatedDurationSeconds != null;
    _estimateMinutes = ((task?.estimatedDurationSeconds ?? 45 * 60) / 60.0)
        .clamp(15, 240);
    _initialDraft = _draft;
    for (final field in [_titleController, _noteController, _tagsController]) {
      field.addListener(_draftChanged);
    }
  }

  String get _draft => jsonEncode([
    _titleController.text,
    _noteController.text,
    _tagsController.text,
    _projectId,
    _priority.name,
    _dueAt?.toIso8601String(),
    _hasEstimate,
    _estimateMinutes,
  ]);
  void _draftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    _titleController.dispose();
    _noteController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: EditorDraftGuard(
        key: _guardKey,
        dismissal: widget.dismissal,
        dirty: _draft != _initialDraft,
        hasChanges: () => _draft != _initialDraft,
        savingNow: () => _saving,
        saving: _saving,
        child: EditorPanel(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      widget.task == null ? '新建任务' : '编辑任务',
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        enabled: !_saving,
                        controller: _titleController,
                        focusNode: _titleFocus,
                        autofocus: widget.task == null,
                        textInputAction: TextInputAction.next,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: '任务标题',
                          prefixIcon: Icon(Icons.check_circle_outline),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入任务标题'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        enabled: !_saving,
                        controller: _noteController,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 50000,
                        decoration: const InputDecoration(
                          labelText: '备注',
                          alignLabelWithHint: true,
                          prefixIcon: Icon(Icons.notes_outlined),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String?>(
                        key: ValueKey(_projectId),
                        isExpanded: true,
                        initialValue: _projectId,
                        decoration: const InputDecoration(
                          labelText: '项目或清单',
                          prefixIcon: Icon(Icons.folder_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              '收集箱',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          for (final project in widget.controller.projects)
                            DropdownMenuItem<String?>(
                              value: project.id,
                              child: Text(
                                project.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _projectId = value),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _saving
                              ? null
                              : () async {
                                  final project = await showProjectEditor(
                                    context,
                                    controller: widget.controller,
                                  );
                                  if (project != null && mounted) {
                                    setState(() => _projectId = project.id);
                                  }
                                },
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('新建项目'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      DropdownButtonFormField<TaskPriority>(
                        isExpanded: true,
                        initialValue: _priority,
                        decoration: const InputDecoration(
                          labelText: '优先级',
                          prefixIcon: Icon(Icons.flag_outlined),
                        ),
                        items: [
                          for (final priority in TaskPriority.values)
                            DropdownMenuItem(
                              value: priority,
                              child: Text('${priority.label}优先级'),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _priority = value);
                                }
                              },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _DateField(
                        value: _dueAt,
                        onChanged: (value) => setState(() => _dueAt = value),
                        enabled: !_saving,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Card(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _hasEstimate,
                                onChanged: _saving
                                    ? null
                                    : (value) {
                                        setState(() => _hasEstimate = value);
                                      },
                                title: const Text('设置预计用时'),
                                subtitle: _hasEstimate
                                    ? Text(
                                        formatDuration(
                                          (_estimateMinutes * 60).round(),
                                          compact: true,
                                        ),
                                      )
                                    : const Text('未设置预计用时；开始专注时可选择目标时长'),
                              ),
                              if (_hasEstimate)
                                Slider(
                                  value: _estimateMinutes,
                                  min: 15,
                                  max: 240,
                                  divisions: 15,
                                  label: '${_estimateMinutes.round()} 分钟',
                                  onChanged: _saving
                                      ? null
                                      : (value) {
                                          setState(
                                            () => _estimateMinutes = value,
                                          );
                                        },
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        enabled: !_saving,
                        controller: _tagsController,
                        decoration: const InputDecoration(
                          labelText: '标签',
                          hintText: '用逗号或顿号分隔',
                          prefixIcon: Icon(Icons.label_outline),
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
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存任务'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
      final tags = _tagsController.text
          .split(RegExp('[,，、]'))
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList(growable: false);
      final estimate = _hasEstimate ? (_estimateMinutes * 60).round() : null;
      TaskItem saved;
      if (widget.task case final task?) {
        saved = task.copyWith(
          title: _titleController.text.trim(),
          note: _noteController.text.trim(),
          clearNote: _noteController.text.trim().isEmpty,
          projectId: _projectId,
          clearProject: _projectId == null,
          priority: _priority,
          dueAt: _dueAt,
          clearDueAt: _dueAt == null,
          estimatedDurationSeconds: estimate,
          clearEstimatedDuration: estimate == null,
          tags: tags,
        );
        await widget.controller.updateTask(saved);
      } else {
        saved = await widget.controller.createTask(
          title: _titleController.text,
          note: _noteController.text,
          projectId: _projectId,
          priority: _priority,
          dueAt: _dueAt,
          estimatedDurationSeconds: estimate,
          tags: tags,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saveError = persistenceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final DateTime? value;
  final bool enabled;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: '截止日期',
        prefixIcon: Icon(Icons.event_outlined),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            value == null
                ? '不设置截止日期'
                : '${formatMonthDay(value!)} ${formatClock(value!)}',
          ),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              if (value != null)
                IconButton(
                  tooltip: '清除截止日期',
                  onPressed: enabled ? () => onChanged(null) : null,
                  icon: const Icon(Icons.clear),
                ),
              IconButton(
                tooltip: '选择截止日期',
                onPressed: !enabled
                    ? null
                    : () async {
                        final now = DateTime.now();
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: value ?? now,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 10),
                        );
                        if (selected != null) {
                          onChanged(
                            DateTime(
                              selected.year,
                              selected.month,
                              selected.day,
                              value?.hour ?? 0,
                              value?.minute ?? 0,
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.calendar_today_outlined),
              ),
              if (value != null)
                IconButton(
                  tooltip: '选择截止时间',
                  onPressed: !enabled
                      ? null
                      : () async {
                          final selected = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(value!),
                          );
                          if (selected != null) {
                            onChanged(
                              DateTime(
                                value!.year,
                                value!.month,
                                value!.day,
                                selected.hour,
                                selected.minute,
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.schedule),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
