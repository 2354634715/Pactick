import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pactick/core/models/domain_models.dart';
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
  _testWithHarness(
    'token refresh resumes queued uploads and periodic downloads',
    (tester, harness) async {
      final task = await harness.app.createTask(title: 'saved while offline');
      harness.server.syncFailure = (_) async => _expiredAccess();
      await harness.app.syncNow();
      expect(harness.app.syncPhase, SyncPhase.attention);
      expect(harness.app.pendingOperations, 1);
      final afterFailure = harness.server.syncRequests;
      await harness.app.syncNow(automatic: true);
      expect(harness.server.syncRequests, afterFailure);

      harness.server.syncFailure = (request) async =>
          request.headers['authorization'] == 'Bearer test-access-token'
          ? _expiredAccess()
          : null;
      expect(await harness.session.ensureFreshSession(force: true), isTrue);
      await tester.pump();

      expect(harness.server.taskBody(task.id)['title'], 'saved while offline');
      expect(harness.server.pushTokens.last, 'Bearer rotated-access-token');
      expect(harness.app.pendingOperations, 0);
      expect(harness.app.syncPhase, SyncPhase.synced);
      expect(harness.app.syncErrorMessage, isNull);

      harness.server.editTask(task.id, {'title': 'edited on another device'});
      await tester.pump(const Duration(minutes: 1));
      expect(harness.app.tasks.single.title, 'edited on another device');
    },
  );

  _testWithHarness('refresh waits for an old request that returns a late 401', (
    tester,
    harness,
  ) async {
    final task = await harness.app.createTask(title: 'preserve this upload');
    final oldResponse = Completer<http.Response>();
    harness.server.syncFailure = (request) async =>
        request.headers['authorization'] == 'Bearer test-access-token'
        ? oldResponse.future
        : null;
    final syncing = harness.app.syncNow();
    await tester.pump();
    var rebound = false;
    final refreshing = harness.session.ensureFreshSession(force: true).then((
      value,
    ) {
      rebound = true;
      return value;
    });
    await tester.pump();
    expect(harness.api.accessToken, 'rotated-access-token');
    expect(rebound, isFalse);
    expect(harness.server.taskExists(task.id), isFalse);

    oldResponse.complete(_expiredAccess());
    await syncing;
    expect(await refreshing, isTrue);
    await tester.pump();
    expect(harness.server.taskBody(task.id)['title'], 'preserve this upload');
    expect(harness.app.pendingOperations, 0);
    expect(harness.app.syncPhase, SyncPhase.synced);
  });

  _testWithHarness(
    'manual retry restarts a timer cancelled by authentication',
    (tester, harness) async {
      final task = await harness.app.createTask(title: 'manual recovery');
      harness.server.syncFailure = (_) async => _expiredAccess();
      await harness.app.syncNow();
      harness.server.syncFailure = null;
      await harness.app.syncNow();
      expect(harness.app.pendingOperations, 0);

      // There is no local edit or lifecycle event to trigger this download.
      harness.server.editTask(task.id, {'title': 'periodic download resumed'});
      await tester.pump(const Duration(minutes: 1));
      expect(harness.app.tasks.single.title, 'periodic download resumed');
    },
  );

  for (final failure in <({String name, http.Response Function() response})>[
    (name: 'HTTP 426', response: () => _error(426, 'client_update_required')),
    (
      name: 'unsupported_protocol with HTTP 401',
      response: () => _error(401, 'unsupported_protocol'),
    ),
    (
      name: 'client_update_required with HTTP 401',
      response: () => _error(401, 'client_update_required'),
    ),
    (
      name: 'malformed HTTP 401 response',
      response: () => http.Response('<html>invalid response</html>', 401),
    ),
    (
      name: 'invalid sync response structure',
      response: () => _json({'results': 'invalid', 'current_cursor': 0}),
    ),
  ]) {
    _testWithHarness(
      '${failure.name} stays paused after a successful refresh',
      (tester, harness) async {
        await harness.app.createTask(title: 'local edit survives');
        harness.server.syncFailure = (_) async => failure.response();
        await harness.app.syncNow();
        expect(harness.app.syncPhase, SyncPhase.attention);
        final afterFailure = harness.server.syncRequests;
        harness.server.syncFailure = null;

        expect(await harness.session.ensureFreshSession(force: true), isTrue);
        await harness.app.syncNow(automatic: true);
        await tester.pump(const Duration(minutes: 1));
        expect(harness.server.syncRequests, afterFailure);
        expect(harness.app.tasks.single.title, 'local edit survives');
        expect(harness.app.pendingOperations, 1);
        expect(harness.app.syncPhase, SyncPhase.attention);

        await harness.app.syncNow();
        expect(harness.app.pendingOperations, 0);
        expect(harness.app.syncPhase, SyncPhase.synced);
      },
    );
  }

  _testWithHarness(
    'failed refresh keeps authentication sync paused until recovery',
    (tester, harness) async {
      final task = await harness.app.createTask(title: 'do not discard');
      harness.server.syncFailure = (_) async => _expiredAccess();
      await harness.app.syncNow();
      harness.server.refreshOverride = (_) async =>
          throw http.ClientException('network unavailable');
      expect(await harness.session.ensureFreshSession(force: true), isFalse);
      expect(harness.session.isAuthenticated, isTrue);
      expect(harness.app.syncPhase, SyncPhase.offline);
      final afterFailure = harness.server.syncRequests;
      await harness.app.syncNow(automatic: true);
      await tester.pump(const Duration(seconds: 30));
      expect(harness.server.syncRequests, afterFailure);
      expect(harness.app.pendingOperations, 1);

      harness.server.refreshOverride = null;
      harness.server.syncFailure = null;
      expect(await harness.session.ensureFreshSession(force: true), isTrue);
      await tester.pump();
      expect(harness.server.taskBody(task.id)['title'], 'do not discard');
      expect(harness.app.pendingOperations, 0);
    },
  );

  _testWithHarness(
    'revoked refresh disconnects and preserves the queued local edit',
    (tester, harness) async {
      final task = await harness.app.createTask(
        title: 'retained after revocation',
      );
      harness.server.syncFailure = (_) async => _expiredAccess();
      await harness.app.syncNow();
      harness.server.refreshOverride = (_) async =>
          _error(401, 'invalid_token');
      expect(await harness.session.ensureFreshSession(force: true), isFalse);
      expect(harness.session.isAuthenticated, isFalse);
      expect(harness.app.canSync, isFalse);
      expect(harness.app.tasks.single.id, task.id);
      expect(
        await harness.app.repository.store.pendingOperationCount(
          accountId: harness.accountId,
        ),
        1,
      );
      final afterDisconnect = harness.server.syncRequests;
      await harness.app.syncNow();
      await tester.pump(const Duration(minutes: 1));
      expect(harness.server.syncRequests, afterDisconnect);
    },
  );

  _testWithHarness(
    'disconnect during rebind prevents the old identity from resuming',
    (tester, harness) async {
      await harness.app.createTask(title: 'keep the old workspace');
      final oldResponse = Completer<http.Response>();
      harness.server.syncFailure = (_) => oldResponse.future;
      final syncing = harness.app.syncNow();
      await tester.pump();
      final rebinding = harness.app.connectSyncAccount(
        userId: harness.accountId,
        deviceId: 'device-id',
      );
      final disconnecting = harness.app.disconnectSyncAccount();
      final afterDisconnect = harness.server.syncRequests;
      oldResponse.complete(_expiredAccess());
      await Future.wait([syncing, rebinding, disconnecting]);
      await tester.pump(const Duration(minutes: 1));
      expect(harness.app.canSync, isFalse);
      expect(harness.server.syncRequests, afterDisconnect);
      expect(harness.app.tasks.single.title, 'keep the old workspace');
    },
  );
}

void _testWithHarness(
  String description,
  Future<void> Function(WidgetTester tester, _Harness harness) body,
) {
  testWidgets(description, (tester) async {
    final harness = await _Harness.create(tester);
    try {
      await body(tester, harness);
    } finally {
      harness.dispose();
    }
  });
}

class _Harness {
  _Harness(this.server, this.api, this.app, this.session, this.accountId);

  final _SyncServer server;
  final ApiClient api;
  final AppController app;
  final SessionController session;
  final String accountId;

  static Future<_Harness> create(WidgetTester tester) async {
    final server = _SyncServer();
    final api = ApiClient(
      baseUrl: 'https://sync.example.test',
      client: MockClient(server.handle),
    );
    final app = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
      apiClient: api,
    );
    final saved = testAuthSession();
    late final SessionController session;
    session = SessionController(
      repository: AuthRepository(
        apiClient: api,
        sessionStore: MemorySessionStore(
          session: saved,
          deviceId: saved.device.id,
        ),
      ),
      beforeSessionChange: app.disconnectSyncAccount,
      onAuthenticationChanged: (authenticated, offline) async {
        final current = session.session;
        if (authenticated && current != null) {
          await app.connectSyncAccount(
            userId: serverWorkspaceId(api.baseUri, current.user.id),
            deviceId: current.device.id,
            offline: offline,
          );
        } else {
          await app.disconnectSyncAccount();
        }
      },
    );
    final harness = _Harness(
      server,
      api,
      app,
      session,
      serverWorkspaceId(api.baseUri, saved.user.id),
    );
    try {
      await app.initialize();
      await session.initialize();
      await tester.pump();
      expect(app.syncPhase, SyncPhase.synced);
      return harness;
    } catch (_) {
      harness.dispose();
      rethrow;
    }
  }

  void dispose() {
    session.dispose();
    app.dispose();
    api.close();
  }
}

// The server accepts uploads only after the injected transport/authentication
// failure has cleared, then returns actual snapshots and append-only changes.
class _SyncServer {
  Future<http.Response?> Function(http.Request)? syncFailure;
  Future<http.Response> Function(http.Request)? refreshOverride;
  final List<String?> pushTokens = [];
  final Map<String, Map<String, Object?>> _entities = {};
  final List<Map<String, Object?>> _changes = [];
  int syncRequests = 0;
  int _cursor = 0;

  bool taskExists(String id) => _entities.containsKey('task:$id');

  Map<String, Object?> taskBody(String id) =>
      Map<String, Object?>.from(_entities['task:$id']!['body']! as Map);

  void editTask(String id, Map<String, Object?> patch) {
    _write('task', id, {...taskBody(id), ...patch});
  }

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/v1/auth/refresh') {
      if (refreshOverride != null) return refreshOverride!(request);
      return _json(
        testAuthSession(
          accessToken: 'rotated-access-token',
          refreshToken: 'rotated-refresh-token',
        ).toJson(),
      );
    }
    if (request.url.path == '/v1/devices') {
      return _json({'devices': <Object?>[]});
    }
    if (!request.url.path.startsWith('/v1/sync/')) {
      throw StateError('Unexpected test request: ${request.url.path}');
    }
    syncRequests++;
    if (request.url.path == '/v1/sync/push') {
      pushTokens.add(request.headers['authorization']);
    }
    final failure = await syncFailure?.call(request);
    if (failure != null) return failure;
    if (request.url.path == '/v1/sync/push') {
      final body = jsonDecode(request.body) as Map;
      final results = <Map<String, Object?>>[];
      for (final value in body['operations'] as List) {
        final operation = Map<String, Object?>.from(value as Map);
        final type = operation['entity_type']! as String;
        final id = operation['entity_id']! as String;
        final previous = _entities['$type:$id'];
        final snapshot = _write(type, id, {
          if (previous != null)
            ...Map<String, Object?>.from(previous['body']! as Map),
          ...Map<String, Object?>.from(operation['patch']! as Map),
        });
        results.add({
          'operation_id': operation['operation_id'],
          'status': 'applied',
          'snapshot': snapshot,
        });
      }
      return _json({'results': results, 'current_cursor': _cursor});
    }
    if (request.url.path != '/v1/sync/pull') {
      throw StateError('Unexpected sync request: ${request.url.path}');
    }
    final cursor = int.parse(request.url.queryParameters['cursor']!);
    final changes = _changes
        .where((change) => (change['cursor']! as int) > cursor)
        .toList();
    return _json({
      'changes': changes,
      'next_cursor': changes.isEmpty ? cursor : changes.last['cursor'],
      'current_cursor': _cursor,
      'has_more': false,
    });
  }

  Map<String, Object?> _write(
    String type,
    String id,
    Map<String, Object?> body,
  ) {
    final version = ((_entities['$type:$id']?['version'] as int?) ?? 0) + 1;
    final timestamp = DateTime.utc(
      2026,
      10,
      3,
    ).add(Duration(seconds: ++_cursor)).toIso8601String();
    final snapshot = <String, Object?>{
      'entity_type': type,
      'entity_id': id,
      'version': version,
      'body': body,
      'deleted': false,
      'updated_at': timestamp,
      'cursor': _cursor,
    };
    _entities['$type:$id'] = snapshot;
    _changes.add({
      'cursor': _cursor,
      'change_id': 'change-$_cursor',
      'entity_type': type,
      'entity_id': id,
      'action': 'upsert',
      'version': version,
      'body': body,
      'changed_fields': body.keys.toList(),
      'device_id': 'device-id',
      'changed_at': timestamp,
    });
    return snapshot;
  }
}

http.Response _expiredAccess() => _error(401, 'invalid_token');

http.Response _error(int status, String code) => _json({
  'error': {'code': code, 'message': code},
}, status: status);

http.Response _json(Map<String, Object?> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
