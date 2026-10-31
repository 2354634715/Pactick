import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/platform/system_calendar_gateway.dart';
import '../../data/repositories/workspace_repository.dart';
import '../calendar/system_calendar_models.dart';
import '../calendar/system_calendar_sync_engine.dart';
import '../localization/app_localizations.dart';

/// Coordinates foreground calendar work without changing account sync rules.
class SystemCalendarController extends ChangeNotifier {
  SystemCalendarController({
    required this.repository,
    required this.gateway,
    required this.canRun,
    required this.onLocalChanged,
    this.debounce = const Duration(seconds: 2),
  }) : _engine = SystemCalendarSyncEngine(
         store: repository.store,
         gateway: gateway,
       );

  final WorkspaceRepository repository;
  final SystemCalendarGateway gateway;
  final bool Function() canRun;
  final Future<void> Function(String accountId) onLocalChanged;
  final Duration debounce;
  final SystemCalendarSyncEngine _engine;

  SystemCalendarConfiguration configuration =
      const SystemCalendarConfiguration();
  SystemCalendarPermissions permissions = const SystemCalendarPermissions(
    supported: false,
    canRead: false,
    canWrite: false,
  );
  List<SystemCalendarInfo> calendars = const [];
  SystemCalendarSyncResult? lastResult;
  Object? error;
  String? _accountId;
  Object? _dataSnapshot;
  int _workspaceGeneration = 0;
  int _syncGeneration = 0;
  int _localMutations = 0;
  bool _loaded = false;
  bool _foreground = true;
  bool _available = false;
  bool _configuring = false;
  bool _disposed = false;
  bool _applyingResult = false;
  bool _needsReload = false;
  bool _resyncRequested = false;
  Timer? _timer;
  StreamSubscription<void>? _subscription;
  Future<void>? _flight;

  bool get supported => gateway.isSupported;
  bool get busy => _configuring || _flight != null;
  bool get enabled => configuration.enabled;
  bool get canSynchronize =>
      supported &&
      _loaded &&
      _foreground &&
      canRun() &&
      _localMutations == 0 &&
      configuration.enabled &&
      configuration.calendar != null;

  String? get errorMessage {
    final failure = error;
    if (failure == null) return null;
    if (failure is PlatformException) {
      return switch (failure.code) {
        'calendar_permission_denied' => tr('系统日历权限未授予或已撤销，请重新授权。'),
        'calendar_read_only' => tr('所选日历只允许读取，客户端更改尚未写入。'),
        'calendar_not_found' ||
        'calendar_changed' => tr('所选日历已不可用或身份已变化，请重新选择。'),
        'calendar_conflict' => tr('系统日程在保存前又发生变化，请重新同步后处理冲突。'),
        'calendar_too_many_events' => tr('日程数量超过本次读取上限，请缩短同步范围后重试。'),
        'calendar_state_invalid' => tr('系统日历连接记录无法读取，请保留本机数据并重试。'),
        'calendar_unsupported' => tr('当前平台或日历服务不支持此操作。'),
        _ => tr('系统日历操作未完成，请检查权限与日历状态后重试。'),
      };
    }
    return tr('系统日历操作未完成，本机计划已保留。请重试。');
  }

  /// Called for ordinary data changes; focus ticks and private records do not
  /// need another provider query.
  void workspaceDataChanged(Object snapshot) {
    if (_disposed || snapshot == _dataSnapshot) return;
    _dataSnapshot = snapshot;
    final accountId = repository.selectedAccountId;
    final available = canRun();
    if (_available && !available) _cancelRun();
    _available = available;
    if (_accountId != accountId) {
      unawaited(_activateWorkspace(accountId));
      return;
    }
    if (!_applyingResult) _schedule();
  }

  Future<void> _activateWorkspace(String accountId) async {
    _accountId = accountId;
    final generation = ++_workspaceGeneration;
    _cancelRun();
    _loaded = false;
    configuration = const SystemCalendarConfiguration();
    _updateSubscription();
    calendars = const [];
    lastResult = null;
    error = null;
    _notify();
    try {
      final loaded = await _engine.loadConfiguration(accountId);
      if (!_ownsWorkspace(accountId, generation)) return;
      configuration = loaded;
      _loaded = true;
      if (enabled && supported) {
        final access = SystemCalendarPermissions.fromMap(
          await gateway.getPermissions(),
        );
        if (!_ownsWorkspace(accountId, generation)) return;
        permissions = access;
      }
      _updateSubscription();
      _schedule();
    } catch (failure) {
      if (_ownsWorkspace(accountId, generation)) error = failure;
    } finally {
      if (_ownsWorkspace(accountId, generation)) _notify();
    }
  }

  bool _ownsWorkspace(String id, int generation) =>
      !_disposed &&
      _workspaceGeneration == generation &&
      _accountId == id &&
      repository.selectedAccountId == id;

  Future<void> refreshAccess({bool listCalendars = false}) async {
    if (!supported || _disposed) return;
    final accountId = repository.selectedAccountId;
    final generation = _workspaceGeneration;
    try {
      final access = SystemCalendarPermissions.fromMap(
        await gateway.getPermissions(),
      );
      if (!_ownsWorkspace(accountId, generation)) return;
      permissions = access;
      if (listCalendars && access.canRead) {
        final rows = await gateway.listCalendars();
        if (!_ownsWorkspace(accountId, generation)) return;
        calendars = rows
            .map(SystemCalendarInfo.fromMap)
            .toList(growable: false);
      }
      error = null;
      _updateSubscription();
    } catch (failure) {
      if (_ownsWorkspace(accountId, generation)) error = failure;
    }
    if (_ownsWorkspace(accountId, generation)) _notify();
  }

  Future<void> requestAccess({bool write = false}) async {
    if (!supported || busy || _disposed) return;
    final accountId = repository.selectedAccountId;
    final generation = _workspaceGeneration;
    _configuring = true;
    _updateSubscription();
    error = null;
    _notify();
    try {
      final access = SystemCalendarPermissions.fromMap(
        await gateway.requestPermissions(write: write),
      );
      if (!_ownsWorkspace(accountId, generation)) return;
      permissions = access;
      if (access.canRead) {
        final rows = await gateway.listCalendars();
        if (!_ownsWorkspace(accountId, generation)) return;
        calendars = rows
            .map(SystemCalendarInfo.fromMap)
            .toList(growable: false);
      } else {
        error = PlatformException(code: 'calendar_permission_denied');
      }
      _updateSubscription();
      _schedule();
    } catch (failure) {
      if (_ownsWorkspace(accountId, generation)) error = failure;
    } finally {
      _configuring = false;
      _updateSubscription();
      _schedule();
      if (!_disposed) _notify();
    }
  }

  Future<void> configure({
    required bool enabled,
    SystemCalendarInfo? calendar,
    int? futureDays,
  }) async {
    if (_disposed || _configuring) return;
    final accountId = repository.selectedAccountId;
    final workspaceGeneration = ++_workspaceGeneration;
    final selected = calendar ?? configuration.calendar;
    _configuring = true;
    _updateSubscription();
    _cancelRun();
    error = null;
    _notify();
    try {
      await _flight;
      if (!_ownsWorkspace(accountId, workspaceGeneration)) return;
      await _engine.configure(
        accountId,
        enabled: enabled,
        calendar: selected,
        pastDays: 30,
        futureDays: futureDays ?? configuration.futureDays,
      );
      if (!_ownsWorkspace(accountId, workspaceGeneration)) return;
      configuration = await _engine.loadConfiguration(accountId);
      if (!_ownsWorkspace(accountId, workspaceGeneration)) return;
      _loaded = true;
      lastResult = null;
      _updateSubscription();
    } catch (failure) {
      if (_ownsWorkspace(accountId, workspaceGeneration)) error = failure;
    } finally {
      _configuring = false;
      _updateSubscription();
      if (!_disposed) {
        _notify();
        _schedule();
      }
    }
  }

  Future<T> protectLocalMutation<T>(Future<T> Function() operation) async {
    _localMutations++;
    _updateSubscription();
    _cancelRun();
    try {
      await _flight;
      return await operation();
    } finally {
      _localMutations--;
      _updateSubscription();
      if (!_disposed) _schedule();
    }
  }

  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      _cancelRun();
    } else if (enabled) {
      unawaited(refreshAccess());
      _schedule();
    }
    _updateSubscription();
  }

  void _cancelRun() {
    _syncGeneration++;
    _timer?.cancel();
    _timer = null;
    _resyncRequested = false;
  }

  void _schedule() {
    _timer?.cancel();
    if (!canSynchronize || _configuring) return;
    if (_flight != null) {
      _resyncRequested = true;
      return;
    }
    _timer = Timer(debounce, () => unawaited(syncNow()));
  }

  void _updateSubscription() {
    final watch =
        !_disposed &&
        !_configuring &&
        _localMutations == 0 &&
        supported &&
        _foreground &&
        enabled &&
        permissions.canRead;
    if (!watch) {
      final current = _subscription;
      _subscription = null;
      if (current != null) unawaited(current.cancel());
    } else {
      _subscription ??= gateway.changes.listen(
        (_) => _schedule(),
        onError: (Object failure) {
          if (_disposed) return;
          error = failure;
          _notify();
        },
      );
    }
  }

  Future<void> syncNow({
    Map<String, SystemCalendarConflictChoice> resolutions = const {},
  }) {
    _timer?.cancel();
    if (_flight != null) return _flight!;
    if (!canSynchronize || _configuring) return Future<void>.value();
    final accountId = repository.selectedAccountId;
    final generation = _syncGeneration;
    bool current() =>
        !_disposed &&
        _syncGeneration == generation &&
        repository.selectedAccountId == accountId &&
        canSynchronize;
    error = null;
    final future = _synchronize(accountId, current, resolutions);
    _flight = future;
    _notify();
    return future;
  }

  Future<void> _synchronize(
    String accountId,
    bool Function() current,
    Map<String, SystemCalendarConflictChoice> resolutions,
  ) async {
    try {
      final result = await _engine.sync(
        accountId: accountId,
        isCurrent: current,
        resolutions: resolutions,
      );
      if (!current()) return;
      lastResult = result;
      if (result.localChanged || _needsReload) {
        _applyingResult = true;
        try {
          await onLocalChanged(accountId);
          _needsReload = false;
        } finally {
          _applyingResult = false;
        }
      }
    } on SystemCalendarSyncCancelled {
      _needsReload = true;
    } catch (failure) {
      if (current()) {
        error = failure;
        // A provider/checkpoint failure can follow a committed local import.
        _needsReload = true;
        _applyingResult = true;
        try {
          await onLocalChanged(accountId);
          _needsReload = false;
        } catch (_) {
          // Keep the original error and retry the reload on the next sync.
        } finally {
          _applyingResult = false;
        }
      }
    } finally {
      _flight = null;
      if (!_disposed) {
        _notify();
        if (_resyncRequested) {
          _resyncRequested = false;
          _schedule();
        }
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _workspaceGeneration++;
    _cancelRun();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }
}
