import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/core/state/private_vault_controller.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/local/private_vault_crypto.dart';
import 'package:pactick/data/local/private_vault_storage.dart';
import 'package:pactick/data/local/workspace_backup.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/tasks/pages/private_vault_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _password = '私密箱测试-password-2026';
const _local = DocumentStore.localAccountId;
const _taskId = '11111111-1111-4111-8111-111111111111';
const _projectId = '22222222-2222-4222-8222-222222222222';
const _planId = '33333333-3333-4333-8333-333333333333';
const _sessionId = '44444444-4444-4444-8444-444444444444';
const _reminderId = '55555555-5555-4555-8555-555555555555';
const _secret = '从不应出现在同步中的私密正文-Secret-71864';
final _now = DateTime.utc(2026, 10, 17, 1);
const _task = TaskItem(
  id: _taskId,
  title: _secret,
  note: '私密备注-88195',
  priority: TaskPriority.high,
  status: TaskStatus.open,
  rank: 0,
  tags: ['私密标签-128'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late String emptyEnvelope;
  late SecretKeyData fixtureKey;
  final fixtureSalt = List<int>.generate(32, (index) => index + 1);
  late PrivateVaultCrypto crypto;

  setUpAll(() async {
    // Derive the real PBKDF2 600000-iteration key once; all tests still use
    // production AES-GCM and payload/backup validation.
    fixtureKey = await const PrivateVaultCrypto().derive(
      _password,
      fixtureSalt,
    );
    crypto = _FixtureCrypto(fixtureSalt, fixtureKey);
    emptyEnvelope = (await crypto.encrypt(
      WorkspaceArchive(
        createdAt: _now,
        documents: const [],
        settings: const {},
        pendingChanges: const [],
      ).encode(),
      key: fixtureKey,
      salt: fixtureSalt,
    )).encode();
  });
  tearDownAll(() => fixtureKey.destroy());

  for (final backend in ['memory', 'sqlite']) {
    group('$backend private vault', () {
      late DocumentStore store;
      late PrivateVaultStorage storage;
      late PrivateVaultController vault;
      Directory? temp;
      String? databasePath;
      setUp(() async {
        if (backend == 'sqlite') {
          temp = await Directory.systemTemp.createTemp(
            'pactick-private-vault-',
          );
          databasePath = '${temp!.path}/workspace.db';
          store = LocalDatabase(
            databasePath: databasePath,
            factory: databaseFactoryFfi,
          );
        } else {
          store = MemoryDocumentStore();
        }
        storage = store as PrivateVaultStorage;
        await storage.writePrivateVault(
          _local,
          emptyEnvelope,
          expectedEnvelope: null,
        );
        vault = PrivateVaultController(store: store, crypto: crypto);
        await vault.selectWorkspace(_local);
      });
      tearDown(() async {
        vault.dispose();
        if (store is LocalDatabase) await (store as LocalDatabase).close();
        if (temp != null) {
          await temp!.delete(recursive: true);
          temp = null;
        }
      });

      test('default locked, common reads/outbox/backups never expose private content', () async {
        expect(vault.configured, isTrue);
        expect(vault.isUnlocked, isFalse);
        expect(vault.tasks, isEmpty);
        await vault.unlock(_password);
        await vault.saveProject('隐藏分类-16633');
        final task = _task.copyWith(projectId: vault.projects.single.id);
        await vault.saveTask(task);
        await vault.savePlanBlock(
          PlanBlockItem(
            id: _planId,
            taskId: task.id,
            startsAt: _now,
            endsAt: _now.add(const Duration(minutes: 30)),
            timeZone: 'Asia/Shanghai',
            status: PlanBlockStatus.scheduled,
          ),
        );
        for (final entity in [
          'task',
          'project',
          'plan_block',
          'focus_session',
          'reminder',
        ]) {
          expect(await store.readDocuments(entity), isEmpty);
        }
        expect(await store.pendingOperationCount(), 0);
        expect(await store.readPendingOperations(_local), isEmpty);
        final backup = await WorkspaceBackupService(store).exportJson(_local);
        for (final secret in [
          _secret,
          '私密备注-88195',
          '私密标签-128',
          '隐藏分类-16633',
          _password,
        ]) {
          expect(backup, isNot(contains(secret)));
          expect(
            (await storage.readPrivateVault(_local))!.envelope,
            isNot(contains(secret)),
          );
        }
        vault.lock();
        expect(vault.tasks, isEmpty);
        expect(vault.projects, isEmpty);
        expect(vault.planBlocks, isEmpty);
        expect(vault.focusSessions, isEmpty);
        await expectLater(
          vault.saveTask(_task),
          throwsA(isA<PrivateVaultException>()),
        );
        if (backend == 'sqlite') {
          final db = await databaseFactoryFfi.openDatabase(databasePath!);
          final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'",
          );
          for (final table in tables) {
            final name = table['name']! as String;
            final rows = await db.query(name);
            expect(jsonEncode(rows), isNot(contains(_secret)), reason: name);
            expect(jsonEncode(rows), isNot(contains(_password)), reason: name);
          }
          final fileContents = utf8.decode(
            await File(databasePath!).readAsBytes(),
            allowMalformed: true,
          );
          expect(fileContents, isNot(contains('Secret-71864')));
          expect(fileContents, isNot(contains(_password)));
        }
      });

      test(
        'wrong password persists retry delay without deleting ciphertext',
        () async {
          final before = (await storage.readPrivateVault(_local))!.envelope;
          await expectLater(
            vault.unlock('错误-password'),
            throwsA(isA<PrivateVaultException>()),
          );
          expect(vault.isUnlocked, isFalse);
          expect(vault.tasks, isEmpty);
          final state = (await storage.readPrivateVault(_local))!;
          expect(state.envelope, before);
          expect(state.failedAttempts, 1);
          expect(state.retryAfter!.isAfter(DateTime.now()), isTrue);
          final restarted = PrivateVaultController(
            store: store,
            crypto: crypto,
          );
          addTearDown(restarted.dispose);
          await restarted.selectWorkspace(_local);
          expect(restarted.retryAfter, state.retryAfter);
          await expectLater(
            restarted.unlock(_password),
            throwsA(isA<PrivateVaultException>()),
          );
        },
      );

      test(
        'local task and all dedicated records move atomically and clear outbox',
        () async {
          await _seedOrdinaryTask(store);
          await vault.unlock(_password);
          await vault.importLocalTask(_taskId);
          expect(vault.tasks.single.title, _secret);
          expect(vault.planBlocks.single.id, _planId);
          expect(vault.focusSessions.single.id, _sessionId);
          for (final entity in [
            'task',
            'plan_block',
            'focus_session',
            'reminder',
          ]) {
            expect(await store.readDocuments(entity), isEmpty, reason: entity);
          }
          expect((await store.readDocuments('project')).single.id, _projectId);
          final ordinaryBackup = await store.exportWorkspace(_local);
          expect(
            ordinaryBackup.pendingChanges.every(
              (change) => change.entityType == 'project',
            ),
            isTrue,
          );
          expect(ordinaryBackup.encode(), isNot(contains(_secret)));
          await vault.exportTaskToOrdinary(_taskId);
          expect(vault.tasks, isEmpty);
          expect(
            (await store.readDocuments('task')).single.body['title'],
            _secret,
          );
          expect((await store.readDocuments('plan_block')).single.id, _planId);
          expect(
            (await store.readDocuments('focus_session')).single.id,
            _sessionId,
          );
          expect(
            (await store.readDocuments('reminder')).single.id,
            _reminderId,
          );
        },
      );

      test(
        'attempted sync and remote/copied workspace conversion are rejected',
        () async {
          await _seedOrdinaryTask(store);
          await vault.unlock(_password);
          await store.readPendingOperations(_local);
          final before = (await storage.readPrivateVault(_local))!.envelope;
          await expectLater(vault.importLocalTask(_taskId), throwsStateError);
          expect((await storage.readPrivateVault(_local))!.envelope, before);
          expect(await store.readDocuments('task'), hasLength(1));
          final copyId = await WorkspaceBackupService(store)
              .copyToLocal(_local);
          await vault.selectWorkspace(copyId);
          await vault.unlock(_password);
          await expectLater(vault.importLocalTask(_taskId), throwsStateError);
          await store.ensureAccount('remote-account');
          await vault.selectWorkspace('remote-account');
          expect(vault.isUnlocked, isFalse);
          expect(vault.tasks, isEmpty);
          expect(vault.configured, isFalse);
        },
      );

      test(
        'stale candidate and duplicate ordinary IDs leave both stores intact',
        () async {
          await _seedOrdinaryTask(store);
          await vault.unlock(_password);
          final candidate = await storage.readPrivateImportCandidate(
            _local,
            _taskId,
          );
          await store.putDocument(
            'task',
            _taskId,
            _task.copyWith(title: '后来编辑').toBody(),
          );
          await expectLater(
            storage.commitPrivateImport(
              _local,
              expectedEnvelope: emptyEnvelope,
              envelope: emptyEnvelope,
              taskId: _taskId,
              expectedSnapshot: candidate.snapshot,
            ),
            throwsStateError,
          );
          expect(
            (await store.readDocuments('task')).single.body['title'],
            '后来编辑',
          );
          await vault.importLocalTask(_taskId);
          await store.putDocument(
            'task',
            _taskId,
            _task.copyWith(title: '重复标识').toBody(),
          );
          final before = (await storage.readPrivateVault(_local))!.envelope;
          await expectLater(
            vault.exportTaskToOrdinary(_taskId),
            throwsStateError,
          );
          expect((await storage.readPrivateVault(_local))!.envelope, before);
          expect(vault.tasks.single.title, '后来编辑');
          expect(
            (await store.readDocuments('task')).single.body['title'],
            '重复标识',
          );
        },
      );

      test(
        'cancelled tasks cannot start private focus after import or restore',
        () async {
          await store.putDocument(
            'task',
            _taskId,
            _task.copyWith(status: TaskStatus.cancelled).toBody(),
          );
          await vault.unlock(_password);
          await vault.importLocalTask(_taskId);
          expect(vault.tasks.single.status, TaskStatus.cancelled);
          await expectLater(
            vault.startFocus(_taskId, 25),
            throwsA(isA<PrivateVaultException>()),
          );
          expect(vault.hasActiveFocus, isFalse);
          expect(vault.focusSessions, isEmpty);
          final encrypted = await vault.exportEncryptedBackup();
          final fresh = MemoryDocumentStore();
          final restored = PrivateVaultController(store: fresh, crypto: crypto);
          addTearDown(restored.dispose);
          await restored.selectWorkspace(_local);
          final id = await restored.restoreEncryptedBackup(
            encrypted,
            _password,
          );
          await restored.selectWorkspace(id);
          await restored.unlock(_password);
          expect(restored.tasks.single.status, TaskStatus.cancelled);
          await expectLater(
            restored.startFocus(_taskId, 25),
            throwsA(isA<PrivateVaultException>()),
          );
          expect(restored.hasActiveFocus, isFalse);
          expect(restored.focusSessions, isEmpty);
        },
      );

      test('portable backups restore on a fresh store with original password and stay locked', () async {
        await vault.unlock(_password);
        await vault.saveTask(_task);
        final encrypted = await vault.exportEncryptedBackup();
        final fresh = MemoryDocumentStore();
        final restorer = PrivateVaultController(store: fresh, crypto: crypto);
        addTearDown(restorer.dispose);
        await restorer.selectWorkspace(_local);
        final id = await restorer.restoreEncryptedBackup(encrypted, _password);
        expect(await fresh.listWorkspaceIds(), containsAll([_local, id]));
        expect(restorer.isUnlocked, isFalse);
        await restorer.selectWorkspace(id);
        expect(restorer.isUnlocked, isFalse);
        expect(restorer.tasks, isEmpty);
        await restorer.unlock(_password);
        expect(restorer.tasks.single.title, _secret);
        expect(await fresh.readDocuments('task', accountId: id), isEmpty);
        expect(await fresh.pendingOperationCount(accountId: id), 0);
      });

      test(
        'bad backup version, ciphertext and password never create a workspace',
        () async {
          final ids = await store.listWorkspaceIds();
          final badVersion = Map<String, Object?>.from(
            jsonDecode(emptyEnvelope) as Map,
          )..['version'] = 99;
          await expectLater(
            vault.restoreEncryptedBackup(jsonEncode(badVersion), _password),
            throwsFormatException,
          );
          final corrupted = Map<String, Object?>.from(
            jsonDecode(emptyEnvelope) as Map,
          );
          final bytes = base64Decode(corrupted['ciphertext']! as String)
            ..[0] ^= 1;
          corrupted['ciphertext'] = base64Encode(bytes);
          await expectLater(
            vault.restoreEncryptedBackup(jsonEncode(corrupted), _password),
            throwsA(isA<PrivateVaultException>()),
          );
          await expectLater(
            vault.restoreEncryptedBackup(emptyEnvelope, '另一错误密码'),
            throwsA(isA<PrivateVaultException>()),
          );
          expect(await store.listWorkspaceIds(), ids);
          expect(
            (await storage.readPrivateVault(_local))!.envelope,
            emptyEnvelope,
          );
        },
      );

      test('same workspace refresh preserves unlock; account switch and restart lock', () async {
        await vault.unlock(_password);
        await vault.saveTask(_task);
        await vault.selectWorkspace(_local);
        expect(vault.isUnlocked, isTrue);
        await vault.selectWorkspace('other-workspace');
        expect(vault.isUnlocked, isFalse);
        expect(vault.tasks, isEmpty);
        await vault.selectWorkspace(_local);
        expect(vault.isUnlocked, isFalse);
        final restarted = PrivateVaultController(store: store, crypto: crypto);
        addTearDown(restarted.dispose);
        await restarted.selectWorkspace(_local);
        expect(restarted.tasks, isEmpty);
        await restarted.unlock(_password);
        expect(restarted.tasks.single.title, _secret);
      });

      test('generic private timer survives locking, but backups and copies cannot own it', () async {
        await vault.unlock(_password);
        await vault.saveTask(_task);
        await vault.startFocus(_taskId, 25);
        final runtime = vault.activeFocusRuntime!;
        final header = jsonDecode(
          (await storage.readPrivateVault(_local))!.envelope,
        ) as Map;
        expect(jsonEncode(header['runtime']), isNot(contains(_taskId)));
        expect(jsonEncode(header['runtime']), isNot(contains(_secret)));
        vault.lock();
        expect(vault.hasActiveFocus, isTrue);
        expect(vault.tasks, isEmpty);
        final resumed = PrivateVaultController(store: store, crypto: crypto);
        addTearDown(resumed.dispose);
        await resumed.selectWorkspace(_local);
        expect(resumed.activeFocusRuntime?.sessionId, runtime.sessionId);
        expect(resumed.isUnlocked, isFalse);
        final backup = await WorkspaceBackupService(store).exportJson(_local);
        expect(backup, isNot(contains(PrivateVaultCrypto.ownershipSetting)));
        final copyId = await WorkspaceBackupService(store).copyToLocal(_local);
        final copied = PrivateVaultController(store: store, crypto: crypto);
        addTearDown(copied.dispose);
        await copied.selectWorkspace(copyId);
        expect(copied.hasActiveFocus, isFalse);
        await copied.unlock(_password);
        expect(copied.hasActiveFocus, isFalse);
        expect(
          copied.focusSessions.single.status,
          FocusSessionStatus.interrupted,
        );
        final fresh = MemoryDocumentStore();
        final restoredId = await WorkspaceBackupService(fresh)
            .restoreJson(backup);
        final restored = PrivateVaultController(store: fresh, crypto: crypto);
        addTearDown(restored.dispose);
        await restored.selectWorkspace(restoredId);
        expect(restored.hasActiveFocus, isFalse);
        await restored.unlock(_password);
        expect(
          restored.focusSessions.single.status,
          FocusSessionStatus.interrupted,
        );
      });

      if (backend == 'sqlite') {
        test(
          'failed password replacement leaves old key and data usable',
          () async {
            await vault.unlock(_password);
            await vault.saveTask(_task);
            final db = await databaseFactoryFfi.openDatabase(databasePath!);
            await db.execute(
              "CREATE TRIGGER fail_private_password BEFORE INSERT ON private_vaults BEGIN SELECT RAISE(ABORT, 'injected password failure'); END",
            );
            final before = (await storage.readPrivateVault(_local))!.envelope;
            await expectLater(
              vault.changePassword(
                _password,
                'changed-password-899',
                'changed-password-899',
              ),
              throwsA(isA<DatabaseException>()),
            );
            expect((await storage.readPrivateVault(_local))!.envelope, before);
            vault.lock();
            await vault.unlock(_password);
            expect(vault.tasks.single.title, _secret);
          },
        );
        test('SQLite failure after vault write rolls back the task and outbox deletion', () async {
          await _seedOrdinaryTask(store);
          await vault.unlock(_password);
          final db = await databaseFactoryFfi.openDatabase(databasePath!);
          await db.execute(
            "CREATE TRIGGER fail_private_import BEFORE DELETE ON documents WHEN OLD.entity_type='task' BEGIN SELECT RAISE(ABORT, 'injected transfer failure'); END",
          );
          final before = (await storage.readPrivateVault(_local))!.envelope;
          final pendingBefore = await store.pendingOperationCount();
          await expectLater(
            vault.importLocalTask(_taskId),
            throwsA(isA<DatabaseException>()),
          );
          expect((await storage.readPrivateVault(_local))!.envelope, before);
          expect(vault.tasks, isEmpty);
          expect(
            (await store.readDocuments('task')).single.body['title'],
            _secret,
          );
          expect(await store.pendingOperationCount(), pendingBefore);
          expect(await store.readDocuments('plan_block'), hasLength(1));
        });
      }
    });
  }

  test('lock during a pending derive cannot republish plaintext', () async {
    final store = MemoryDocumentStore();
    await store.writePrivateVault(
      _local,
      emptyEnvelope,
      expectedEnvelope: null,
    );
    final gate = Completer<void>();
    final entered = Completer<void>();
    final gated = _GatedCrypto(crypto, entered, gate);
    final vault = PrivateVaultController(store: store, crypto: gated);
    addTearDown(vault.dispose);
    await vault.selectWorkspace(_local);
    final future = vault.unlock(_password);
    final failed = expectLater(future, throwsA(isA<PrivateVaultException>()));
    await entered.future;
    vault.lock();
    gate.complete();
    await failed;
    expect(vault.isUnlocked, isFalse);
    expect(vault.tasks, isEmpty);
  });

  test('new password uses new salt and only the new password decrypts updated envelope', () async {
    final store = MemoryDocumentStore();
    await store.writePrivateVault(
      _local,
      emptyEnvelope,
      expectedEnvelope: null,
    );
    final vault = PrivateVaultController(store: store, crypto: crypto);
    addTearDown(vault.dispose);
    await vault.selectWorkspace(_local);
    await vault.unlock(_password);
    await vault.saveTask(_task);
    final original = (await store.readPrivateVault(_local))!.envelope;
    await vault.changePassword(
      _password,
      'New-private-password-771',
      'New-private-password-771',
    );
    final changed = (await store.readPrivateVault(_local))!.envelope;
    expect(
      PrivateVaultEnvelope.decode(changed).salt,
      isNot(PrivateVaultEnvelope.decode(original).salt),
    );
    final oldKey = await crypto.derive(
      _password,
      PrivateVaultEnvelope.decode(changed).salt,
    );
    try {
      await expectLater(
        crypto.decrypt(PrivateVaultEnvelope.decode(changed), oldKey),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    } finally {
      oldKey.destroy();
    }
    vault.lock();
    await vault.unlock('New-private-password-771');
    expect(vault.tasks.single.title, _secret);
    final oldBackupId = await vault.restoreEncryptedBackup(original, _password);
    expect(await store.listWorkspaceIds(), contains(oldBackupId));
  });

  test('legacy v1 ordinary archive remains recoverable', () async {
    final json =
        WorkspaceArchive(
            createdAt: _now,
            documents: const [],
            settings: const {},
            pendingChanges: const [],
          ).toJson()
          ..['version'] = 1
          ..remove('private_vault');
    final store = MemoryDocumentStore();
    final id = await WorkspaceBackupService(store)
        .restoreJson(jsonEncode(json));
    expect(await store.listWorkspaceIds(), contains(id));
    expect(await store.readPrivateVault(id), isNull);
  });

  test(
    'setting a new password requires confirmation before any row is created',
    () async {
      final store = MemoryDocumentStore();
      final vault = PrivateVaultController(store: store);
      addTearDown(vault.dispose);
      await vault.selectWorkspace(_local);
      await expectLater(
        vault.configure('password-123', 'different-123'),
        throwsA(isA<PrivateVaultException>()),
      );
      await expectLater(
        vault.configure('short', 'short'),
        throwsA(isA<PrivateVaultException>()),
      );
      expect(await store.readPrivateVault(_local), isNull);
      await vault.configure('password-123', 'password-123');
      expect(vault.configured, isTrue);
      expect(vault.isUnlocked, isTrue);
      vault.lock();
      await vault.unlock('password-123');
      expect(vault.isUnlocked, isTrue);
    },
  );

  test(
    'lock after focus commit preserves start ownership and committed stop',
    () async {
      final store = _CommitGateStore();
      await store.writePrivateVault(
        _local,
        emptyEnvelope,
        expectedEnvelope: null,
      );
      final events = <PrivateFocusRuntime?>[];
      final vault = PrivateVaultController(
        store: store,
        crypto: crypto,
        onFocusRuntimeChanged: (runtime) async => events.add(runtime),
      );
      addTearDown(vault.dispose);
      await vault.selectWorkspace(_local);
      await vault.unlock(_password);
      await vault.saveTask(_task);
      store.gateNextWrite();
      final starting = expectLater(
        vault.startFocus(_taskId, 25),
        throwsA(isA<PrivateVaultException>()),
      );
      await store.committed!.future;
      vault.lock();
      store.resume!.complete();
      await starting;
      expect(vault.hasActiveFocus, isTrue);
      expect(events.last?.sessionId, vault.activeFocusRuntime!.sessionId);
      expect(vault.tasks, isEmpty);
      store.committed = null;
      await vault.unlock(_password);
      store.gateNextWrite();
      final stopping = expectLater(
        vault.stopFocus(),
        throwsA(isA<PrivateVaultException>()),
      );
      await store.committed!.future;
      vault.lock();
      store.resume!.complete();
      await stopping;
      expect(vault.hasActiveFocus, isFalse);
      expect(events.last, isNull);
      store.committed = null;
      await vault.unlock(_password);
      expect(vault.focusSessions.single.status, FocusSessionStatus.abandoned);
    },
  );

  test('background lock during workspace metadata read does not hide an existing vault', () async {
    final store = _ReadGateStore();
    await store.writePrivateVault(
      _local,
      emptyEnvelope,
      expectedEnvelope: null,
    );
    final vault = PrivateVaultController(store: store, crypto: crypto);
    addTearDown(vault.dispose);
    store.pauseRead = true;
    final selecting = vault.selectWorkspace(_local);
    await store.entered.future;
    vault.lock();
    store.gate.complete();
    await selecting;
    expect(vault.configured, isTrue);
    expect(vault.isUnlocked, isFalse);
    store.pauseRead = false;
    await vault.unlock(_password);
    expect(vault.isUnlocked, isTrue);
  });

  testWidgets('cancelled private tasks do not offer a start focus action', (
    tester,
  ) async {
    final store = MemoryDocumentStore();
    await store.writePrivateVault(
      _local,
      emptyEnvelope,
      expectedEnvelope: null,
    );
    final app = AppController(
      repository: WorkspaceRepository(store),
      focusPlatform: const FocusPlatformGateway(),
    );
    addTearDown(app.dispose);
    await app.initialize();
    await tester.runAsync(() async {
      await app.privateVault.unlock(_password);
      await app.privateVault.saveTask(
        _task.copyWith(status: TaskStatus.cancelled),
      );
    });
    await tester.pumpWidget(MaterialApp(home: PrivateVaultPage(app: app)));
    await tester.pumpAndSettle();
    expect(find.text(_secret), findsOneWidget);
    expect(find.text('开始专注'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'locking dismisses private menus and discards editor text and semantics',
    (tester) async {
      final store = MemoryDocumentStore();
      await store.writePrivateVault(
        _local,
        emptyEnvelope,
        expectedEnvelope: null,
      );
      final app = AppController(
        repository: WorkspaceRepository(store),
        focusPlatform: const FocusPlatformGateway(),
      );
      addTearDown(app.dispose);
      await app.initialize();
      await tester.runAsync(() async {
        await app.privateVault.unlock(_password);
        await app.privateVault.saveProject('私密分类弹出层-772');
        await app.privateVault.saveTask(
          _task.copyWith(projectId: app.privateVault.projects.single.id),
        );
      });
      await tester.pumpWidget(
        AppScope(
          controller: app,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showPrivateVault(context),
                  child: const Text('打开私密箱'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开私密箱'));
      await tester.pumpAndSettle();
      expect(find.text(_secret), findsOneWidget);
      await tester.ensureVisible(find.text('编辑'));
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      final title = find.widgetWithText(TextField, '任务标题');
      await tester.enterText(title, '尚未保存的秘密输入-663');
      await tester.tap(find.text('私密分类弹出层-772'));
      await tester.pumpAndSettle();
      expect(find.text('私密分类弹出层-772'), findsWidgets);
      app.privateVault.lock();
      await tester.pumpAndSettle();
      expect(find.text(_secret), findsNothing);
      expect(find.text('私密分类弹出层-772'), findsNothing);
      expect(find.text('尚未保存的秘密输入-663'), findsNothing);
      expect(find.text('私密任务箱密码'), findsOneWidget);
      expect(
        tester
            .widgetList<EditableText>(find.byType(EditableText))
            .every((field) => field.controller.text.isEmpty),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _FixtureCrypto extends PrivateVaultCrypto {
  _FixtureCrypto(this.salt, this.key);
  final List<int> salt;
  final SecretKeyData key;
  @override
  Future<SecretKeyData> derive(String password, List<int> inputSalt) =>
      password == _password && base64Encode(inputSalt) == base64Encode(salt)
      ? Future.value(key.copy())
      : super.derive(password, inputSalt);
}

class _CommitGateStore extends MemoryDocumentStore {
  Completer<void>? committed;
  Completer<void>? resume;
  void gateNextWrite() {
    committed = Completer<void>();
    resume = Completer<void>();
  }

  @override
  Future<void> writePrivateVault(
    String accountId,
    String envelope, {
    required String? expectedEnvelope,
    bool ownsFocusRuntime = false,
  }) async {
    await super.writePrivateVault(
      accountId,
      envelope,
      expectedEnvelope: expectedEnvelope,
      ownsFocusRuntime: ownsFocusRuntime,
    );
    if (committed != null) {
      committed!.complete();
      await resume!.future;
    }
  }
}

class _ReadGateStore extends MemoryDocumentStore {
  bool pauseRead = false;
  final entered = Completer<void>();
  final gate = Completer<void>();
  @override
  Future<PrivateVaultStoredState?> readPrivateVault(String accountId) async {
    final value = await super.readPrivateVault(accountId);
    if (pauseRead) {
      entered.complete();
      await gate.future;
    }
    return value;
  }
}

class _GatedCrypto extends PrivateVaultCrypto {
  _GatedCrypto(this.delegate, this.entered, this.gate);
  final PrivateVaultCrypto delegate;
  final Completer<void> entered;
  final Completer<void> gate;
  @override
  Future<SecretKeyData> derive(String password, List<int> salt) async {
    entered.complete();
    await gate.future;
    return delegate.derive(password, salt);
  }
}

Future<void> _seedOrdinaryTask(DocumentStore store) async {
  await store.putDocument(
    'project',
    _projectId,
    const ProjectItem(
      id: _projectId,
      name: '原有普通分类',
      color: '#5367A5',
    ).toBody(),
  );
  await store.putDocument(
    'task',
    _taskId,
    _task.copyWith(projectId: _projectId).toBody(),
  );
  await store.putDocument(
    'plan_block',
    _planId,
    PlanBlockItem(
      id: _planId,
      taskId: _taskId,
      title: '私密计划标题-817',
      startsAt: _now,
      endsAt: _now.add(const Duration(minutes: 30)),
      timeZone: 'Asia/Shanghai',
      status: PlanBlockStatus.scheduled,
    ).toBody(),
  );
  await store.putDocument(
    'focus_session',
    _sessionId,
    FocusSessionItem(
      id: _sessionId,
      taskId: _taskId,
      planBlockId: _planId,
      plannedDurationSeconds: 1800,
      startedAt: _now,
      endedAt: _now.add(const Duration(minutes: 30)),
      actualDurationSeconds: 1800,
      startedDeviceId: 'android-local',
      status: FocusSessionStatus.completed,
      timeZone: 'Asia/Shanghai',
    ).toBody(),
  );
  await store.putDocument('reminder', _reminderId, {
    'target_type': 'plan_block',
    'target_id': _planId,
    'trigger_at': _now.toIso8601String(),
    'time_zone': 'Asia/Shanghai',
    'status': 'pending',
    'delivery_mode': 'local',
  });
}
