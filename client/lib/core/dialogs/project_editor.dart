import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../models/domain_models.dart';
import '../state/app_controller.dart';
import '../utilities/persistence_errors.dart';
import 'editor_frame.dart';

Future<ProjectItem?> showProjectEditor(
  BuildContext context, {
  required AppController controller,
  ProjectItem? project,
}) {
  return showGuardedEditor<ProjectItem>(
    context,
    builder: (dismissal) => ProjectEditor(
      controller: controller,
      project: project,
      dismissal: dismissal,
    ),
  );
}

class ProjectEditor extends StatefulWidget {
  const ProjectEditor({
    required this.controller,
    this.project,
    this.dismissal,
    super.key,
  });

  final AppController controller;
  final EditorDismissalController? dismissal;
  final ProjectItem? project;

  @override
  State<ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends State<ProjectEditor> {
  static const _colors = [
    '#5B67D8',
    '#8B5FC7',
    '#D15D83',
    '#D46A45',
    '#C28A2C',
    '#3C9475',
    '#367FA1',
    '#697386',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameFocus = FocusNode();
  final _guardKey = GlobalKey<EditorDraftGuardState>();
  late final String _initialDraft;
  late final TextEditingController _nameController;
  late String _color;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.project?.name);
    _color = widget.project?.color ?? _colors.first;
    _initialDraft = _draft;
    _nameController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  String get _draft => jsonEncode([_nameController.text, _color]);

  @override
  void dispose() {
    _nameFocus.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedColor = _parseColor(_color);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: EditorDraftGuard(
        key: _guardKey,
        dismissal: widget.dismissal,
        dirty: _draft != _initialDraft,
        hasChanges: () => _draft != _initialDraft,
        savingNow: () => _saving,
        saving: _saving,
        child: Form(
          key: _formKey,
          child: EditorPanel(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: selectedColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppRadii.medium),
                      ),
                      child: Icon(Icons.folder_rounded, color: selectedColor),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.project == null ? '新建项目' : '编辑项目',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text(
                            '将相关任务归入同一项目',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
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
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        enabled: !_saving,
                        controller: _nameController,
                        focusNode: _nameFocus,
                        autofocus: widget.project == null,
                        maxLength: 120,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _save(),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: '项目名称',
                          hintText: '例如：产品发布',
                          prefixIcon: Icon(Icons.drive_file_rename_outline),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入项目名称'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '项目颜色',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final color in _colors)
                            Semantics(
                              button: true,
                              selected: _color == color,
                              label: '项目颜色 ${_colorName(color)}',
                              enabled: !_saving,
                              excludeSemantics: true,
                              onTap: _saving
                                  ? null
                                  : () => setState(() => _color = color),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _saving
                                    ? null
                                    : () => setState(() => _color = color),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.xs),
                                  child: AnimatedContainer(
                                    duration: AppDurations.resolve(
                                      context,
                                      AppDurations.feedback,
                                    ),
                                    width: AppSpacing.xl,
                                    height: AppSpacing.xl,
                                    decoration: BoxDecoration(
                                      color: _parseColor(color),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _color == color
                                            ? scheme.onSurface
                                            : Colors.transparent,
                                        width: 3,
                                      ),
                                    ),
                                    child: _color == color
                                        ? const Icon(
                                            Icons.check,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: selectedColor.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(AppRadii.card),
                          border: Border.all(
                            color: selectedColor.withValues(alpha: 0.24),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.folder_rounded, color: selectedColor),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                _nameController.text.trim().isEmpty
                                    ? '项目预览'
                                    : _nameController.text.trim(),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              '${widget.controller.tasks.where((task) => widget.project != null && task.projectId == widget.project!.id).length} 项任务',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
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
                        : const Icon(Icons.check),
                    label: Text(widget.project == null ? '创建项目' : '保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      _nameFocus.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final ProjectItem saved;
      if (widget.project case final project?) {
        saved = project.copyWith(
          name: _nameController.text.trim(),
          color: _color,
        );
        await widget.controller.updateProject(saved);
      } else {
        saved = await widget.controller.createProject(
          name: _nameController.text,
          color: _color,
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

Color _parseColor(String value) {
  final normalized = value.replaceFirst('#', '');
  final parsed = int.tryParse(normalized, radix: 16) ?? 0x5B67D8;
  if (normalized.length != 8) return Color(0xFF000000 | parsed);
  final rgb = parsed >> 8;
  final alpha = parsed & 0xFF;
  return Color((alpha << 24) | rgb);
}

String _colorName(String value) =>
    const {
      '#5B67D8': '靛蓝',
      '#8B5FC7': '紫色',
      '#D15D83': '玫红',
      '#D46A45': '橙红',
      '#C28A2C': '赭黄',
      '#3C9475': '绿色',
      '#367FA1': '蓝色',
      '#697386': '灰色',
    }[value] ??
    value;
