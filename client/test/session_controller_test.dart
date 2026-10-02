import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pactick/core/state/session_controller.dart';
import 'package:pactick/data/local/session_store.dart';
import 'package:pactick/data/remote/api_client.dart';
import 'package:pactick/data/repositories/auth_repository.dart';

import 'support/session_test_support.dart';

void main() {
  test(
    'account deletion stays bound to the confirmed server and user',
    () async {
      final saved = testAuthSession();
      final controller = _controller(
        store: MemorySessionStore(session: saved, deviceId: saved.device.id),
        client: MockClient(
          (_) async => fail('must not send credentials to a changed target'),
        ),
      );
      await controller.initialize();
      await expectLater(
        controller.deleteServerAccount(
          'password',
          server: Uri.parse('https://other.example.test'),
          userId: saved.user.id,
        ),
        throwsStateError,
      );
      expect(controller.isAuthenticated, isTrue);
      controller.dispose();
    },
  );

  test(
    'account deletion sends password confirmation and clears the local session',
    () async {
      final saved = testAuthSession();
      final store = MemorySessionStore(
        session: saved,
        deviceId: saved.device.id,
      );
      var deleted = false;
      final controller = _controller(
        store: store,
        client: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/v1/account');
          expect(jsonDecode(request.body), {
            'password': 'confirmed-password',
            'confirmation': 'DELETE',
          });
          deleted = true;
          return http.Response('', 204);
        }),
      );
      await controller.initialize();
      await controller.deleteServerAccount(
        'confirmed-password',
        server: controller.serverUri,
        userId: saved.user.id,
      );
      expect(deleted, isTrue);
      expect(controller.isAuthenticated, isFalse);
      expect(store.session, isNull);
      controller.dispose();
    },
  );

  test(
    'login persists the returned session without storing the password',
    () async {
      late Map<String, Object?> requestBody;
      final store = MemorySessionStore(deviceId: 'stable-device-id');
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/auth/login');
        requestBody = (jsonDecode(request.body) as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final device = (requestBody['device'] as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final session = testAuthSession().toJson();
        session['device'] = device;
        return http.Response(
          jsonEncode(session),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });
      final controller = _controller(store: store, client: client);
      await controller.initialize();

      final success = await controller.signIn(
        email: ' lin@example.com ',
        password: 'correct horse battery staple',
      );

      expect(success, isTrue);
      expect(controller.isAuthenticated, isTrue);
      expect(store.session?.user.email, 'lin@example.com');
      expect(requestBody['email'], 'lin@example.com');
      expect((requestBody['device'] as Map)['id'], store.session!.device.id);
      expect(
        jsonEncode(store.session!.toJson()),
        isNot(contains('correct horse')),
      );
      controller.dispose();
    },
  );

  test('invalid credentials produce a safe localized error', () async {
    final controller = _controller(
      store: MemorySessionStore(),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'invalid_credentials',
              'message': 'email or password is incorrect',
            },
          }),
          401,
        ),
      ),
    );
    await controller.initialize();

    final success = await controller.signIn(
      email: 'lin@example.com',
      password: 'wrong',
    );

    expect(success, isFalse);
    expect(controller.isAuthenticated, isFalse);
    expect(controller.formError, '邮箱或密码不正确。');
    controller.dispose();
  });

  test('a proxy rate limit produces an actionable login error', () async {
    final controller = _controller(
      store: MemorySessionStore(),
      client: MockClient(
        (_) async => http.Response('<html>limited</html>', 429),
      ),
    );
    await controller.initialize();

    final success = await controller.signIn(
      email: 'lin@example.com',
      password: 'correct horse battery staple',
    );

    expect(success, isFalse);
    expect(controller.formError, contains('过于频繁'));
    controller.dispose();
  });

  test('an expired access token is rotated during session restore', () async {
    final old = testAuthSession(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
      accessExpiresAt: DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      ),
    );
    final rotated = testAuthSession(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
    );
    final store = MemorySessionStore(session: old, deviceId: old.device.id);
    final controller = _controller(
      store: store,
      client: MockClient((request) async {
        expect(request.url.path, '/v1/auth/refresh');
        expect(jsonDecode(request.body), {'refresh_token': 'old-refresh'});
        return http.Response(
          jsonEncode(rotated.toJson()),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await controller.initialize();

    expect(controller.isAuthenticated, isTrue);
    expect(controller.connectionUnavailable, isFalse);
    expect(controller.session?.tokens.accessToken, 'new-access');
    expect(store.session?.tokens.refreshToken, 'new-refresh');
    controller.dispose();
  });

  test('a network failure restores a still-valid offline session', () async {
    final stored = testAuthSession(
      accessExpiresAt: DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      ),
    );
    final controller = _controller(
      store: MemorySessionStore(session: stored, deviceId: stored.device.id),
      client: MockClient((_) async => throw http.ClientException('offline')),
    );

    await controller.initialize();

    expect(controller.isAuthenticated, isTrue);
    expect(controller.connectionUnavailable, isTrue);
    expect(controller.notice, contains('离线'));
    controller.dispose();
  });

  test(
    'an expired refresh token is cleared without a network request',
    () async {
      final expired = testAuthSession(
        accessExpiresAt: DateTime.now().toUtc().subtract(
          const Duration(days: 2),
        ),
        refreshExpiresAt: DateTime.now().toUtc().subtract(
          const Duration(days: 1),
        ),
      );
      final store = MemorySessionStore(
        session: expired,
        deviceId: expired.device.id,
      );
      final controller = _controller(
        store: store,
        client: MockClient(
          (_) async => fail('expired sessions must not refresh'),
        ),
      );

      await controller.initialize();

      expect(controller.isAuthenticated, isFalse);
      expect(store.session, isNull);
      expect(controller.notice, contains('登录已过期'));
      controller.dispose();
    },
  );

  test('concurrent refresh requests share one token rotation', () async {
    final stored = testAuthSession();
    final rotated = testAuthSession(
      accessToken: 'rotated-access',
      refreshToken: 'rotated-refresh',
    );
    final response = Completer<http.Response>();
    var requestCount = 0;
    final controller = _controller(
      store: MemorySessionStore(session: stored, deviceId: stored.device.id),
      client: MockClient((_) {
        requestCount++;
        return response.future;
      }),
    );
    await controller.initialize();

    final first = controller.ensureFreshSession(force: true);
    final second = controller.ensureFreshSession(force: true);
    response.complete(
      http.Response(
        jsonEncode(rotated.toJson()),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(requestCount, 1);
    expect(controller.session?.tokens.refreshToken, 'rotated-refresh');
    controller.dispose();
  });

  test('logout waits for a refresh and revokes the rotated token', () async {
    final stored = testAuthSession();
    final rotated = testAuthSession(
      accessToken: 'rotated-access',
      refreshToken: 'rotated-refresh',
    );
    final refreshResponse = Completer<http.Response>();
    String? revokedToken;
    final controller = _controller(
      store: MemorySessionStore(session: stored, deviceId: stored.device.id),
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/refresh') {
          return refreshResponse.future;
        }
        if (request.url.path == '/v1/auth/logout') {
          revokedToken =
              (jsonDecode(request.body) as Map)['refresh_token'] as String;
          return http.Response('', 204);
        }
        return http.Response('', 404);
      }),
    );
    await controller.initialize();

    final refresh = controller.ensureFreshSession(force: true);
    final logout = controller.signOut();
    refreshResponse.complete(
      http.Response(
        jsonEncode(rotated.toJson()),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await refresh;
    await logout;

    expect(revokedToken, 'rotated-refresh');
    expect(controller.isAuthenticated, isFalse);
    controller.dispose();
  });

  test(
    'logout revokes the refresh token and clears only the session',
    () async {
      final stored = testAuthSession();
      final store = MemorySessionStore(
        session: stored,
        deviceId: stored.device.id,
      );
      var logoutCalled = false;
      final controller = _controller(
        store: store,
        client: MockClient((request) async {
          expect(request.url.path, '/v1/auth/logout');
          expect(jsonDecode(request.body), {
            'refresh_token': stored.tokens.refreshToken,
          });
          logoutCalled = true;
          return http.Response('', 204);
        }),
      );
      await controller.initialize();

      await controller.signOut();

      expect(logoutCalled, isTrue);
      expect(controller.isAuthenticated, isFalse);
      expect(store.session, isNull);
      expect(await store.readDeviceId(), stored.device.id);
      expect(controller.notice, contains('本机任务数据保留'));
      controller.dispose();
    },
  );
}

SessionController _controller({
  required MemorySessionStore store,
  required http.Client client,
}) {
  return SessionController(
    repository: AuthRepository(
      sessionStore: store,
      apiClient: ApiClient(baseUrl: 'https://api.example.test', client: client),
    ),
  );
}
