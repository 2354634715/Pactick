import 'package:flutter/widgets.dart';

import 'app_controller.dart';

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    required AppController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this context.');
    return scope!.notifier!;
  }

  static AppController read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<AppScope>();
    final scope = element?.widget as AppScope?;
    assert(scope != null, 'AppScope is missing above this context.');
    return scope!.notifier!;
  }

  static AppController watchData(BuildContext context) {
    final data = context.dependOnInheritedWidgetOfExactType<_AppDataScope>();
    return data?.notifier?.controller ?? of(context);
  }
}

/// Keeps the existing controller while excluding timer-only notifications.
class AppDataBoundary extends StatefulWidget {
  const AppDataBoundary({
    required this.controller,
    required this.child,
    super.key,
  });
  final AppController controller;
  final Widget child;
  @override
  State<AppDataBoundary> createState() => _AppDataBoundaryState();
}

class _AppDataBoundaryState extends State<AppDataBoundary> {
  late _AppDataNotifier _notifier;
  @override
  void initState() {
    super.initState();
    _notifier = _AppDataNotifier(widget.controller);
  }

  @override
  void didUpdateWidget(AppDataBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _notifier.dispose();
      _notifier = _AppDataNotifier(widget.controller);
    }
  }

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _AppDataScope(notifier: _notifier, child: widget.child);
}

class _AppDataScope extends InheritedNotifier<_AppDataNotifier> {
  const _AppDataScope({required super.notifier, required super.child});
}

class _AppDataNotifier extends ChangeNotifier {
  _AppDataNotifier(this.controller) {
    _value = _snapshot();
    controller.addListener(_changed);
  }
  final AppController controller;
  Object? _value;
  Object _snapshot() => (
    controller.tasks,
    controller.projects,
    controller.planBlocks,
    controller.focusSessions,
    controller.focusPolicies,
    controller.devices,
    controller.isReady,
    controller.initializationError,
    controller.themePreference,
    controller.useDynamicColor,
    controller.notificationsEnabled,
    controller.usageAccessGranted,
    controller.overlayPermissionGranted,
    controller.installedApplications,
    controller.installedApplicationsLoading,
    controller.installedApplicationsError,
    controller.syncPhase,
    controller.pendingOperations,
    controller.syncErrorMessage,
    controller.lastSuccessfulSyncAt,
    controller.syncRejections,
    controller.isSwitchingSyncAccount,
    controller.accountConnectionError,
    controller.repository.selectedAccountId,
    controller.canStartFocus,
    [null, ...controller.projects.map((p) => p.id)]
        .map((id) {
          final packages = controller.appWhitelistForProject(id).toList()
            ..sort();
          return '$id:${packages.join(',')}';
        })
        .join('|'),
  );
  void _changed() {
    final value = _snapshot();
    if (value == _value) return;
    _value = value;
    notifyListeners();
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    super.dispose();
  }
}
