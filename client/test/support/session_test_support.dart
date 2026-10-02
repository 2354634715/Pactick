import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pactick/core/models/auth_models.dart';
import 'package:pactick/core/state/session_controller.dart';
import 'package:pactick/data/local/session_store.dart';
import 'package:pactick/data/remote/api_client.dart';
import 'package:pactick/data/repositories/auth_repository.dart';

AuthSession testAuthSession({
  String accessToken = 'test-access-token',
  String refreshToken = 'test-refresh-token',
  DateTime? accessExpiresAt,
  DateTime? refreshExpiresAt,
}) {
  final now = DateTime.now().toUtc();
  return AuthSession(
    user: AuthUser(
      id: 'user-id',
      email: 'lin@example.com',
      displayName: '林默',
      timeZone: 'Asia/Shanghai',
      locale: 'zh-CN',
      weekStartsOn: 1,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    device: const AuthDevice(
      id: 'device-id',
      name: '测试 Android 设备',
      platform: 'android',
      appVersion: '0.1.0',
    ),
    tokens: AuthTokens(
      accessToken: accessToken,
      accessExpiresAt: accessExpiresAt ?? now.add(const Duration(hours: 1)),
      refreshToken: refreshToken,
      refreshExpiresAt: refreshExpiresAt ?? now.add(const Duration(days: 30)),
      tokenType: 'Bearer',
    ),
  );
}

Future<SessionController> createAuthenticatedSessionController({
  AuthenticationChanged? onAuthenticationChanged,
  http.Client? client,
}) async {
  final session = testAuthSession();
  final controller = SessionController(
    repository: AuthRepository(
      sessionStore: MemorySessionStore(
        session: session,
        deviceId: session.device.id,
      ),
      apiClient: ApiClient(
        baseUrl: 'https://api.example.test',
        client:
            client ??
            MockClient(
              (_) async => http.Response(
                jsonEncode(session.toJson()),
                200,
                headers: const {'content-type': 'application/json'},
              ),
            ),
      ),
    ),
    onAuthenticationChanged: onAuthenticationChanged,
  );
  await controller.initialize();
  return controller;
}
