import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app/pactick_app.dart';
import 'core/licenses/supplemental_licenses.dart';
import 'core/state/app_controller.dart';
import 'core/state/app_scope.dart';
import 'core/state/session_controller.dart';
import 'core/state/session_scope.dart';
import 'data/local/local_database.dart';
import 'data/local/session_store.dart';
import 'data/platform/focus_platform_gateway.dart';
import 'data/remote/api_client.dart';
import 'data/remote/server_address.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/workspace_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerSupplementalLicenses();
  var appVersion = '0.1.0';
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
  } catch (_) {
    /* Local use does not require package metadata. */
  }
  final workspace = WorkspaceRepository(LocalDatabase());
  final apiClient = ApiClient(baseUrl: '');
  final controller = AppController(
    repository: workspace,
    focusPlatform: const FocusPlatformGateway(),
    apiClient: apiClient,
  );
  late final SessionController sessionController;
  sessionController = SessionController(
    repository: AuthRepository(
      sessionStore: SecureSessionStore(),
      apiClient: apiClient,
      appVersion: appVersion,
    ),
    beforeSessionChange: controller.disconnectSyncAccount,
    onAuthenticationChanged: (authenticated, connectionUnavailable) async {
      final session = sessionController.session;
      if (authenticated && session != null) {
        await workspace.writeGlobalSetting('sync_enabled_v2', 'true');
        final uploadSource = sessionController.uploadSourceWorkspace;
        sessionController.uploadSourceWorkspace = null;
        await controller.connectSyncAccount(
          userId: serverWorkspaceId(apiClient.baseUri, session.user.id),
          deviceId: session.device.id,
          offline: connectionUnavailable,
          uploadSourceWorkspace: uploadSource,
        );
      } else {
        await controller.disconnectSyncAccount();
        await workspace.writeGlobalSetting('sync_enabled_v2', 'false');
      }
    },
  );
  runApp(
    AppScope(
      controller: controller,
      child: SessionScope(
        controller: sessionController,
        child: const PactickApp(),
      ),
    ),
  );
  unawaited(_initialize(controller, sessionController));
}

Future<void> _initialize(
  AppController controller,
  SessionController sessionController,
) async {
  await controller.initialize();
  if (controller.initializationError == null) {
    try {
      final savedServer = await controller.repository.readGlobalSetting(
        'sync_server_v2',
      );
      sessionController.repository.apiClient.configureServer(
        savedServer ?? const String.fromEnvironment('API_BASE_URL'),
      );
      if (await controller.repository.readGlobalSetting('sync_enabled_v2') ==
          'false') {
        await sessionController.initialize(restore: false);
        return;
      }
    } catch (_) {
      sessionController.notice = '无法读取同步配置。你仍可使用本地工作区，并在设置中重新配置服务器。';
    }
  }
  await sessionController.initialize();
}
