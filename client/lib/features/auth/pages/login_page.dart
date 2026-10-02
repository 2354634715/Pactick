import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/components/feature_page_scaffold.dart';
import '../../../core/dialogs/editor_frame.dart';
import '../../../core/state/app_scope.dart';
import '../../../core/state/session_scope.dart';
import '../../../data/remote/server_address.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({this.onCheckForUpdate, super.key});
  final Future<void> Function()? onCheckForUpdate;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _serverFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _nameFocus = FocusNode();
  final _guard = GlobalKey<EditorDraftGuardState>();
  late final String _initialDraft;
  final _server = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _upload = false;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _server.text = SessionScope.read(context).serverUri.toString();
    _initialDraft = _draft;
    for (final field in [_server, _email, _password, _name]) {
      field.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  String get _draft => jsonEncode([
    _server.text,
    _email.text,
    _password.text,
    _name.text,
    _upload,
    _register,
  ]);

  @override
  void dispose() {
    _serverFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _nameFocus.dispose();
    _server.dispose();
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final app = AppScope.watchData(context);
    final blocked = app.activeFocusSession != null;
    return EditorDraftGuard(
      key: _guard,
      dirty: _draft != _initialDraft,
      hasChanges: () => _draft != _initialDraft,
      savingNow: () => _busy,
      saving: _busy,
      child: Scaffold(
        appBar: buildPageAppBar(
          context,
          title: '连接同步账户',
          low:
              MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom <
              AppSizes.lowHeight,
          leading: IconButton(
            tooltip: '返回',
            onPressed: _busy ? null : () => _guard.currentState?.requestClose(),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSizes.formMax),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const Text(
                  '登录只用于可选同步。无账户或网络时，本地任务、计划与专注仍可使用。未选择上传时打开服务器与账户独立的工作区，当前工作区保留。',
                ),
                if (blocked)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.md),
                    child: Text('请先结束本机专注，再连接或切换同步账户。'),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _server,
                        focusNode: _serverFocus,
                        key: const Key('server_address'),
                        enabled: !_busy,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: '服务器 HTTPS 地址',
                          hintText: 'https://sync.example.com',
                        ),
                        validator: (value) {
                          try {
                            if (normalizeServerAddress(value ?? '').isEmpty) {
                              return '请输入服务器地址';
                            }
                          } on FormatException catch (e) {
                            return e.message;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _email,
                        focusNode: _emailFocus,
                        key: const Key('login_email'),
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: '邮箱'),
                        validator: (v) =>
                            v == null || !v.contains('@') ? '请输入有效邮箱' : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        key: const Key('login_password'),
                        enabled: !_busy,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '密码'),
                        validator: (v) =>
                            v == null || v.isEmpty ? '请输入密码' : null,
                      ),
                      if (_register) ...[
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _name,
                          focusNode: _nameFocus,
                          enabled: !_busy,
                          decoration: const InputDecoration(labelText: '显示名称'),
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? '请输入显示名称' : null,
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: AppSpacing.sm),
                          child: Text('注册前需联系服务器管理员临时开启注册；注册完成后应关闭注册。'),
                        ),
                      ],
                      CheckboxListTile(
                        value: _upload,
                        onChanged: _busy || session.isBusy || blocked
                            ? null
                            : (v) => setState(() => _upload = v!),
                        title: const Text('复制当前本地数据并上传'),
                        subtitle: Text(
                          '来源：${app.repository.selectedAccountId}\n目标：${_server.text} · ${_email.text.isEmpty ? '所填账户' : _email.text}\n勾选后复制并上传当前工作区全部内容，原工作区保留。目标工作区已存在时拒绝复制，不合并或覆盖。默认不选。',
                        ),
                      ),
                      if (_error ?? session.formError case final error?)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              error,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      FilledButton(
                        key: const Key('login_submit'),
                        onPressed: _busy || session.isBusy || blocked
                            ? null
                            : _submit,
                        child: Text(
                          _busy
                              ? '正在连接…'
                              : _register
                              ? '注册并连接'
                              : '登录',
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _register = !_register;
                                _error = null;
                              }),
                        child: Text(_register ? '返回登录' : '注册账户'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_form.currentState!.validate()) {
      var validServer = false;
      try {
        validServer = normalizeServerAddress(_server.text).isNotEmpty;
      } on FormatException {
        validServer = false;
      }
      if (!validServer) {
        _serverFocus.requestFocus();
      } else if (!_email.text.contains('@')) {
        _emailFocus.requestFocus();
      } else if (_password.text.isEmpty) {
        _passwordFocus.requestFocus();
      } else {
        _nameFocus.requestFocus();
      }
      return;
    }
    final app = AppScope.read(context);
    final session = SessionScope.read(context);
    if (app.activeFocusSession != null) {
      setState(() => _error = '请先结束当前专注，再连接同步账户。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final source = app.repository.selectedAccountId;
    try {
      final address = normalizeServerAddress(_server.text);
      if (session.serverUri.toString() != address) {
        await session.configureServer(address);
      }
      await app.repository.writeGlobalSetting('sync_server_v2', address);
      session.uploadSourceWorkspace = _upload ? source : null;
      final success = await session.signIn(
        email: _email.text,
        password: _password.text,
        displayName: _register ? _name.text : null,
      );
      session.uploadSourceWorkspace = null;
      if (success && mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '连接未完成：$e');
    } finally {
      session.uploadSourceWorkspace = null;
      if (mounted) setState(() => _busy = false);
    }
  }
}
