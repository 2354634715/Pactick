import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../core/dialogs/editor_frame.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/utilities/persistence_errors.dart';
import '../../../core/state_views/state_pane.dart';
import '../../../data/platform/focus_platform_gateway.dart';

Future<void> showAppWhitelistEditor(
  BuildContext context, {
  required AppController controller,
  required String? projectId,
}) async {
  await showGuardedEditor<void>(
    context,
    builder: (dismissal) => _AppWhitelistEditor(
      controller: controller,
      projectId: projectId,
      dismissal: dismissal,
    ),
  );
}

class _AppWhitelistEditor extends StatefulWidget {
  const _AppWhitelistEditor({
    required this.controller,
    required this.projectId,
    required this.dismissal,
  });

  final AppController controller;
  final String? projectId;
  final EditorDismissalController dismissal;

  @override
  State<_AppWhitelistEditor> createState() => _AppWhitelistEditorState();
}

class _AppWhitelistEditorState extends State<_AppWhitelistEditor> {
  late final TextEditingController _searchController;
  late final Set<String> _selectedPackages;
  final _guardKey = GlobalKey<EditorDraftGuardState>();
  late final Set<String> _initialPackages;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selectedPackages = widget.controller
        .appWhitelistForProject(widget.projectId)
        .toSet();
    _initialPackages = {..._selectedPackages};
    _loadApplications();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApplications({bool force = false}) async {
    await widget.controller.loadInstalledApplications(force: force);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final scheme = Theme.of(context).colorScheme;
    final applications = _filteredApplications(
      controller.installedApplications,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: EditorDraftGuard(
        key: _guardKey,
        dismissal: widget.dismissal,
        dirty: !setEquals(_initialPackages, _selectedPackages),
        hasChanges: () => !setEquals(_initialPackages, _selectedPackages),
        savingNow: () => _saving,
        saving: _saving,
        child: Material(
          color: scheme.surfaceContainerLow,
          child: EditorPanel(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                      child: const Icon(Icons.shield_outlined),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${controller.whitelistName(widget.projectId)}白名单',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            '仅用于本机守护；不发送到同步服务器。主动导出备份会携带包名与项目白名单。',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭白名单编辑',
                      onPressed: _saving
                          ? null
                          : () => _guardKey.currentState?.requestClose(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _saveError!,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SearchBar(
                  controller: _searchController,
                  enabled: !_saving,
                  hintText: '搜索应用名称或包名',
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        tooltip: '清除搜索',
                        onPressed: _saving
                            ? null
                            : () {
                                _searchController.clear();
                                setState(() {});
                              },
                        icon: const Icon(Icons.clear),
                      ),
                  ],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(
                  '已选择 ${_selectedPackages.length} 个应用',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppDurations.resolve(context, AppDurations.overlay),
                  child: _applicationList(controller, applications),
                ),
              ),
              const Divider(height: 1),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => _guardKey.currentState?.requestClose(),
                        child: const Text('取消'),
                      ),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('保存白名单'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _applicationList(
    AppController controller,
    List<InstalledApplication> applications,
  ) {
    if (controller.installedApplicationsLoading) {
      return const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (controller.installedApplicationsError != null) {
      return SingleChildScrollView(
        child: StatePane.error(
          title: '无法读取应用列表',
          message: '可重新读取应用列表，当前选择保持不变。',
          actionLabel: '重试',
          onAction: () => _loadApplications(force: true),
        ),
      );
    }
    if (controller.installedApplications.isEmpty) {
      return SingleChildScrollView(
        child: StatePane.empty(
          title: '没有可选应用',
          message: '白名单仅支持选择 Android 设备上可启动的应用。',
          actionLabel: '重新读取',
          onAction: () => _loadApplications(force: true),
        ),
      );
    }
    if (applications.isEmpty) {
      return SingleChildScrollView(
        child: StatePane.empty(title: '未找到匹配应用', message: '更换应用名称或包名后重试。'),
      );
    }
    return ListView.separated(
      key: const ValueKey('applications'),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      itemCount: applications.length,
      separatorBuilder: (context, index) => const Divider(indent: 72),
      itemBuilder: (context, index) {
        final application = applications[index];
        final selected = _selectedPackages.contains(application.packageName);
        return CheckboxListTile(
          value: selected,
          onChanged: _saving
              ? null
              : (value) {
                  setState(() {
                    if (value ?? false) {
                      _selectedPackages.add(application.packageName);
                    } else {
                      _selectedPackages.remove(application.packageName);
                    }
                  });
                },
          secondary: CircleAvatar(
            child: Text(
              application.label.isEmpty
                  ? '?'
                  : application.label.characters.first,
            ),
          ),
          title: Text(
            application.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            application.packageName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  List<InstalledApplication> _filteredApplications(
    List<InstalledApplication> applications,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return applications;
    return applications
        .where(
          (application) =>
              application.label.toLowerCase().contains(query) ||
              application.packageName.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.controller.setAppWhitelist(
        widget.projectId,
        _selectedPackages,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _saveError = persistenceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
