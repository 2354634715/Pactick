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
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _routes = _AppRouteObserver();
  bool _checkingReminderLaunch = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_handleReminderLaunch());
    });
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
    unawaited(app.refreshTaskReminders());
    unawaited(_handleReminderLaunch());
    unawaited(_resumeSync());
  }

  Future<void> _handleReminderLaunch() async {
    if (_checkingReminderLaunch) return;
    _checkingReminderLaunch = true;
    try {
      final app = _controller;
      if (app == null || !await app.takeTaskReminderOpenRequest() || !mounted) {
        return;
      }
      // Respect existing unsaved-form guards while returning to the task page.
      while (mounted) {
        final route = _routes.current;
        final navigator = _navigatorKey.currentState;
        if (route == null || route.isFirst || navigator == null) break;
        await navigator.maybePop();
        if (route.isActive) break;
      }
    } finally {
      _checkingReminderLaunch = false;
    }
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
        navigatorKey: _navigatorKey,
        navigatorObservers: [_routes],
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

class _AppRouteObserver extends NavigatorObserver {
  Route<dynamic>? current;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    current = route;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    current = previousRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (current == oldRoute) current = newRoute;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (current == route) current = previousRoute;
  }
}
