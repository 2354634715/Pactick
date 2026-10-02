import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/remote/api_client.dart';
import '../../data/remote/server_address.dart';
import '../../data/repositories/auth_repository.dart';
import '../models/auth_models.dart';

enum SessionPhase { initializing, signedOut, signingIn, signedIn, signingOut }

typedef AuthenticationChanged = FutureOr<void> Function(
  bool authenticated,
  bool connectionUnavailable,
);

class SessionController extends ChangeNotifier {
  SessionController({
    required this.repository,
    this.onAuthenticationChanged,
    this.beforeSessionChange,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AuthRepository repository;
  final AuthenticationChanged? onAuthenticationChanged;
  final Future<void> Function()? beforeSessionChange;
  final DateTime Function() _now;

  SessionPhase phase = SessionPhase.initializing;
  AuthSession? session;
  Object? initializationError;
  String? formError;
  String? notice;
  bool connectionUnavailable = false;
  String? uploadSourceWorkspace;

  Timer? _refreshTimer;
  Future<bool>? _activeRefresh;
  bool _disposed = false;

  bool get isReady => phase != SessionPhase.initializing;
  bool get isAuthenticated => session != null;
  bool get isBusy =>
      phase == SessionPhase.initializing ||
      phase == SessionPhase.signingIn ||
      phase == SessionPhase.signingOut;
  AuthUser? get user => session?.user;
  AuthDevice? get device => session?.device;
  Uri get serverUri => repository.serverUri;
  bool get hasServer => repository.apiClient.isConfigured;

  Future<void> configureServer(String address) async {
    if (isBusy) throw StateError('请等待当前登录操作完成');
    final normalized = normalizeServerAddress(address);
    _refreshTimer?.cancel();
    phase = SessionPhase.signingOut;
    _notify();
    if (_activeRefresh != null) await _activeRefresh;
    _refreshTimer?.cancel();
    await beforeSessionChange?.call();
    repository.apiClient.configureServer(normalized);
    session = null;
    connectionUnavailable = false;
    await initialize();
  }

  Future<void> useLocalWorkspace() async {
    if (isBusy) throw StateError('请等待当前登录操作完成');
    _refreshTimer?.cancel();
    phase = SessionPhase.signingOut;
    if (_activeRefresh != null) await _activeRefresh;
    _refreshTimer?.cancel();
    await beforeSessionChange?.call();
    try {
      await repository.clearSession();
    } catch (_) {
      repository.apiClient.accessToken = null;
      notice = '无法确认本机登录信息已清除；同步已停止，本机数据仍可使用。';
    }
    session = null;
    phase = SessionPhase.signedOut;
    connectionUnavailable = false;
    await onAuthenticationChanged?.call(false, false);
    _notify();
  }

  Future<void> deleteServerAccount(
    String password, {
    required Uri server,
    required String userId,
  }) async {
    if (isBusy || !await ensureFreshSession()) {
      throw StateError('请重新登录后操作');
    }
    if (serverUri != server || user?.id != userId) {
      throw StateError('当前服务器或账户已变化，请重新确认删除对象。');
    }
    _refreshTimer?.cancel();
    phase = SessionPhase.signingOut;
    _notify();
    try {
      await beforeSessionChange?.call();
      await repository.apiClient.delete(
        '/v1/account',
        body: {'password': password, 'confirmation': 'DELETE'},
      );
      try {
        await repository.clearSession();
      } catch (_) {
        repository.apiClient.accessToken = null;
        notice = '服务器账户已删除，但无法确认本机登录信息已清除。';
      }
      session = null;
      phase = SessionPhase.signedOut;
      await onAuthenticationChanged?.call(false, false);
    } catch (_) {
      phase = session == null ? SessionPhase.signedOut : SessionPhase.signedIn;
      _scheduleRefresh();
      rethrow;
    } finally {
      _notify();
    }
  }

  String get serverLabel {
    final uri = serverUri;
    if (!hasServer) return '仅本地使用';
    if (uri.host == '10.0.2.2' || uri.host == 'localhost') {
      return '本地开发服务';
    }
    return uri.host.isEmpty ? uri.toString() : uri.host;
  }

  Future<void> initialize({bool restore = true}) async {
    _refreshTimer?.cancel();
    session = null;
    repository.apiClient.accessToken = null;
    phase = SessionPhase.initializing;
    initializationError = null;
    formError = null;
    _notify();
    try {
      if (!restore) {
        phase = SessionPhase.signedOut;
        return;
      }
      final restored = await repository.restoreSession();
      if (restored == null) {
        phase = SessionPhase.signedOut;
        return;
      }
      if (!_now().toUtc().isBefore(restored.tokens.refreshExpiresAt)) {
        await repository.clearSession();
        notice = '登录已过期，请重新登录。';
        phase = SessionPhase.signedOut;
        await onAuthenticationChanged?.call(false, false);
        return;
      }

      session = restored;
      phase = SessionPhase.signedIn;
      if (_accessNeedsRefresh(restored)) {
        await _refreshRestoredSession();
      } else {
        _scheduleRefresh();
        await onAuthenticationChanged?.call(true, false);
      }
    } catch (error, stackTrace) {
      debugPrint('Session initialization failed: $error\n$stackTrace');
      _refreshTimer?.cancel();
      session = null;
      repository.apiClient.accessToken = null;
      initializationError = error;
      formError = '无法读取本机登录信息，请重试。';
      phase = SessionPhase.signedOut;
    } finally {
      _notify();
    }
  }

  Future<void> retryInitialization() => initialize();

  void clearFormError() {
    if (formError == null) return;
    formError = null;
    _notify();
  }

  Future<bool> signIn({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (isBusy) return false;
    _refreshTimer?.cancel();
    phase = SessionPhase.signingIn;
    initializationError = null;
    formError = null;
    notice = null;
    connectionUnavailable = false;
    _notify();
    try {
      if (_activeRefresh != null) await _activeRefresh;
      _refreshTimer?.cancel();
      await beforeSessionChange?.call();
      session = null;
      await repository.clearSession();
      final signedIn = await repository.login(
        email: email,
        password: password,
        displayName: displayName,
      );
      session = signedIn;
      phase = SessionPhase.signedIn;
      _scheduleRefresh();
      await onAuthenticationChanged?.call(true, false);
      _notify();
      return true;
    } on ApiException catch (error) {
      phase = SessionPhase.signedOut;
      formError = _messageForApiError(error);
    } on ApiNetworkException {
      phase = SessionPhase.signedOut;
      connectionUnavailable = true;
      formError = '无法连接服务器，请检查网络后重试。';
    } on FormatException catch (error, stackTrace) {
      debugPrint('Invalid login response: $error\n$stackTrace');
      phase = SessionPhase.signedOut;
      formError = '服务器返回了无法识别的登录信息。';
    } catch (error, stackTrace) {
      debugPrint('Sign in failed: $error\n$stackTrace');
      phase = SessionPhase.signedOut;
      formError = '登录未完成，请稍后重试。';
    }
    _refreshTimer?.cancel();
    session = null;
    try {
      await repository.clearSession();
    } catch (_) {
      repository.apiClient.accessToken = null;
    }
    await onAuthenticationChanged?.call(false, connectionUnavailable);
    _notify();
    return false;
  }

  Future<bool> ensureFreshSession({bool force = false}) {
    final current = session;
    if (current == null || isBusy) {
      return Future.value(false);
    }
    if (!force && !_accessNeedsRefresh(current)) return Future.value(true);
    return _activeRefresh ??= _refreshCurrentSession().whenComplete(() {
      _activeRefresh = null;
    });
  }

  Future<void> signOut() async {
    final sessionBeforeRefresh = session;
    if (sessionBeforeRefresh == null || phase == SessionPhase.signingOut) {
      return;
    }
    _refreshTimer?.cancel();
    phase = SessionPhase.signingOut;
    formError = null;
    _notify();

    final refreshInProgress = _activeRefresh;
    if (refreshInProgress != null) {
      await refreshInProgress;
      _refreshTimer?.cancel();
    }
    await beforeSessionChange?.call();
    final current = session ?? sessionBeforeRefresh;

    var serverRevoked = true;
    try {
      await repository.logout(current);
    } catch (error, stackTrace) {
      serverRevoked = false;
      debugPrint('Remote logout failed: $error\n$stackTrace');
    }
    var localCleared = true;
    try {
      await repository.clearSession();
    } catch (error, stackTrace) {
      localCleared = false;
      debugPrint('Clearing the local session failed: $error\n$stackTrace');
    }

    session = null;
    phase = SessionPhase.signedOut;
    connectionUnavailable = false;
    notice = !localCleared
        ? '无法确认本机登录信息已清除。在系统设置中清除应用数据会删除本机数据，请先备份。'
        : serverRevoked
        ? '已退出登录，本机任务数据保留。'
        : '本机登录信息已清除，但无法确认服务器已撤销此次登录。';
    await onAuthenticationChanged?.call(false, false);
    _notify();
  }

  Future<void> _refreshRestoredSession() async {
    final current = session!;
    try {
      session = await repository.refresh(current);
      connectionUnavailable = false;
      _scheduleRefresh();
      await onAuthenticationChanged?.call(true, false);
    } on ApiException catch (error) {
      if (_isInvalidSession(error)) {
        await repository.clearSession();
        session = null;
        phase = SessionPhase.signedOut;
        notice = '登录已失效，请重新登录。';
        await onAuthenticationChanged?.call(false, false);
        return;
      }
      connectionUnavailable = true;
      notice = '服务器暂时不可用，已进入离线工作区。';
      _scheduleRetry();
      await onAuthenticationChanged?.call(true, true);
    } on ApiNetworkException {
      connectionUnavailable = true;
      notice = '当前离线，使用本机保存的登录信息。';
      _scheduleRetry();
      await onAuthenticationChanged?.call(true, true);
    } catch (error, stackTrace) {
      debugPrint('Restored session refresh failed: $error\n$stackTrace');
      connectionUnavailable = true;
      notice = '当前离线，使用本机保存的登录信息。';
      _scheduleRetry();
      await onAuthenticationChanged?.call(true, true);
    }
  }

  Future<bool> _refreshCurrentSession() async {
    final current = session;
    if (current == null) return false;
    try {
      session = await repository.refresh(current);
      connectionUnavailable = false;
      notice = null;
      _scheduleRefresh();
      await onAuthenticationChanged?.call(true, false);
      _notify();
      return true;
    } on ApiException catch (error) {
      if (_isInvalidSession(error)) {
        await repository.clearSession();
        session = null;
        phase = SessionPhase.signedOut;
        formError = '登录已失效，请重新登录。';
        await onAuthenticationChanged?.call(false, false);
      } else {
        connectionUnavailable = true;
        _scheduleRetry();
        await onAuthenticationChanged?.call(true, true);
      }
    } on ApiNetworkException {
      connectionUnavailable = true;
      _scheduleRetry();
      await onAuthenticationChanged?.call(true, true);
    } catch (error, stackTrace) {
      debugPrint('Session refresh failed: $error\n$stackTrace');
      connectionUnavailable = true;
      _scheduleRetry();
      await onAuthenticationChanged?.call(true, true);
    }
    _notify();
    return false;
  }

  bool _accessNeedsRefresh(AuthSession value) {
    return !value.tokens.accessExpiresAt.isAfter(
      _now().toUtc().add(const Duration(minutes: 2)),
    );
  }

  bool _isInvalidSession(ApiException error) {
    return error.statusCode == 401 ||
        error.code == 'invalid_refresh_token' ||
        error.code == 'refresh_token_reuse' ||
        error.code == 'device_revoked';
  }

  String _messageForApiError(ApiException error) {
    return switch (error.code) {
      'invalid_credentials' => '邮箱或密码不正确。',
      'registration_disabled' => '服务器尚未开放注册，请联系服务器管理员。',
      'email_exists' || 'email_taken' => '该邮箱已注册，请直接登录。',
      'device_conflict' => '此设备已关联到另一个账户，请先撤销旧设备会话。',
      'validation_error' => '登录信息格式不正确，请检查后重试。',
      'rate_limited' => '登录尝试过于频繁，请稍后再试。',
      'invalid_response' ||
      'device_mismatch' ||
      'session_mismatch' => '服务器返回了无法识别的登录信息。',
      'authentication_unavailable' ||
      'internal_error' ||
      'server_unavailable' => '登录服务暂时不可用，请稍后重试。',
      _ => '登录失败，请稍后重试。',
    };
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    final current = session;
    if (current == null) return;
    final refreshAt = current.tokens.accessExpiresAt.subtract(
      const Duration(minutes: 2),
    );
    var delay = refreshAt.difference(_now().toUtc());
    if (delay.isNegative || delay == Duration.zero) {
      delay = const Duration(seconds: 1);
    }
    _refreshTimer = Timer(
      delay,
      () => unawaited(ensureFreshSession(force: true)),
    );
  }

  void _scheduleRetry() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      const Duration(minutes: 1),
      () => unawaited(ensureFreshSession(force: true)),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    repository.close();
    super.dispose();
  }
}
