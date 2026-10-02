import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pactick/app/pactick_app.dart';
import 'package:pactick/core/models/update_models.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/core/state/session_controller.dart';
import 'package:pactick/core/state/session_scope.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/local/session_store.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/remote/api_client.dart';
import 'package:pactick/data/repositories/auth_repository.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/data/update/client_update_service.dart';

import 'support/session_test_support.dart';

import 'package:pactick/features/auth/pages/login_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a successful login opens the local workspace', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    final appController = AppController(
      repository: WorkspaceRepository(MemoryDocumentStore()),
      focusPlatform: const FocusPlatformGateway(),
    );
    await appController.initialize();
    final sessionStore = MemorySessionStore(deviceId: 'widget-device-id');
    final sessionController = SessionController(
      repository: AuthRepository(
        sessionStore: sessionStore,
        apiClient: ApiClient(
          baseUrl: 'https://api.example.test',
          client: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final response = testAuthSession().toJson();
            response['device'] = body['device'];
            return http.Response(
              jsonEncode(response),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }),
        ),
      ),
      onAuthenticationChanged: (authenticated, offline) {
        if (authenticated) {
          appController.connectSyncAccount(offline: offline);
        } else {
          appController.disconnectSyncAccount();
        }
      },
    );
    await sessionController.initialize();

    await tester.pumpWidget(
      AppScope(
        controller: appController,
        child: SessionScope(
          controller: sessionController,
          child: const PactickApp(automaticallyCheckForUpdates: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(sessionController.isAuthenticated, isFalse);
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => const LoginPage()));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('login_email')),
      'lin@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login_password')),
      'correct horse battery staple',
    );
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('今日安排'), findsOneWidget);
    expect(sessionStore.session?.user.email, 'lin@example.com');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    appController.dispose();
    sessionController.dispose();
  });

  testWidgets(
    'required server updates cannot gate local use or trigger requests',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);

      final appController = AppController(
        repository: WorkspaceRepository(MemoryDocumentStore()),
        focusPlatform: const FocusPlatformGateway(),
      );
      await appController.initialize();
      final sessionController = SessionController(
        repository: AuthRepository(
          sessionStore: MemorySessionStore(),
          apiClient: ApiClient(
            baseUrl: 'https://api.example.test',
            client: MockClient((_) async => http.Response('{}', 500)),
          ),
        ),
      );
      await sessionController.initialize();

      final opened = <Uri>[];
      var updateRequests = 0;
      final updateApi = ApiClient(
        baseUrl: 'https://api.example.test',
        client: MockClient((_) async {
          updateRequests++;
          return http.Response(
            jsonEncode({
              'status': 'update_available',
              'update_available': true,
              'required': true,
              'version': '1.0.0',
              'build_number': 100,
              'download_url': 'https://downloads.example.test/app.apk',
              'sha256': 'a' * 64,
              'size_bytes': 7340032,
              'release_notes': '安全与协议更新',
              'published_at': '2026-09-19T04:30:00Z',
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final updateService = ClientUpdateService(
        apiClient: updateApi,
        installedVersionLoader: () async => const InstalledClientVersion(
          appName: 'Pactick',
          version: '0.1.0',
          buildNumber: 2,
        ),
        externalUrlLauncher: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      await tester.pumpWidget(
        AppScope(
          controller: appController,
          child: SessionScope(
            controller: sessionController,
            child: PactickApp(clientUpdateService: updateService),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(updateRequests, 0);
      expect(opened, isEmpty);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('需要更新后继续使用'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      appController.dispose();
      sessionController.dispose();
      updateApi.close();
    },
  );
}
