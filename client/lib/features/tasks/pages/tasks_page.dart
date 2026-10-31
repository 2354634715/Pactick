import '../../../core/localization/app_localizations.dart';

import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/components/feature_page_scaffold.dart';
import '../../../core/components/sync_status_button.dart';
import '../../../core/components/task_card.dart';
import '../../../core/components/task_details_panel.dart';
import '../../../core/dialogs/project_editor.dart';
import '../../../core/dialogs/task_editor.dart';
import '../../../core/models/domain_models.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/state/app_scope.dart';
import '../../../core/state_views/state_pane.dart';
import '../../../core/utilities/persistence_errors.dart';
import 'private_vault_page.dart';

enum _TaskSection { inbox, projects, tags, completed }

enum _TaskAction { edit, focus, makePrivate }

class TasksPage extends StatefulWidget {
  const TasksPage({
    required this.onOpenSettings,
    required this.onOpenFocus,
    super.key,
  });
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenFocus;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _searchController = TextEditingController();
  final _listController = ScrollController();
  final _detailsController = ScrollController();
  final _busyTasks = <String>{};
  _TaskSection _section = _TaskSection.inbox;
  String? _selectedProjectId;
  String? _selectedTag;
  String? _selectedTaskId;

  @override
  void dispose() {
    _searchController.dispose();
    _listController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watchData(context);
    final tasks = _filterTasks(controller);
    final selectedTask = controller.taskById(_selectedTaskId);
    return FeaturePageScaffold(
      title: context.tr('任务'),
      subtitle: _subtitle(controller, tasks.length),
      scrollable: false,
      actions: [
        IconButton(
          tooltip: context.tr('私密任务箱'),
          onPressed: () => showPrivateVault(context),
          icon: const Icon(Icons.lock_outline),
        ),
        SyncStatusButton(
          phase: controller.syncPhase,
          pendingCount: controller.pendingOperations,
          onPressed: () => showSyncStatusPanel(
            context,
            controller: controller,
            onOpenSettings: widget.onOpenSettings,
          ),
        ),
        IconButton(
          tooltip: context.tr('设置'),
          onPressed: widget.onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'tasks-create-task',
        onPressed: () => showTaskEditor(context, controller: controller),
        icon: const Icon(Icons.add_task),
        label: Text(context.tr('新建任务')),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final twoPane =
              constraints.maxWidth >= AppSizes.twoPaneMinWidth &&
              constraints.maxHeight >= AppSizes.lowHeight;
          final list = CustomScrollView(
            key: const PageStorageKey('tasks-list'),
            controller: _listController,
            slivers: [
              SliverToBoxAdapter(
                child: _header(controller, selectedTask, twoPane),
              ),
              if (tasks.isEmpty)
                SliverToBoxAdapter(child: _empty(controller))
              else
                SliverList.builder(
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    final busy = _busyTasks.contains(task.id);
                    return Column(
                      key: ValueKey(task.id),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TaskCard(
                          task: task,
                          project: controller.projectById(task.projectId),
                          actualSeconds: controller.actualSecondsForTask(
                            task.id,
                          ),
                          enabled: !busy,
                          selected: _selectedTaskId == task.id,
                          onToggle: (_) => _toggleTask(controller, task.id),
                          onTap: () {
                            if (_selectedTaskId != task.id &&
                                _detailsController.hasClients) {
                              _detailsController.jumpTo(0);
                            }
                            setState(() => _selectedTaskId = task.id);
                            if (!twoPane) {
                              showTaskDetailsPanel(
                                context,
                                controller: controller,
                                task: task,
                              );
                            }
                          },
                          trailing: busy
                              ? Padding(
                                  padding: EdgeInsets.all(AppSpacing.md),
                                  child: SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      semanticsLabel: context.tr('正在保存任务'),
                                    ),
                                  ),
                                )
                              : _taskMenu(controller, task),
                        ),
                      ],
                    );
                  },
                ),
              const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.xxl + AppSpacing.lg),
              ),
            ],
          );
          if (!twoPane) return list;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: list),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(
                width: AppSizes.detailPanelWidth,
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  child: SingleChildScrollView(
                    key: const PageStorageKey('task-details'),
                    controller: _detailsController,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: selectedTask == null
                        ? StatePane.empty(
                            title: context.tr('选择一项任务'),
                            message: context.tr('查看完整标题、备注、标签和已记录专注时间。'),
                          )
                        : TaskDetailsPanel(
                            task: selectedTask,
                            controller: controller,
                            onEdit: _busyTasks.contains(selectedTask.id)
                                ? null
                                : () => showTaskEditor(
                                    context,
                                    controller: controller,
                                    task: selectedTask,
                                  ),
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(
    AppController controller,
    TaskItem? selectedTask,
    bool twoPane,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchBar(
          controller: _searchController,
          hintText: context.tr('搜索标题、备注或标签'),
          leading: const Icon(Icons.search),
          trailing: [
            if (_searchController.text.isNotEmpty)
              IconButton(
                tooltip: context.tr('清除搜索'),
                onPressed: () => setState(_searchController.clear),
                icon: const Icon(Icons.clear),
              ),
          ],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final section in _TaskSection.values)
              ChoiceChip(
                selected: _section == section,
                avatar: Icon(_sectionIcon(section), size: 20),
                label: Text(_sectionLabel(section)),
                onSelected: (_) => setState(() {
                  _section = section;
                  _selectedTaskId = null;
                }),
              ),
          ],
        ),
        if (_section == _TaskSection.projects) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_outlined),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSizes.sidePanel,
                  ),
                  child: Text(
                    controller.projectById(_selectedProjectId)?.name ??
                        context.tr('所有项目'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onPressed: () => _chooseProject(controller),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(context.tr('新建项目')),
                onPressed: () => _createProject(controller),
              ),
              if (controller.projectById(_selectedProjectId)
                  case final project?)
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(context.tr('编辑项目')),
                  onPressed: () => showProjectEditor(
                    context,
                    controller: controller,
                    project: project,
                  ),
                ),
            ],
          ),
        ],
        if (_section == _TaskSection.tags) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.sell_outlined),
              label: Text(
                _selectedTag ?? context.tr('所有标签'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => _chooseTag(controller),
            ),
          ),
        ],
        if (!twoPane && selectedTask != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => showTaskDetailsPanel(
                context,
                controller: controller,
                task: selectedTask,
              ),
              icon: const Icon(Icons.description_outlined),
              label: Text(context.tr('查看选中任务详情')),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  Widget _empty(AppController controller) {
    final hasFilter =
        _searchController.text.trim().isNotEmpty ||
        _selectedProjectId != null ||
        _selectedTag != null;
    if (controller.tasks.isEmpty) {
      return StatePane.empty(
        title: context.tr('尚无任务'),
        message: context.tr('使用“新建任务”记录任务；本地使用无需账号。'),
      );
    }
    return StatePane.empty(
      title: _section == _TaskSection.completed && !hasFilter
          ? context.tr('还没有已完成任务')
          : context.tr('当前条件下没有任务'),
      message: _section == _TaskSection.inbox && !hasFilter
          ? context.tr('收集箱中没有待办任务，可查看项目或新建任务。')
          : context.tr('调整搜索或分类；已有任务和本机数据保持不变。'),
      actionLabel: hasFilter ? context.tr('清除搜索与筛选') : null,
      onAction: hasFilter
          ? () => setState(() {
              _searchController.clear();
              _selectedProjectId = null;
              _selectedTag = null;
            })
          : null,
    );
  }

  Widget _taskMenu(AppController controller, TaskItem task) {
    final active = controller.activeFocusSession != null;
    return PopupMenuButton<_TaskAction>(
      key: ValueKey('task-more-${task.id}'),
      tooltip: context.tr('{arg0}的更多操作', args: {'arg0': task.title}),
      icon: const Icon(Icons.more_horiz),
      onSelected: (action) {
        switch (action) {
          case _TaskAction.edit:
            final current = controller.taskById(task.id);
            if (current != null) {
              showTaskEditor(context, controller: controller, task: current);
            }
          case _TaskAction.focus:
            _startFocus(controller, task.id);
          case _TaskAction.makePrivate:
            showPrivateVault(context, importTaskId: task.id);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: _TaskAction.edit, child: Text(context.tr('编辑任务'))),
        PopupMenuItem(
          value: _TaskAction.makePrivate,
          child: Text(context.tr('转入私密任务箱')),
        ),
        if (!task.isCompleted)
          PopupMenuItem(
            value: _TaskAction.focus,
            child: Text(active ? context.tr('返回当前专注') : context.tr('开始专注')),
          ),
      ],
    );
  }

  List<TaskItem> _filterTasks(AppController controller) {
    final query = _searchController.text.trim().toLowerCase();
    return controller.tasks
        .where((task) {
          final matches = switch (_section) {
            _TaskSection.inbox => task.projectId == null && !task.isCompleted,
            _TaskSection.projects =>
              !task.isCompleted &&
                  task.projectId != null &&
                  (_selectedProjectId == null ||
                      task.projectId == _selectedProjectId),
            _TaskSection.tags =>
              !task.isCompleted &&
                  (_selectedTag == null || task.tags.contains(_selectedTag)),
            _TaskSection.completed => task.isCompleted,
          };
          if (!matches) return false;
          return query.isEmpty ||
              task.title.toLowerCase().contains(query) ||
              (task.note?.toLowerCase().contains(query) ?? false) ||
              task.tags.any((tag) => tag.toLowerCase().contains(query));
        })
        .toList(growable: false);
  }

  String _subtitle(AppController controller, int count) => switch (_section) {
    _TaskSection.inbox => context.tr('收集箱 · {arg0} 项待办', args: {'arg0': count}),
    _TaskSection.projects => context.tr('项目 · {arg0} 项', args: {'arg0': count}),
    _TaskSection.tags => context.tr('标签 · {arg0} 项', args: {'arg0': count}),
    _TaskSection.completed => context.tr(
      '已完成 · {arg0} 项',
      args: {'arg0': count},
    ),
  };

  Future<void> _chooseProject(AppController controller) async {
    final selected = await _choose(
      title: context.tr('选择项目'),
      allLabel: context.tr('所有项目'),
      values: {
        for (final project in controller.projects) project.id: project.name,
      },
      selected: _selectedProjectId,
      emptyMessage: context.tr('尚无项目；可以返回后新建项目。'),
      icon: Icons.folder_outlined,
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedProjectId = selected.isEmpty ? null : selected;
        _selectedTaskId = null;
      });
    }
  }

  Future<void> _chooseTag(AppController controller) async {
    final tags = controller.tasks.expand((task) => task.tags).toSet().toList()
      ..sort();
    final selected = await _choose(
      title: context.tr('选择标签'),
      allLabel: context.tr('所有标签'),
      values: {for (final tag in tags) tag: tag},
      selected: _selectedTag,
      emptyMessage: context.tr('还没有标签；可在任务编辑器中输入标签。'),
      icon: Icons.label_outline,
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedTag = selected.isEmpty ? null : selected;
        _selectedTaskId = null;
      });
    }
  }

  Future<String?> _choose({
    required String title,
    required String allLabel,
    required Map<String, String> values,
    required String? selected,
    required String emptyMessage,
    required IconData icon,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.7,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              title: Text(allLabel),
              selected: selected == null,
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final entry in values.entries)
              ListTile(
                leading: Icon(icon),
                title: Text(entry.value),
                selected: selected == entry.key,
                onTap: () => Navigator.pop(context, entry.key),
              ),
            if (values.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(emptyMessage),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createProject(AppController controller) async {
    final project = await showProjectEditor(context, controller: controller);
    if (project != null && mounted) {
      setState(() {
        _section = _TaskSection.projects;
        _selectedProjectId = project.id;
        _selectedTaskId = null;
      });
    }
  }

  Future<void> _toggleTask(AppController controller, String id) async {
    if (!mounted || _busyTasks.contains(id)) return;
    final previous = controller.taskById(id);
    if (previous == null) return;
    final accountId = controller.repository.selectedAccountId;
    setState(() => _busyTasks.add(id));
    try {
      await controller.toggleTask(previous);
      final applied = controller.taskById(id);
      if (!mounted ||
          applied == null ||
          controller.repository.selectedAccountId != accountId) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            applied.isCompleted ? context.tr('任务已完成') : context.tr('任务已恢复待办'),
          ),
          action: SnackBarAction(
            label: context.tr('撤销'),
            onPressed: () =>
                _undoTask(controller, previous, applied, accountId),
          ),
        ),
      );
    } catch (error) {
      _error(
        error,
        retry: () {
          if (controller.repository.selectedAccountId == accountId) {
            _toggleTask(controller, id);
          } else {
            _message(context.tr('工作区已变化，请在当前工作区重新操作。'));
          }
        },
      );
    } finally {
      if (mounted) setState(() => _busyTasks.remove(id));
    }
  }

  Future<void> _undoTask(
    AppController controller,
    TaskItem previous,
    TaskItem applied,
    String accountId,
  ) async {
    if (!mounted) return;
    final current = controller.taskById(previous.id);
    if (controller.repository.selectedAccountId != accountId ||
        current == null ||
        current.status != applied.status ||
        current.completedAt != applied.completedAt) {
      _message(context.tr('任务状态或工作区已变化，无法撤销这次操作。'));
      return;
    }
    if (_busyTasks.contains(current.id)) return;
    setState(() => _busyTasks.add(current.id));
    try {
      await controller.updateTask(
        current.copyWith(
          status: previous.status,
          completedAt: previous.completedAt,
          clearCompletedAt: previous.completedAt == null,
        ),
      );
      if (controller.repository.selectedAccountId == accountId) {
        _message(tr('已撤销任务状态更改'));
      }
    } catch (error) {
      _error(
        error,
        retry: () => _undoTask(controller, previous, applied, accountId),
      );
    } finally {
      if (mounted) setState(() => _busyTasks.remove(current.id));
    }
  }

  Future<void> _startFocus(AppController controller, String id) async {
    if (!mounted || _busyTasks.contains(id)) return;
    if (controller.activeFocusSession != null || !controller.canStartFocus) {
      widget.onOpenFocus();
      return;
    }
    final task = controller.taskById(id);
    final policy = controller.focusPolicies.firstOrNull;
    if (task == null || task.isCompleted || policy == null) return;
    final accountId = controller.repository.selectedAccountId;
    setState(() => _busyTasks.add(id));
    try {
      await controller.startFocus(
        task: task,
        durationSeconds: task.estimatedDurationSeconds ?? 25 * 60,
        policy: policy,
      );
      if (mounted && controller.repository.selectedAccountId == accountId) {
        widget.onOpenFocus();
      }
    } catch (error) {
      _error(
        error,
        retry: () {
          if (controller.repository.selectedAccountId == accountId) {
            _startFocus(controller, id);
          } else {
            _message(context.tr('工作区已变化，请在当前工作区重新操作。'));
          }
        },
      );
    } finally {
      if (mounted) setState(() => _busyTasks.remove(id));
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _error(Object error, {required VoidCallback retry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(persistenceErrorMessage(error)),
        action: SnackBarAction(label: context.tr('重试'), onPressed: retry),
      ),
    );
  }
}

IconData _sectionIcon(_TaskSection section) => switch (section) {
  _TaskSection.inbox => Icons.inbox_outlined,
  _TaskSection.projects => Icons.folder_outlined,
  _TaskSection.tags => Icons.sell_outlined,
  _TaskSection.completed => Icons.task_alt,
};

String _sectionLabel(_TaskSection section) => switch (section) {
  _TaskSection.inbox => tr('收集箱'),
  _TaskSection.projects => tr('项目'),
  _TaskSection.tags => tr('标签'),
  _TaskSection.completed => tr('已完成'),
};
