import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/dialogs/editor_frame.dart';
import '../../../core/state/session_controller.dart';
import '../../../core/state/app_scope.dart';
import '../../../core/state/session_scope.dart';
import '../../../data/platform/backup_file_gateway.dart';
import '../../../data/update/client_update_service.dart';
import '../../auth/pages/login_page.dart';

class SyncSettingsCard extends StatelessWidget {
  const SyncSettingsCard({super.key});
  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: const Text('同步设置'),
          subtitle: Text(
            session.hasServer
                ? session.serverUri.toString()
                : '仅本地使用 · 尚未配置服务器',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: session.isBusy
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const LoginPage()),
                ),
        ),
        if (session.notice != null) ListTile(subtitle: Text(session.notice!)),
        if (session.formError != null)
          Semantics(
            liveRegion: true,
            child: Text(
              session.formError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (session.isAuthenticated)
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('退出登录'),
            subtitle: const Text('停止同步，保留本机数据'),
            onTap: session.isBusy
                ? null
                : () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('退出同步账户'),
                        content: const Text('退出后停止同步。本机任务、计划和专注记录保留，可继续编辑和导出。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('退出登录'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) {
                      try {
                        await session.signOut();
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('退出未完成：$error。本机数据保留。')),
                          );
                        }
                      }
                    }
                  },
          ),
      ],
    );
  }
}

class LocalDataCard extends StatefulWidget {
  const LocalDataCard({super.key});
  @override
  State<LocalDataCard> createState() => _LocalDataCardState();
}

class _LocalDataCardState extends State<LocalDataCard> {
  bool _busy = false;
  String? _operationError;
  bool _showProgress = true;
  static const _files = BackupFileGateway();
  Future<void> _run(
    Future<void> Function() action, {
    bool showProgress = true,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _operationError = null;
      _showProgress = showProgress;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _operationError = '操作未完成：$e');
      _message('操作未完成：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.watchData(context);
    final session = SessionScope.of(context);
    return Column(
      children: [
        if (_busy && _showProgress)
          const LinearProgressIndicator(semanticsLabel: '正在执行数据操作'),
        if (_operationError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _operationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        if (app.activeFocusSession != null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text('请先结束本机专注，再恢复、复制或切换工作区。当前专注期间仍可导出本地备份。'),
          ),
        ListTile(
          leading: const Icon(Icons.save_alt),
          title: const Text('导出本地备份'),
          subtitle: const Text(
            '导出当前工作区、未同步修改及可携带设置（含本机白名单包名），无需联网。不含密码、令牌、服务器配置、专注控制所有权或旧同步游标。',
          ),
          onTap: _busy
              ? null
              : () => _run(() async {
                  final encoded = await app.repository.backups.exportJson(
                    app.repository.selectedAccountId,
                  );
                  if (await _files.saveJson(encoded)) _message('本地备份已保存');
                }),
        ),
        ListTile(
          leading: const Icon(Icons.file_open_outlined),
          title: const Text('从本地备份恢复'),
          subtitle: const Text(
            '支持 v1 备份，最大 50 MiB / 100000 文档。校验后创建新的本地工作区，原工作区保留；停止当前同步，不自动上传。',
          ),
          onTap: _busy || session.isBusy || app.activeFocusSession != null
              ? null
              : () => _run(() async {
                  if (app.activeFocusSession != null) {
                    throw StateError('请先结束当前专注');
                  }
                  final encoded = await _files.openJson();
                  if (encoded == null) return;
                  final id = await app.repository.backups.restoreJson(encoded);
                  await session.useLocalWorkspace();
                  await app.openOfflineWorkspace(id);
                  _message('备份已恢复到新的本地工作区，原工作区保留');
                }),
        ),
        ListTile(
          leading: const Icon(Icons.copy_all_outlined),
          title: const Text('复制为本地工作区'),
          subtitle: const Text('创建并打开本地副本，停止同步，原工作区保留。清除本机会话不代表服务器已撤销此次登录。'),
          onTap: _busy || session.isBusy || app.activeFocusSession != null
              ? null
              : () => _run(() async {
                  if (app.activeFocusSession != null) {
                    throw StateError('请先结束当前专注');
                  }
                  final id = await app.repository.backups.copyToLocal(
                    app.repository.selectedAccountId,
                  );
                  await session.useLocalWorkspace();
                  await app.openOfflineWorkspace(id);
                  _message('已打开本地副本，原工作区保留');
                }),
        ),
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: const Text('打开保留的工作区'),
          subtitle: const Text('离线打开选定的本机工作区并停止当前同步；清除本机会话不代表服务器已撤销此次登录。'),
          onTap: _busy || session.isBusy || app.activeFocusSession != null
              ? null
              : () => _run(() async {
                  if (app.activeFocusSession != null) {
                    throw StateError('请先结束当前专注');
                  }
                  final ids = await app.repository.store.listWorkspaceIds();
                  final alternatives = ids
                      .where((id) => id != app.repository.selectedAccountId)
                      .toList();
                  if (alternatives.isEmpty) {
                    _message('没有其他可打开的本机工作区');
                    return;
                  }
                  if (!context.mounted) return;
                  final id = await showDialog<String>(
                    context: context,
                    builder: (c) => SimpleDialog(
                      title: const Text('选择本机工作区'),
                      children: [
                        for (final id in alternatives)
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(c, id),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: AppSizes.minTouchTarget,
                              ),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  '${id == app.repository.selectedAccountId ? '当前 · ' : ''}${_workspaceLabel(id)}',
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                  if (id == null) return;
                  await session.useLocalWorkspace();
                  await app.openOfflineWorkspace(id);
                }),
        ),
        if (session.isAuthenticated) ...[
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('导出服务器账户数据'),
            subtitle: const Text('需要联网，不含本机未同步修改；请同时保存本地备份'),
            onTap: _busy
                ? null
                : () => _run(() async {
                    if (!await session.ensureFreshSession()) {
                      throw StateError('请重新登录服务器');
                    }
                    final data = await session.repository.apiClient.get(
                      '/v1/account/export',
                    );
                    if (await _files.saveJson(
                      const JsonEncoder.withIndent('  ').convert(data),
                      suggestedName: 'pactick-server-export.json',
                    )) {
                      _message('服务器账户数据已保存');
                    }
                  }),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('删除服务器账户'),
            subtitle: const Text('永久删除服务器账户和数据，保留本机副本'),
            onTap: _busy
                ? null
                : () => _run(_deleteAccount, showProgress: false),
          ),
        ],
      ],
    );
  }

  String _workspaceLabel(String id) {
    if (id == '__local__') return '初始本地工作区';
    if (id.startsWith('__local__:')) {
      final suffix = id.substring(10);
      return '本地副本 · ${suffix.length > 8 ? suffix.substring(0, 8) : suffix}';
    }
    if (id.startsWith('server:')) return Uri.decodeComponent(id.substring(7));
    return '旧版工作区 · $id';
  }

  Future<void> _deleteAccount() async {
    final session = SessionScope.read(context);
    final user = session.user;
    if (user == null) throw StateError('请重新登录后操作');
    final deleted = await showGuardedEditor<bool>(
      context,
      builder: (dismissal) => _DeleteServerAccountDialog(
        session: session,
        server: session.serverUri,
        userId: user.id,
        email: user.email,
        dismissal: dismissal,
      ),
    );
    if (deleted == true) _message('服务器账户已删除，本机数据保留');
  }
}

class ReleasesAboutCard extends StatefulWidget {
  const ReleasesAboutCard({this.service, super.key});
  final ClientUpdateService? service;
  @override
  State<ReleasesAboutCard> createState() => _ReleasesAboutCardState();
}

class _ReleasesAboutCardState extends State<ReleasesAboutCard> {
  static const releases = String.fromEnvironment('RELEASES_URL');
  String? _version;
  bool _loadingVersion = true;
  @override
  void initState() {
    super.initState();
    _readVersion();
  }

  Future<void> _readVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = '${info.version}+${info.buildNumber}');
      }
    } catch (_) {
      /* The current platform may not expose package metadata. */
    } finally {
      if (mounted) setState(() => _loadingVersion = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('关于 Pactick'),
        subtitle: Text(
          '${_version ?? (_loadingVersion ? '正在读取版本' : '版本信息未取得')} · 数据保存在本机，可通过自部署服务器同步；源码公开。查看许可证。',
        ),
        onTap: () => showLicensePage(
          context: context,
          applicationName: 'Pactick',
          applicationVersion: _version ?? '',
        ),
      ),
      ListTile(
        key: const ValueKey('check-client-update-settings'),
        leading: const Icon(Icons.open_in_new),
        title: const Text('查看发布版本'),
        subtitle: Text(releases.isEmpty ? '尚未配置发布页，请查阅分发者的发布说明' : releases),
        onTap: releases.isEmpty
            ? null
            : () async {
                final uri = Uri.tryParse(releases);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  if (uri == null ||
                      !ClientUpdateService.isSafeDownloadUri(uri) ||
                      !await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      )) {
                    throw StateError('无法打开发布页');
                  }
                } catch (_) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('无法打开发布页，请检查发布地址与浏览器')),
                  );
                }
              },
      ),
    ],
  );
}

class _DeleteServerAccountDialog extends StatefulWidget {
  const _DeleteServerAccountDialog({
    required this.session,
    required this.server,
    required this.userId,
    required this.email,
    required this.dismissal,
  });
  final SessionController session;
  final Uri server;
  final String userId;
  final String email;
  final EditorDismissalController dismissal;
  @override
  State<_DeleteServerAccountDialog> createState() =>
      _DeleteServerAccountDialogState();
}

class _DeleteServerAccountDialogState
    extends State<_DeleteServerAccountDialog> {
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmationFocus = FocusNode();
  final _confirmation = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _guard = GlobalKey<EditorDraftGuardState>();
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _password.addListener(_changed);
    _confirmation.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _passwordFocus.dispose();
    _confirmationFocus.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy) return;
    if (!_form.currentState!.validate()) {
      (_password.text.isEmpty ? _passwordFocus : _confirmationFocus)
          .requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.deleteServerAccount(
        _password.text,
        server: widget.server,
        userId: widget.userId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '删除未完成：$error。本机数据保留，可检查连接或重新登录后再试。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: EditorDraftGuard(
      key: _guard,
      dismissal: widget.dismissal,
      dirty: _password.text.isNotEmpty || _confirmation.text.isNotEmpty,
      hasChanges: () =>
          _password.text.isNotEmpty || _confirmation.text.isNotEmpty,
      savingNow: () => _busy,
      saving: _busy,
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
                Expanded(
                  child: Text(
                    '永久删除服务器账户',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭删除确认',
                  onPressed: _busy
                      ? null
                      : () => _guard.currentState?.requestClose(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '服务器：${widget.server}\n账户：${widget.email}\n永久删除此服务器账户及全部服务器数据。本机副本保留；此操作不会删除本机数据。',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _password,
                      focusNode: _passwordFocus,
                      enabled: !_busy,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '当前密码'),
                      validator: (value) =>
                          value == null || value.isEmpty ? '请输入密码' : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _confirmation,
                      focusNode: _confirmationFocus,
                      enabled: !_busy,
                      decoration: const InputDecoration(labelText: '输入 DELETE'),
                      validator: (value) =>
                          value != 'DELETE' ? '请输入 DELETE 确认' : null,
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          EditorActions(
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _guard.currentState?.requestClose(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: _busy ? null : _delete,
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: Text(_busy ? '正在删除…' : '永久删除'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
