import 'package:uuid/uuid.dart';

import '../../core/models/auth_models.dart';
import '../local/session_store.dart';
import '../remote/api_client.dart';

class AuthRepository {
  AuthRepository({
    required this.sessionStore,
    required this.apiClient,
    Uuid? uuid,
    this.deviceName = 'Android 设备',
    this.platform = 'android',
    this.appVersion = '0.1.0',
  }) : _uuid = uuid ?? Uuid();

  final SessionStore sessionStore;
  final ApiClient apiClient;
  final Uuid _uuid;
  final String deviceName;
  final String platform;
  final String appVersion;

  Uri get serverUri => apiClient.baseUri;

  Future<AuthSession?> restoreSession() async {
    if (!apiClient.isConfigured) return null;
    await sessionStore.selectServer(serverUri.toString());
    final session = await sessionStore.readSession();
    if (session != null) {
      final deviceId = await sessionStore.readDeviceId();
      if (deviceId == null || deviceId.isEmpty) {
        await sessionStore.writeDeviceId(session.device.id);
      } else if (deviceId != session.device.id) {
        await clearSession();
        throw const FormatException('Saved session device does not match.');
      }
    }
    apiClient.accessToken = session?.tokens.accessToken;
    return session;
  }

  Future<AuthSession> login({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (!apiClient.isConfigured) {
      throw const ApiException('server_not_configured', '请先配置同步服务器');
    }
    await sessionStore.selectServer(serverUri.toString());
    await sessionStore.selectIdentity('email:${email.trim().toLowerCase()}');
    final device = await _currentDevice();
    final response = displayName == null
        ? await apiClient.login(
            email: email.trim(),
            password: password,
            device: device.toJson(),
          )
        : await apiClient.register(
            email: email.trim(),
            password: password,
            displayName: displayName.trim(),
            timeZone: 'Asia/Shanghai',
            device: device.toJson(),
          );
    final session = AuthSession.fromJson(response);
    if (session.device.id != device.id) {
      throw const ApiException('device_mismatch', '服务器返回了不匹配的设备会话');
    }
    await _saveSession(session);
    return session;
  }

  Future<AuthSession> refresh(AuthSession current) async {
    final response = await apiClient.refresh(current.tokens.refreshToken);
    final session = AuthSession.fromJson(response);
    if (session.user.id != current.user.id ||
        session.device.id != current.device.id) {
      throw const ApiException('session_mismatch', '服务器返回了不匹配的刷新会话');
    }
    await _saveSession(session);
    return session;
  }

  Future<void> logout(AuthSession session) {
    return apiClient.logout(session.tokens.refreshToken);
  }

  Future<void> clearSession() async {
    apiClient.accessToken = null;
    await sessionStore.clearSession();
  }

  Future<AuthDevice> _currentDevice() async {
    var id = await sessionStore.readDeviceId();
    if (id == null || id.isEmpty) {
      id = _uuid.v4();
      await sessionStore.writeDeviceId(id);
    }
    return AuthDevice(
      id: id,
      name: deviceName,
      platform: platform,
      appVersion: appVersion,
    );
  }

  Future<void> _saveSession(AuthSession session) async {
    await sessionStore.writeSession(session);
    apiClient.accessToken = session.tokens.accessToken;
  }

  void close() => apiClient.close();
}
