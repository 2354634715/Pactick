import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/private_vault_controller.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/local/private_vault_crypto.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'free focus opens the desktop with generic title and inbox allowlist',
    () async {
      final platform = _DesktopPlatform();
      final app = _app(MemoryDocumentStore(), platform);
      addTearDown(app.dispose);
      await app.initialize();
      await app.setFocusDesktopEnabled(true);
      await app.setAppWhitelist(null, {'com.example.reader'});
      await app.startFocus(
        durationSeconds: 900,
        policy: app.focusPolicies.first,
      );
      expect(app.tasks, isEmpty);
      expect(app.activeFocusSession!.taskId, isNull);
      expect(platform.nativeTitle, '自由专注');
      expect(platform.nativeTitleKey, 'free_focus');
      expect(platform.desktopEnabled, isTrue);
      expect(platform.opens, 1);
      expect(platform.openedPackages, ['com.example.reader']);
    },
  );

  test('free and private focus remain mutually exclusive', () async {
    final store = MemoryDocumentStore();
    final platform = _DesktopPlatform();
    final app = _app(store, platform);
    addTearDown(app.dispose);
    await app.initialize();
    await app.privateVault.configure(
      'free-focus-vault-password',
      'free-focus-vault-password',
    );
    const task = TaskItem(
      id: '11111111-1111-4111-8111-111111111111',
      title: 'Private title must stay in the vault',
      priority: TaskPriority.none,
      status: TaskStatus.open,
      rank: 0,
    );
    await app.privateVault.saveTask(task);
    await app.startFocus(durationSeconds: 900, policy: app.focusPolicies.first);
    await expectLater(
      app.privateVault.startFocus(task.id, 25),
      throwsA(isA<PrivateVaultException>()),
    );
    expect(app.privateVault.hasActiveFocus, isFalse);
    await app.finishFocus();
    await expectLater(
      app.associateFocusSessionTask(
        sessionId: app.focusSessions.single.id,
        task: task,
      ),
      throwsStateError,
    );
    expect(app.focusSessions.single.taskId, isNull);
    await app.privateVault.startFocus(task.id, 25);
    expect(app.canStartFocus, isFalse);
    await app.startFocus(durationSeconds: 900, policy: app.focusPolicies.first);
    expect(app.activeFocusSession, isNull);
    expect(app.privateVault.hasActiveFocus, isTrue);
    expect(platform.nativeTitleKey, 'private_task');
    final ordinarySessions = await store.readDocuments('focus_session');
    expect(ordinarySessions, hasLength(1));
    expect(ordinarySessions.single.body['task_id'], isNull);
    expect(await store.readDocuments('task'), isEmpty);
    await app.privateVault.stopFocus();
    expect(app.canStartFocus, isTrue);
  });

  test(
    'desktop is opt-in and starting focus preserves the default behavior',
    () async {
      final platform = _DesktopPlatform();
      final app = _app(MemoryDocumentStore(), platform);
      addTearDown(app.dispose);
      await app.initialize();
      expect(app.focusDesktopEnabled, isFalse);
      await _start(app);
      expect(platform.desktopEnabled, isFalse);
      expect(platform.opens, 0);
      expect(app.activeFocusSession, isNotNull);
    },
  );

  test(
    'opt-in opens with the current project allowlist and policy packages',
    () async {
      final platform = _DesktopPlatform();
      final app = _app(MemoryDocumentStore(), platform);
      addTearDown(app.dispose);
      await app.initialize();
      await app.setAppWhitelist(null, {'com.example.reader'});
      await app.setFocusDesktopEnabled(true);
      expect(platform.opens, 0);
      await _start(app);
      expect(platform.desktopEnabled, isTrue);
      expect(platform.opens, 1);
      expect(platform.openedPackages, contains('com.example.reader'));
      expect(app.focusDesktopErrorMessage, isNull);
    },
  );

  test(
    'resume opens the desktop; foreground reconciliation does not',
    () async {
      final platform = _DesktopPlatform();
      final app = _app(MemoryDocumentStore(), platform);
      addTearDown(app.dispose);
      await app.initialize();
      await app.setFocusDesktopEnabled(true);
      await _start(app);
      await app.reconcileNativeFocus();
      expect(platform.opens, 1);
      await app.pauseFocus();
      expect(platform.opens, 1);
      await app.resumeFocus();
      expect(platform.opens, 2);
    },
  );

  test(
    'the device preference persists without opening a restored session',
    () async {
      final store = MemoryDocumentStore();
      final app = _app(store, _DesktopPlatform());
      await app.initialize();
      await app.setFocusDesktopEnabled(true);
      await _start(app);
      app.dispose();
      final platform = _DesktopPlatform();
      final restored = _app(store, platform);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.focusDesktopEnabled, isTrue);
      expect(restored.activeFocusSession, isNotNull);
      expect(platform.desktopEnabled, isTrue);
      expect(platform.opens, 0);
    },
  );

  test('disabling updates Android immediately without ending focus', () async {
    final platform = _DesktopPlatform();
    final app = _app(MemoryDocumentStore(), platform);
    addTearDown(app.dispose);
    await app.initialize();
    await app.setFocusDesktopEnabled(true);
    await _start(app);
    await app.setFocusDesktopEnabled(false);
    expect(platform.configuredEnabled, isFalse);
    expect(platform.desktopEnabled, isFalse);
    expect(app.activeFocusSession, isNotNull);
    await app.openFocusDesktop();
    expect(platform.opens, 1);
  });

  test('launch failure keeps committed focus and can be retried', () async {
    final platform = _DesktopPlatform()..failOpen = true;
    final store = MemoryDocumentStore();
    final app = _app(store, platform);
    addTearDown(app.dispose);
    await app.initialize();
    await app.setFocusDesktopEnabled(true);
    await _start(app);
    final id = app.activeFocusSession!.id;
    expect(app.focusDesktopErrorMessage, isNotNull);
    expect((await store.readDocuments('focus_session')).single.id, id);
    platform.failOpen = false;
    await app.openFocusDesktop();
    expect(app.focusDesktopErrorMessage, isNull);
    expect(app.activeFocusSession!.id, id);
    expect(platform.opens, 2);
  });

  test('false platform result reports a retryable failure', () async {
    final platform = _DesktopPlatform()..openResult = false;
    final app = _app(MemoryDocumentStore(), platform);
    addTearDown(app.dispose);
    await app.initialize();
    await app.setFocusDesktopEnabled(true);
    await _start(app);
    expect(app.focusDesktopErrorMessage, isNotNull);
    expect(app.activeFocusSession, isNotNull);
  });

  test(
    'a failed setting write leaves the previous preference and native state',
    () async {
      final platform = _DesktopPlatform();
      final store = _FailingSettingsStore();
      final app = _app(store, platform);
      addTearDown(app.dispose);
      await app.initialize();
      store.failDesktopWrite = true;
      await expectLater(app.setFocusDesktopEnabled(true), throwsStateError);
      expect(app.focusDesktopEnabled, isFalse);
      expect(platform.configuredEnabled, isNull);
    },
  );

  test(
    'configuration failure preserves saved choice and offers retry',
    () async {
      final platform = _DesktopPlatform()..failConfigure = true;
      final app = _app(MemoryDocumentStore(), platform);
      addTearDown(app.dispose);
      await app.initialize();
      await app.setFocusDesktopEnabled(true);
      expect(app.focusDesktopEnabled, isTrue);
      expect(app.focusDesktopErrorMessage, isNotNull);
      platform.failConfigure = false;
      await app.setFocusDesktopEnabled(true);
      expect(app.focusDesktopErrorMessage, isNull);
    },
  );

  test('unsupported platforms and idle state cannot open a desktop', () async {
    final platform = _DesktopPlatform()..supported = false;
    final app = _app(MemoryDocumentStore(), platform);
    addTearDown(app.dispose);
    await app.initialize();
    await app.setFocusDesktopEnabled(true);
    await app.openFocusDesktop();
    await _start(app);
    expect(app.focusDesktopSupported, isFalse);
    expect(platform.opens, 0);
  });

  test(
    'allowlist edits refresh the active native snapshot without navigation',
    () async {
      final platform = _DesktopPlatform();
      final app = _app(MemoryDocumentStore(), platform);
      addTearDown(app.dispose);
      await app.initialize();
      await app.setFocusDesktopEnabled(true);
      await _start(app);
      await app.setAppWhitelist(null, {'com.example.dictionary'});
      expect(platform.sessionPackages, contains('com.example.dictionary'));
      expect(platform.opens, 1);
      await app.finishFocus();
      await app.openFocusDesktop();
      expect(platform.opens, 1);
    },
  );

  test(
    'a private session keeps its owning workspace allowlist after switching',
    () async {
      final store = MemoryDocumentStore();
      await store.ensureAccount('other-workspace');
      await store.writeSetting(
        'selected_workspace_v2',
        DocumentStore.localAccountId,
      );
      await store.writeSetting('focus_desktop_enabled', 'true');
      await store.writeSetting(
        'focus_app_whitelists_v1',
        jsonEncode({
          AppController.inboxWhitelistKey: ['com.example.reader'],
        }),
      );
      await store.writeSetting(
        'focus_app_whitelists_v1',
        jsonEncode({
          AppController.inboxWhitelistKey: ['com.example.game'],
        }),
        accountId: 'other-workspace',
      );
      final now = DateTime.now().toUtc();
      final envelope = await const PrivateVaultCrypto().encrypt(
        'locked fixture: no decrypted task content is needed for restoration',
        key: SecretKeyData(List<int>.filled(32, 7)),
        salt: List<int>.filled(32, 3),
        runtime: {
          'session_id': 'private-workspace-focus',
          'started_at': now.toIso8601String(),
          'ends_at': now.add(const Duration(minutes: 25)).toIso8601String(),
        },
      );
      await store.writePrivateVault(
        DocumentStore.localAccountId,
        envelope.encode(),
        expectedEnvelope: null,
        ownsFocusRuntime: true,
      );
      final platform = _DesktopPlatform();
      final app = _app(store, platform);
      addTearDown(app.dispose);
      await app.initialize();
      expect(platform.sessionPackages, ['com.example.reader']);
      await app.openOfflineWorkspace('other-workspace');
      expect(app.appWhitelistForProject(null), {'com.example.game'});
      expect(platform.sessionPackages, ['com.example.reader']);
      await app.openFocusDesktop();
      expect(platform.openedPackages, ['com.example.reader']);
      expect(app.privateVault.isUnlocked, isFalse);
      expect(platform.opens, 1);
    },
  );

  test(
    'new private focus opens once and sends only generic native titles',
    () async {
      final platform = _DesktopPlatform();
      final app = _app(MemoryDocumentStore(), platform);
      addTearDown(app.dispose);
      await app.initialize();
      await app.setFocusDesktopEnabled(true);
      await app.setAppWhitelist(null, {'com.example.reader'});
      await app.privateVault.configure(
        'desktop-test-password',
        'desktop-test-password',
      );
      const task = TaskItem(
        id: '11111111-1111-4111-8111-111111111111',
        title: 'Never send this private title to Android',
        priority: TaskPriority.none,
        status: TaskStatus.open,
        rank: 0,
      );
      await app.privateVault.saveTask(task);
      await app.privateVault.startFocus(task.id, 25);
      expect(platform.opens, 1);
      expect(platform.nativeTitle, isNot(contains('Never send')));
      expect(platform.nativeTitleKey, 'private_task');
      expect(platform.openedPackages, ['com.example.reader']);
      await app.reconcileNativeFocus();
      expect(platform.opens, 1);
    },
  );
}

AppController _app(DocumentStore store, FocusPlatformGateway platform) =>
    AppController(
      repository: WorkspaceRepository(store),
      focusPlatform: platform,
    );

Future<void> _start(AppController app) async {
  final task = await app.createTask(title: 'Read 用户原文');
  await app.startFocus(
    task: task,
    durationSeconds: 900,
    policy: app.focusPolicies.firstWhere(
      (p) => p.mode == FocusPolicyMode.normal,
    ),
  );
}

class _DesktopPlatform extends FocusPlatformGateway {
  bool supported = true;
  bool desktopEnabled = false;
  bool? configuredEnabled;
  bool failOpen = false;
  bool failConfigure = false;
  bool openResult = true;
  int opens = 0;
  List<String> openedPackages = [];
  List<String> sessionPackages = [];
  String? nativeTitle;
  String? nativeTitleKey;
  FocusTimerState state = const FocusTimerState();

  @override
  bool get supportsFocusDesktop => supported;

  @override
  Future<void> configureFocusDesktop({required bool enabled}) async {
    if (failConfigure) throw StateError('configuration failed');
    configuredEnabled = enabled;
    desktopEnabled = enabled;
  }

  @override
  Future<bool> openFocusDesktop({
    List<String> allowedPackageNames = const [],
  }) async {
    opens++;
    openedPackages = allowedPackageNames;
    if (failOpen) throw StateError('launcher unavailable');
    return openResult;
  }

  @override
  Future<void> startTimer({
    String? sessionId,
    required String title,
    String? titleKey,
    required DateTime endsAt,
    required FocusPolicyMode mode,
    List<String> allowedPackageNames = const [],
    String? taskTypeName,
    String? taskTypeKey,
    int? maxAppExits,
    bool paused = false,
    bool focusDesktopEnabled = false,
    int appExitCount = 0,
    int interruptionCount = 0,
  }) async {
    state = FocusTimerState(sessionId: sessionId, isActive: true);
    nativeTitle = title;
    nativeTitleKey = titleKey;
    desktopEnabled = focusDesktopEnabled;
    sessionPackages = allowedPackageNames;
  }

  @override
  Future<FocusTimerState> getTimerState() async => state;

  @override
  Future<void> stopTimer() async => state = const FocusTimerState();
}

class _FailingSettingsStore extends MemoryDocumentStore {
  bool failDesktopWrite = false;

  @override
  Future<void> writeSetting(
    String key,
    String value, {
    String accountId = DocumentStore.localAccountId,
  }) async {
    if (failDesktopWrite && key == 'focus_desktop_enabled') {
      throw StateError('setting write failed');
    }
    await super.writeSetting(key, value, accountId: accountId);
  }
}
