import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/models/domain_models.dart';
import '../core/state/app_scope.dart';
import '../core/state/app_controller.dart';
import '../core/state/session_scope.dart';
import '../core/state_views/state_pane.dart';
import '../data/update/client_update_service.dart';
import 'navigation/adaptive_app_shell.dart';
import 'theme/app_theme.dart';

class PactickApp extends StatefulWidget {
  const PactickApp({
    this.clientUpdateService,
    this.automaticallyCheckForUpdates = false,
    super.key,
  });
  // Compatibility with existing embedders: updates never block local use.
  final ClientUpdateService? clientUpdateService;
  final bool automaticallyCheckForUpdates;
  @override
  State<PactickApp> createState() => _PactickAppState();
}

class _PactickAppState extends State<PactickApp> with WidgetsBindingObserver {
  AppController? _controller;
  Object? _presentation;

  Object _snapshot(AppController app) => (
    app.themePreference,
    app.useDynamicColor,
    app.isReady,
    app.initializationError,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.read(context);
    if (_controller == controller) return;
    _controller?.removeListener(_onPresentationChanged);
    _controller = controller;
    _presentation = _snapshot(controller);
    controller.addListener(_onPresentationChanged);
  }

  void _onPresentationChanged() {
    final value = _snapshot(_controller!);
    if (value == _presentation) return;
    setState(() => _presentation = value);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPresentationChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final app = AppScope.read(context);
    unawaited(app.refreshGuardPermissions());
    unawaited(app.refreshGuardActivityStats());
    unawaited(_resumeSync());
  }

  Future<void> _resumeSync() async {
    final app = AppScope.read(context);
    final session = SessionScope.read(context);
    if (app.canSync && await session.ensureFreshSession()) {
      await app.syncNow(automatic: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return DynamicColorBuilder(
      builder: (light, dark) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Pactick',
        theme: AppTheme.light(app.useDynamicColor ? light : null),
        darkTheme: AppTheme.dark(app.useDynamicColor ? dark : null),
        themeMode: switch (app.themePreference) {
          ThemePreference.system => ThemeMode.system,
          ThemePreference.light => ThemeMode.light,
          ThemePreference.dark => ThemeMode.dark,
        },
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: !app.isReady
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : app.initializationError != null
            ? Scaffold(
                body: StatePane.error(
                  title: '无法打开本地工作区',
                  message: '本机数据初始化未完成，请重试。',
                  actionLabel: '重试',
                  onAction: app.retryInitialization,
                ),
              )
            : AppDataBoundary(controller: app, child: const AdaptiveAppShell()),
      ),
    );
  }
}
