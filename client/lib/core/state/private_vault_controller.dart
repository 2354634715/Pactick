import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/local_database.dart';
import '../../data/local/private_vault_crypto.dart';
import '../../data/local/private_vault_storage.dart';
import '../../data/local/workspace_archive.dart';
import '../models/domain_models.dart';

class PrivateVaultException implements Exception {
  const PrivateVaultException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Contains no title, task identifier, category or other private content.
class PrivateFocusRuntime {
  const PrivateFocusRuntime({
    required this.sessionId,
    required this.startedAt,
    required this.endsAt,
  });
  final String sessionId;
  final DateTime startedAt;
  final DateTime endsAt;
  Map<String, Object?> toJson() => {
    'session_id': sessionId,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ends_at': endsAt.toUtc().toIso8601String(),
  };
  factory PrivateFocusRuntime.fromJson(Map<String, Object?> value) =>
      PrivateFocusRuntime(
        sessionId: value['session_id']! as String,
        startedAt: DateTime.parse(value['started_at']! as String),
        endsAt: DateTime.parse(value['ends_at']! as String),
      );
}

/// Private records have exactly one read path and never enter AppController's
/// ordinary lists, generic document persistence or the sync outbox.
class PrivateVaultController extends ChangeNotifier {
  PrivateVaultController({
    required DocumentStore store,
    this.canStartFocus,
    this.onFocusRuntimeChanged,
    PrivateVaultCrypto crypto = const PrivateVaultCrypto(),
    Uuid uuid = const Uuid(),
  }) : _storage = store is PrivateVaultStorage
           ? store as PrivateVaultStorage
           : null,
       _store = store,
       // Public injection names keep tests independent of implementation fields.
       // ignore: prefer_initializing_formals
       _crypto = crypto,
       // ignore: prefer_initializing_formals
       _uuid = uuid;

  final PrivateVaultStorage? _storage;
  final DocumentStore _store;
  final PrivateVaultCrypto _crypto;
  final Uuid _uuid;
  final bool Function()? canStartFocus;
  final Future<void> Function(PrivateFocusRuntime? runtime)?
  onFocusRuntimeChanged;
  String? _accountId;
  PrivateVaultStoredState? _stored;
  PrivateVaultEnvelope? _envelope;
  SecretKeyData? _key;
  WorkspaceArchive? _content;
  bool _busy = false;
  bool _disposed = false;
  int _epoch = 0;
  int _selectionGeneration = 0;
  int _lockGeneration = 0;
  Timer? _ticker;
  PrivateFocusRuntime? _runtime;
  String? _runtimeAccountId;
  String? timerWarning;

  bool get supported => _storage != null;
  bool get configured => _stored != null;
  bool get isUnlocked => _key != null && _content != null;
  bool get isBusy => _busy;
  String? get accountId => _accountId;
  int get lockGeneration => _lockGeneration;
  DateTime? get retryAfter => _stored?.retryAfter;
  PrivateFocusRuntime? get activeFocusRuntime => _runtime;
  bool get hasActiveFocus => _runtime != null;
  int get remainingFocusSeconds => _runtime == null
      ? 0
      : _runtime!.endsAt.difference(DateTime.now()).inSeconds.clamp(0, 86400);

  List<ArchiveDocument> get _documents =>
      isUnlocked ? _content!.documents : const [];
  List<TaskItem> get tasks => List.unmodifiable(
    _documents
        .where((doc) => doc.entityType == 'task' && !doc.deleted)
        .map((doc) => TaskItem.fromDocument(doc.id, doc.body))
        .toList()
      ..sort(TaskItem.compareByPriority),
  );
  List<ProjectItem> get projects => List.unmodifiable(
    _documents
        .where((doc) => doc.entityType == 'project' && !doc.deleted)
        .map((doc) => ProjectItem.fromDocument(doc.id, doc.body)),
  );
  List<PlanBlockItem> get planBlocks => List.unmodifiable(
    _documents
        .where((doc) => doc.entityType == 'plan_block' && !doc.deleted)
        .map((doc) => PlanBlockItem.fromDocument(doc.id, doc.body)),
  );
  List<FocusSessionItem> get focusSessions => List.unmodifiable(
    _documents
        .where((doc) => doc.entityType == 'focus_session' && !doc.deleted)
        .map((doc) => FocusSessionItem.fromDocument(doc.id, doc.body)),
  );

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> selectWorkspace(String accountId) async {
    if (_disposed || _accountId == accountId) return;
    lock();
    final selection = ++_selectionGeneration;
    _accountId = accountId;
    _stored = null;
    _envelope = null;
    if (_storage == null) {
      _changed();
      return;
    }
    final state = await _storage.readPrivateVault(accountId);
    if (_disposed ||
        selection != _selectionGeneration ||
        _accountId != accountId) {
      return;
    }
    _stored = state;
    if (state != null) {
      try {
        _envelope = PrivateVaultEnvelope.decode(state.envelope);
        final rawRuntime = _envelope!.runtime;
        if (_runtime == null && rawRuntime != null) {
          final runtime = PrivateFocusRuntime.fromJson(rawRuntime);
          if (DateTime.now().isBefore(runtime.endsAt) &&
              await _ownsRuntime(
                accountId,
                state.envelope,
                runtime.sessionId,
              )) {
            if (_disposed ||
                selection != _selectionGeneration ||
                _accountId != accountId) {
              return;
            }
            _runtime = runtime;
            _runtimeAccountId = accountId;
            _startTicker();
            await _notifyRuntime();
          }
        }
      } on FormatException {
        // Preserve malformed data; recovery never silently creates a new vault.
      }
    }
    _changed();
  }

  Future<bool> _ownsRuntime(
    String accountId,
    String envelope,
    String sessionId,
  ) async {
    final encoded = await _store.readSetting(
      PrivateVaultCrypto.ownershipSetting,
    );
    if (encoded == null) return false;
    try {
      final value = jsonDecode(encoded);
      return value is Map &&
          value['account_id'] == accountId &&
          value['session_id'] == sessionId &&
          value['envelope_digest'] ==
              await PrivateVaultCrypto.envelopeDigest(envelope);
    } on FormatException {
      return false;
    }
  }

  /// Does not stop a generic active timer. All decrypted views are invalidated
  /// synchronously, including operations awaiting key derivation or disk I/O.
  void lock() {
    _epoch++;
    _lockGeneration++;
    _key?.destroy();
    _key = null;
    _content = null;
    _changed();
  }

  void _requireUnlocked() {
    if (!isUnlocked) throw const PrivateVaultException('请先解锁私密任务箱。');
  }

  void _checkEpoch(int epoch, String accountId) {
    if (_disposed || epoch != _epoch || accountId != _accountId) {
      throw const PrivateVaultException('私密任务箱已锁定，操作已停止。');
    }
  }

  void _validatePassword(String password, String confirmation) {
    if (password != confirmation) {
      throw const PrivateVaultException('两次输入的密码不一致。');
    }
    if (password.runes.length < 8 || password.runes.length > 1024) {
      throw const PrivateVaultException('密码须为 8 至 1024 个字符。');
    }
  }

  Future<T> _operation<T>(Future<T> Function() action) async {
    if (_busy) throw const PrivateVaultException('操作正在进行，请稍候。');
    if (_storage == null || _accountId == null) {
      throw const PrivateVaultException('当前工作区无法使用私密任务箱。');
    }
    _busy = true;
    _changed();
    try {
      return await action();
    } finally {
      _busy = false;
      _changed();
    }
  }

  WorkspaceArchive _contentWith(List<ArchiveDocument> documents) =>
      WorkspaceArchive.decode(
        WorkspaceArchive(
          createdAt: DateTime.now().toUtc(),
          documents: documents,
          settings: const {},
          pendingChanges: const [],
        ).encode(),
      );

  Future<void> configure(String password, String confirmation) =>
      _operation(() async {
        _validatePassword(password, confirmation);
        if (configured) throw const PrivateVaultException('此工作区已设置私密任务箱密码。');
        final account = _accountId!;
        final epoch = _epoch;
        final salt = _crypto.newSalt();
        final key = await _crypto.derive(password, salt);
        var retained = false;
        try {
          _checkEpoch(epoch, account);
          final content = _contentWith(const []);
          final envelope = await _crypto.encrypt(
            content.encode(),
            key: key,
            salt: salt,
          );
          _checkEpoch(epoch, account);
          await _storage!.writePrivateVault(
            account,
            envelope.encode(),
            expectedEnvelope: null,
          );
          if (_accountId == account) {
            _stored = PrivateVaultStoredState(envelope: envelope.encode());
            _envelope = envelope;
          }
          _checkEpoch(epoch, account);
          _stored = PrivateVaultStoredState(envelope: envelope.encode());
          _envelope = envelope;
          _content = content;
          _key = key;
          retained = true;
        } finally {
          if (!retained) key.destroy();
        }
      });

  Future<void> unlock(String password) => _operation(() async {
    if (isUnlocked) lock();
    final account = _accountId!;
    final epoch = _epoch;
    final state = await _storage!.readPrivateVault(account);
    _checkEpoch(epoch, account);
    if (state == null) throw const PrivateVaultException('请先设置私密任务箱密码。');
    _stored = state;
    if (state.retryAfter != null &&
        DateTime.now().isBefore(state.retryAfter!)) {
      throw const PrivateVaultException('密码重试尚未开放，请等待倒计时结束。');
    }
    SecretKeyData? key;
    var retained = false;
    try {
      final envelope = PrivateVaultEnvelope.decode(state.envelope);
      key = await _crypto.derive(password, envelope.salt);
      final content = WorkspaceArchive.decode(
        await _crypto.decrypt(envelope, key),
      );
      if (content.privateVault != null) {
        throw const FormatException('Nested private vault.');
      }
      _checkEpoch(epoch, account);
      // A concurrent writer cannot cause us to publish stale decrypted content.
      if ((await _storage.readPrivateVault(account))?.envelope !=
          state.envelope) {
        throw const PrivateVaultException('私密任务箱已变化，请重新解锁。');
      }
      _checkEpoch(epoch, account);
      await _storage.resetPrivateVaultFailures(account);
      _checkEpoch(epoch, account);
      _key?.destroy();
      _key = key;
      _content = content;
      _envelope = envelope;
      _stored = PrivateVaultStoredState(envelope: state.envelope);
      retained = true;
      final timer = envelope.runtime;
      final ownsTimer =
          timer != null &&
          await _ownsRuntime(
            account,
            state.envelope,
            timer['session_id']! as String,
          );
      _checkEpoch(epoch, account);
      if (!ownsTimer && focusSessions.any((session) => session.isActive)) {
        await _persist(
          _contentWith(_finishedBackupSessions(_content!.documents)),
        );
      } else if (_runtime == null && timer != null && ownsTimer) {
        final runtime = PrivateFocusRuntime.fromJson(timer);
        final session = focusSessions
            .where((item) => item.id == runtime.sessionId)
            .firstOrNull;
        if (session == null ||
            !session.isActive ||
            session.startedAt.toUtc() != runtime.startedAt.toUtc() ||
            session.plannedDurationSeconds !=
                runtime.endsAt.difference(runtime.startedAt).inSeconds) {
          lock();
          throw const PrivateVaultException('私密计时记录不一致，数据保持锁定。');
        }
        if (DateTime.now().isBefore(runtime.endsAt)) {
          _runtime = runtime;
          _runtimeAccountId = account;
          _startTicker();
          await _notifyRuntime();
        }
      }
      await _reconcileFocus();
    } on SecretBoxAuthenticationError {
      _checkEpoch(epoch, account);
      _stored = await _storage.recordPrivateVaultFailure(account);
      throw const PrivateVaultException('密码错误或私密数据已损坏，原数据未改变。');
    } on FormatException {
      _checkEpoch(epoch, account);
      _stored = await _storage.recordPrivateVaultFailure(account);
      throw const PrivateVaultException('密码错误或私密数据已损坏，原数据未改变。');
    } finally {
      if (!retained) key?.destroy();
    }
  });

  Future<void> _persist(
    WorkspaceArchive content, {
    PrivateFocusRuntime? runtime,
    void Function()? onCommitted,
    Future<void> Function(
      String account,
      String oldEnvelope,
      String newEnvelope,
    )?
    commit,
  }) async {
    _requireUnlocked();
    final epoch = _epoch;
    final account = _accountId!;
    final key = _key!.copy();
    final oldEnvelope = _stored!.envelope;
    try {
      final envelope = await _crypto.encrypt(
        content.encode(),
        key: key,
        salt: _envelope!.salt,
        runtime: runtime?.toJson(),
      );
      _checkEpoch(epoch, account);
      if (commit != null) {
        await commit(account, oldEnvelope, envelope.encode());
      } else {
        await _storage!.writePrivateVault(
          account,
          envelope.encode(),
          expectedEnvelope: oldEnvelope,
          ownsFocusRuntime: runtime != null,
        );
      }
      // Timer ownership must follow the committed record even if background
      // locking invalidates the decrypted view before this future resumes.
      onCommitted?.call();
      if (_accountId == account) {
        _envelope = envelope;
        _stored = PrivateVaultStoredState(envelope: envelope.encode());
      }
      _checkEpoch(epoch, account);
      _envelope = envelope;
      _stored = PrivateVaultStoredState(envelope: envelope.encode());
      _content = content;
    } finally {
      key.destroy();
    }
  }

  Future<void> saveTask(TaskItem task) => _operation(() async {
    _requireUnlocked();
    if (task.title.trim().isEmpty) {
      throw const PrivateVaultException('请输入任务标题。');
    }
    final documents =
        _documents.where((doc) => doc.key != 'task\u0000${task.id}').toList()
          ..add(_document('task', task.id, task.toBody()));
    await _persist(_contentWith(documents), runtime: _currentWorkspaceRuntime);
  });

  Future<void> saveProject(String name) => _operation(() async {
    _requireUnlocked();
    if (name.trim().isEmpty) throw const PrivateVaultException('请输入分类名称。');
    final project = ProjectItem(
      id: _uuid.v4(),
      name: name.trim(),
      color: '#5367A5',
    );
    await _persist(
      _contentWith([
        ..._documents,
        _document('project', project.id, project.toBody()),
      ]),
      runtime: _currentWorkspaceRuntime,
    );
  });

  Future<void> savePlanBlock(PlanBlockItem block) => _operation(() async {
    _requireUnlocked();
    if (!block.endsAt.isAfter(block.startsAt)) {
      throw const PrivateVaultException('计划结束时间必须晚于开始时间。');
    }
    await _persist(
      _contentWith([
        ..._documents.where((doc) => doc.key != 'plan_block\u0000${block.id}'),
        _document('plan_block', block.id, block.toBody()),
      ]),
      runtime: _currentWorkspaceRuntime,
    );
  });

  Future<void> removeTask(String taskId) => _operation(() async {
    _requireUnlocked();
    final bundle = _collectTask(taskId);
    await _persist(
      _contentWith(
        _documents
            .where((doc) => !bundle.removedKeys.contains(doc.key))
            .toList(),
      ),
      runtime: _currentWorkspaceRuntime,
    );
  });

  PrivateTransferBundle _collectTask(String id) => collectPrivateTransfer(
    _documents.map(
      (doc) => StoredDocument(
        entityType: doc.entityType,
        id: doc.id,
        body: doc.body,
        version: 0,
        updatedAt: doc.updatedAt,
        deleted: doc.deleted,
      ),
    ),
    id,
  );

  Future<void> importLocalTask(String taskId) => _operation(() async {
    _requireUnlocked();
    final bundle = await _storage!.readPrivateImportCandidate(
      _accountId!,
      taskId,
    );
    final merged = {for (final doc in _documents) doc.key: doc};
    for (final doc in bundle.documents) {
      if (merged.containsKey(doc.key) &&
          jsonEncode(merged[doc.key]!.body) != jsonEncode(doc.body)) {
        throw const PrivateVaultException('私密箱含有相同标识但内容不同的记录，转入已取消。');
      }
      merged[doc.key] = doc;
    }
    await _persist(
      _contentWith(merged.values.toList()),
      runtime: _currentWorkspaceRuntime,
      commit: (account, old, next) => _storage.commitPrivateImport(
        account,
        expectedEnvelope: old,
        envelope: next,
        taskId: taskId,
        expectedSnapshot: bundle.snapshot,
      ),
    );
  });

  Future<void> exportTaskToOrdinary(String taskId) => _operation(() async {
    _requireUnlocked();
    final bundle = _collectTask(taskId);
    await _persist(
      _contentWith(
        _documents
            .where((doc) => !bundle.removedKeys.contains(doc.key))
            .toList(),
      ),
      runtime: _currentWorkspaceRuntime,
      commit: (account, old, next) => _storage!.commitPrivateExport(
        account,
        expectedEnvelope: old,
        envelope: next,
        documents: bundle.documents,
      ),
    );
  });

  Future<void> changePassword(
    String oldPassword,
    String password,
    String confirmation,
  ) => _operation(() async {
    _requireUnlocked();
    _validatePassword(password, confirmation);
    final account = _accountId!;
    final epoch = _epoch;
    final old = _stored!.envelope;
    final checkKey = await _crypto.derive(oldPassword, _envelope!.salt);
    try {
      await _crypto.decrypt(_envelope!, checkKey);
    } on SecretBoxAuthenticationError {
      _stored = await _storage!.recordPrivateVaultFailure(account);
      lock();
      throw const PrivateVaultException('旧密码错误，私密任务箱已锁定。');
    } finally {
      checkKey.destroy();
    }
    _checkEpoch(epoch, account);
    final salt = _crypto.newSalt();
    final key = await _crypto.derive(password, salt);
    var retained = false;
    try {
      _checkEpoch(epoch, account);
      final next = await _crypto.encrypt(
        _content!.encode(),
        key: key,
        salt: salt,
        runtime: _currentWorkspaceRuntime?.toJson(),
      );
      _checkEpoch(epoch, account);
      await _storage!.writePrivateVault(
        account,
        next.encode(),
        expectedEnvelope: old,
      );
      _checkEpoch(epoch, account);
      _key!.destroy();
      _key = key;
      _envelope = next;
      _stored = PrivateVaultStoredState(envelope: next.encode());
      retained = true;
    } finally {
      if (!retained) key.destroy();
    }
  });

  Future<String> exportEncryptedBackup() => _operation(() async {
    final state = await _storage!.readPrivateVault(_accountId!);
    if (state == null) throw const PrivateVaultException('此工作区没有私密任务箱。');
    PrivateVaultEnvelope.decode(state.envelope);
    return state.envelope;
  });

  /// Authentication and payload validation finish before any workspace is made.
  Future<String> restoreEncryptedBackup(
    String encoded,
    String password,
  ) => _operation(() async {
    final envelope = PrivateVaultEnvelope.decode(encoded);
    final epoch = _epoch;
    final account = _accountId!;
    final key = await _crypto.derive(password, envelope.salt);
    try {
      final content = WorkspaceArchive.decode(
        await _crypto.decrypt(envelope, key),
      );
      if (content.privateVault != null) {
        throw const FormatException('Nested private vault.');
      }
      _checkEpoch(epoch, account);
      // Portable backups restore records, never an active timer from a device.
      final documents = _finishedBackupSessions(content.documents);
      final sealed = await _crypto.encrypt(
        _contentWith(documents).encode(),
        key: key,
        salt: envelope.salt,
      );
      _checkEpoch(epoch, account);
      final id = '__local__:${_uuid.v4()}';
      await _storage!.restorePrivateVault(id, sealed.encode());
      return id;
    } on SecretBoxAuthenticationError {
      throw const PrivateVaultException('密码错误或私密备份已损坏，未恢复任何数据。');
    } finally {
      key.destroy();
    }
  });

  PrivateFocusRuntime? get _currentWorkspaceRuntime =>
      _runtimeAccountId == _accountId ? _runtime : null;

  Future<void> startFocus(String taskId, int durationMinutes) =>
      _operation(() async {
        _requireUnlocked();
        if (hasActiveFocus || !(canStartFocus?.call() ?? true)) {
          throw const PrivateVaultException('已有专注正在进行，请先结束。');
        }
        if (durationMinutes < 1 || durationMinutes > 1440) {
          throw const PrivateVaultException('专注时长须为 1 至 1440 分钟。');
        }
        final task = tasks.where((task) => task.id == taskId).firstOrNull;
        if (task == null || task.status != TaskStatus.open) {
          throw const PrivateVaultException('请选择待办状态的私密任务。');
        }
        final now = DateTime.now();
        final session = FocusSessionItem(
          id: _uuid.v4(),
          taskId: task.id,
          plannedDurationSeconds: durationMinutes * 60,
          startedAt: now,
          startedDeviceId: 'private-local',
          status: FocusSessionStatus.running,
          timeZone: now.timeZoneName,
        );
        final runtime = PrivateFocusRuntime(
          sessionId: session.id,
          startedAt: now,
          endsAt: now.add(Duration(minutes: durationMinutes)),
        );
        final account = _accountId!;
        var committed = false;
        try {
          await _persist(
            _contentWith([
              ..._documents,
              _document('focus_session', session.id, session.toBody()),
            ]),
            runtime: runtime,
            onCommitted: () {
              committed = true;
              _runtime = runtime;
              _runtimeAccountId = account;
              _startTicker();
            },
          );
        } finally {
          if (committed) await _notifyRuntime();
        }
      });

  Future<void> stopFocus() => _operation(() async {
    _requireUnlocked();
    if (_runtimeAccountId != _accountId || _runtime == null) return;
    final runtime = _runtime!;
    final now = DateTime.now();
    final session = focusSessions
        .where((session) => session.id == runtime.sessionId)
        .firstOrNull;
    if (session == null) throw const PrivateVaultException('专注记录缺失。');
    final completed = !now.isBefore(runtime.endsAt);
    final updated = session.copyWith(
      endedAt: completed ? runtime.endsAt : now,
      actualDurationSeconds: now
          .difference(session.startedAt)
          .inSeconds
          .clamp(0, session.plannedDurationSeconds),
      status: completed
          ? FocusSessionStatus.completed
          : FocusSessionStatus.abandoned,
      terminationReason: completed ? 'timer_finished' : 'user_ended',
    );
    var committed = false;
    try {
      await _persist(
        _contentWith([
          ..._documents.where(
            (doc) => doc.key != 'focus_session\u0000${session.id}',
          ),
          _document('focus_session', updated.id, updated.toBody()),
        ]),
        onCommitted: () {
          committed = true;
          _runtime = null;
          _runtimeAccountId = null;
          _ticker?.cancel();
        },
      );
    } finally {
      if (committed) await _notifyRuntime();
    }
  });

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_runtime == null) {
        _ticker?.cancel();
        return;
      }
      if (!DateTime.now().isBefore(_runtime!.endsAt)) {
        if (isUnlocked && !_busy && _runtimeAccountId == _accountId) {
          unawaited(
            stopFocus().catchError((Object _) {
              timerWarning = '专注结果尚未保存，请重新解锁后重试。';
              _changed();
            }),
          );
        } else if (!_busy) {
          // Keep the timer reserved until the generic native stop has finished.
          unawaited(_finishLockedRuntime());
        }
      }
      _changed();
    });
  }

  Future<void> _finishLockedRuntime() async {
    if (_busy) return;
    _busy = true;
    _ticker?.cancel();
    try {
      await onFocusRuntimeChanged?.call(null);
      _runtime = null;
      _runtimeAccountId = null;
    } catch (_) {
      timerWarning = '系统计时通知未更新，请重新打开应用后检查。';
      _runtime = null;
      _runtimeAccountId = null;
    } finally {
      _busy = false;
      _changed();
    }
  }

  Future<void> _reconcileFocus() async {
    final finished = focusSessions
        .where(
          (session) =>
              session.isActive &&
              !DateTime.now().isBefore(
                session.startedAt.add(
                  Duration(seconds: session.plannedDurationSeconds),
                ),
              ),
        )
        .toList();
    if (finished.isEmpty) return;
    final ids = finished.map((session) => session.id).toSet();
    final updated = finished.map(
      (session) => session.copyWith(
        endedAt: session.startedAt.add(
          Duration(seconds: session.plannedDurationSeconds),
        ),
        actualDurationSeconds: session.plannedDurationSeconds,
        status: FocusSessionStatus.completed,
        terminationReason: 'timer_finished',
      ),
    );
    await _persist(
      _contentWith([
        ..._documents.where(
          (doc) => doc.entityType != 'focus_session' || !ids.contains(doc.id),
        ),
        ...updated.map(
          (session) => _document('focus_session', session.id, session.toBody()),
        ),
      ]),
      runtime: _currentWorkspaceRuntime,
    );
  }

  Future<void> _notifyRuntime() async {
    try {
      await onFocusRuntimeChanged?.call(_runtime);
      timerWarning = null;
    } catch (_) {
      timerWarning = '系统计时通知未更新，应用内计时仍按结束时间计算。';
    }
    _changed();
  }

  Future<void> retryNativeFocus() => _notifyRuntime();

  List<ArchiveDocument> _finishedBackupSessions(
    List<ArchiveDocument> documents,
  ) => [
    for (final doc in documents)
      if (doc.entityType == 'focus_session' &&
          {'running', 'paused'}.contains(doc.body['status']))
        _document('focus_session', doc.id, {
          ...doc.body,
          'status': 'interrupted',
          'ended_at': DateTime.now().toUtc().toIso8601String(),
          'termination_reason': 'backup_restored',
        })
      else
        doc,
  ];

  ArchiveDocument _document(
    String type,
    String id,
    Map<String, Object?> body,
  ) => ArchiveDocument(
    entityType: type,
    id: id,
    body: body,
    updatedAt: DateTime.now().toUtc(),
    deleted: false,
  );

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _key?.destroy();
    _key = null;
    _content = null;
    super.dispose();
  }
}
