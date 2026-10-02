import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/session_controller.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/local/session_store.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/remote/api_client.dart';
import 'package:pactick/data/remote/server_address.dart';
import 'package:pactick/data/repositories/auth_repository.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('server addresses canonicalize and reject unsafe origins', () {
    expect(
      normalizeServerAddress(' HTTPS://EXAMPLE.COM:443/ '),
      'https://example.com',
    );
    expect(
      normalizeServerAddress('https://example.com:8443/'),
      'https://example.com:8443',
    );
    expect(normalizeServerAddress(''), '');
    for (final value in [
      'http://example.com',
      'https://user@example.com',
      'https://example.com/api',
      'https://example.com?q=1',
      'https://example.com#x',
      'file:///data',
    ]) {
      expect(() => normalizeServerAddress(value), throwsFormatException);
    }
    expect(
      normalizeServerAddress(
        'http://10.0.2.2:8080',
        allowDevelopmentHttp: true,
      ),
      'http://10.0.2.2:8080',
    );
    expect(
      () => normalizeServerAddress(
        'http://example.com',
        allowDevelopmentHttp: true,
      ),
      throwsFormatException,
    );
  });

  test('unconfigured client never makes an HTTP request', () async {
    final api = ApiClient(
      baseUrl: '',
      client: MockClient((_) async => fail('unexpected request')),
    );
    final session = SessionController(
      repository: AuthRepository(
        sessionStore: MemorySessionStore(),
        apiClient: api,
      ),
    );
    await session.initialize();
    expect(session.isAuthenticated, isFalse);
    expect(session.hasServer, isFalse);
    await expectLater(api.get('/v1/sync/pull'), throwsA(isA<ApiException>()));
    session.dispose();
  });

  test(
    'secure credentials and devices are isolated by server and account',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureSessionStore();
      final original = testAuthSession();
      await store.selectServer('https://one.example.test');
      await store.writeSession(original);
      await store.selectServer('https://two.example.test');
      expect(await store.readSession(), isNull);
      expect(await store.readDeviceId(), isNull);
      await store.writeSession(
        testAuthSession(accessToken: 'second-server-token'),
      );
      await store.selectServer('https://one.example.test');
      expect(
        (await store.readSession())!.tokens.accessToken,
        original.tokens.accessToken,
      );
      await store.selectIdentity('another-user');
      expect(await store.readSession(), isNull);
      expect(await store.readDeviceId(), isNull);
    },
  );

  test(
    'switching server waits for old refresh and synchronization barrier',
    () async {
      final refreshResponse = Completer<http.Response>();
      final barrier = Completer<void>();
      final requests = <http.Request>[];
      final saved = testAuthSession();
      final api = ApiClient(
        baseUrl: 'https://one.example.test',
        client: MockClient((request) {
          requests.add(request);
          return refreshResponse.future;
        }),
      );
      final session = SessionController(
        repository: AuthRepository(
          apiClient: api,
          sessionStore: MemorySessionStore(
            session: saved,
            deviceId: saved.device.id,
          ),
        ),
        beforeSessionChange: () => barrier.future,
      );
      await session.initialize();
      final refreshing = session.ensureFreshSession(force: true);
      final switching = session.configureServer('https://two.example.test');
      refreshResponse.complete(
        http.Response(
          jsonEncode(testAuthSession(accessToken: 'rotated').toJson()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await refreshing;
      expect(api.baseUri.host, 'one.example.test');
      barrier.complete();
      await switching;
      expect(api.baseUri.host, 'two.example.test');
      expect(api.accessToken, isNull);
      expect(session.isAuthenticated, isFalse);
      expect(requests.single.url.host, 'one.example.test');
      expect(requests.single.headers['authorization'], isNull);
      session.dispose();
    },
  );

  test(
    'identical user IDs on two servers never claim local or each other data',
    () async {
      final repository = WorkspaceRepository(MemoryDocumentStore());
      final app = AppController(
        repository: repository,
        focusPlatform: const FocusPlatformGateway(),
      );
      await app.initialize();
      final local = await app.createTask(title: 'stay on device');
      final one = serverWorkspaceId(
        Uri.parse('https://one.example.test'),
        'same-user',
      );
      final two = serverWorkspaceId(
        Uri.parse('https://two.example.test'),
        'same-user',
      );
      await app.connectSyncAccount(
        userId: one,
        deviceId: 'device-one',
        offline: true,
      );
      expect(app.tasks, isEmpty);
      await app.createTask(title: 'server one');
      await app.connectSyncAccount(
        userId: two,
        deviceId: 'device-two',
        offline: true,
      );
      expect(app.tasks, isEmpty);
      expect(await repository.store.readSyncCursor(two), 0);
      await app.openOfflineWorkspace(one);
      expect(app.tasks.single.title, 'server one');
      await app.openOfflineWorkspace(DocumentStore.localAccountId);
      expect(app.tasks.single.id, local.id);
      app.dispose();
    },
  );

  test(
    'sign out keeps the selected workspace editable through restart',
    () async {
      final store = MemoryDocumentStore();
      final app = AppController(
        repository: WorkspaceRepository(store),
        focusPlatform: const FocusPlatformGateway(),
      );
      await app.initialize();
      final id = serverWorkspaceId(
        Uri.parse('https://one.example.test'),
        'account',
      );
      await app.connectSyncAccount(
        userId: id,
        deviceId: 'device',
        offline: true,
      );
      final task = await app.createTask(title: 'retained');
      await app.disconnectSyncAccount();
      expect(app.tasks.single.id, task.id);
      await app.toggleTask(task);
      expect(app.tasks.single.isCompleted, isTrue);
      final restored = AppController(
        repository: WorkspaceRepository(store),
        focusPlatform: const FocusPlatformGateway(),
      );
      await restored.initialize();
      expect(restored.tasks.single.id, task.id);
      expect(restored.tasks.single.isCompleted, isTrue);
      expect(restored.canSync, isFalse);
      app.dispose();
      restored.dispose();
    },
  );

  test(
    'protocol failure pauses background sync without blocking local edits',
    () async {
      var requests = 0;
      final api = ApiClient(
        baseUrl: 'https://one.example.test',
        client: MockClient((_) async {
          requests++;
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'client_update_required',
                'message': 'upgrade sync',
              },
            }),
            426,
          );
        }),
      );
      final app = AppController(
        repository: WorkspaceRepository(MemoryDocumentStore()),
        focusPlatform: const FocusPlatformGateway(),
        apiClient: api,
      );
      await app.initialize();
      await app.connectSyncAccount(
        userId: 'isolated-account',
        deviceId: 'device',
        offline: true,
      );
      await app.syncNow();
      final afterFailure = requests;
      await app.createTask(title: 'offline still works');
      await app.syncNow(automatic: true);
      expect(requests, afterFailure);
      expect(app.tasks.single.title, 'offline still works');
      await app.syncNow();
      expect(requests, greaterThan(afterFailure));
      app.dispose();
      api.close();
    },
  );
}
