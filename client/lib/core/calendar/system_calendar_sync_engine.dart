import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/local_database.dart';
import '../../data/platform/system_calendar_gateway.dart';
import 'system_calendar_models.dart';
import 'system_calendar_privacy.dart';

/// Reconciles one explicitly connected calendar with ordinary plan documents.
/// Cross-provider commits are replayable: imported IDs and exported tokens are
/// deterministic, and a missing checkpoint never authorizes an overwrite.
class SystemCalendarSyncEngine {
  SystemCalendarSyncEngine({required this.store, required this.gateway});

  final DocumentStore store;
  final SystemCalendarGateway gateway;
  static const settingKey = 'system_calendar_sync_v1';
  static const installationSettingKey = 'system_calendar_installation_v1';
  static const _namespace = 'a2e2873e-97ae-5adc-b740-dc63ce881c03';
  static const _uuid = Uuid();
  Future<void> _tail = Future<void>.value();

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<SystemCalendarConfiguration> loadConfiguration(
    String accountId,
  ) async => (await _readState(accountId)).configuration;

  Future<void> configure(
    String accountId, {
    required bool enabled,
    SystemCalendarInfo? calendar,
    int pastDays = 30,
    int futureDays = 180,
  }) => _exclusive(() async {
    if (pastDays < 0 ||
        futureDays < 1 ||
        pastDays > 365 ||
        futureDays > 365 ||
        pastDays + futureDays + 1 > 400) {
      throw PlatformException(code: 'calendar_invalid_window');
    }
    final state = await _readState(accountId);
    final selected = calendar ?? state.configuration.calendar;
    if (enabled && selected == null) {
      throw PlatformException(code: 'calendar_not_found');
    }
    state.configuration = SystemCalendarConfiguration(
      enabled: enabled,
      calendar: selected,
      pastDays: pastDays,
      futureDays: futureDays,
    );
    await _writeState(accountId, state);
  });

  Future<SystemCalendarSyncResult> sync({
    required String accountId,
    required bool Function() isCurrent,
    Map<String, SystemCalendarConflictChoice> resolutions = const {},
    DateTime? now,
  }) => _exclusive(() async {
    void check() {
      if (!isCurrent()) throw const SystemCalendarSyncCancelled();
    }

    check();
    final state = await _readState(accountId);
    check();
    final configuration = state.configuration;
    final selected = configuration.calendar;
    if (!configuration.enabled || selected == null) {
      return const SystemCalendarSyncResult();
    }
    final permissions = SystemCalendarPermissions.fromMap(
      await gateway.getPermissions(),
    );
    check();
    if (!permissions.supported) {
      throw PlatformException(code: 'calendar_unsupported');
    }
    if (!permissions.canRead) {
      throw PlatformException(code: 'calendar_permission_denied');
    }
    final calendars = (await gateway.listCalendars())
        .map(SystemCalendarInfo.fromMap)
        .toList();
    check();
    final matching = calendars.where((value) => value.id == selected.id);
    if (matching.isEmpty) {
      throw PlatformException(code: 'calendar_not_found');
    }
    final calendar = matching.single;
    if (calendar.fingerprint != selected.fingerprint) {
      throw PlatformException(code: 'calendar_changed');
    }
    state.configuration = SystemCalendarConfiguration(
      enabled: true,
      calendar: calendar,
      pastDays: configuration.pastDays,
      futureDays: configuration.futureDays,
    );
    if (state.scope == null) {
      state.scope = await _scope(accountId, check);
      check();
      await _writeState(accountId, state);
      check();
    }
    final scope = state.scope!;
    final exposures = decodeSystemCalendarExposure(
      await store.readSetting(calendarExposureSettingKey, accountId: accountId),
    );
    check();
    final date = now ?? DateTime.now();
    final start = DateTime(
      date.year,
      date.month,
      date.day - configuration.pastDays,
    );
    final end = DateTime(
      date.year,
      date.month,
      date.day + configuration.futureDays + 1,
    );
    final beforeRead = await _readPlans(accountId, state, calendar, check);
    final activeBindings = state.bindings
        .where((value) => value.calendarIdentity == calendar.identity)
        .toList();
    final linkedIds = activeBindings.map((value) => value.planId).toSet();
    final snapshot = await gateway.readEvents(
      calendarId: calendar.id,
      calendarFingerprint: calendar.fingerprint,
      fromMillis: start.millisecondsSinceEpoch,
      toMillis: end.millisecondsSinceEpoch,
      tracked: [
        for (final link in activeBindings) link.remote.toMap(),
        // Also find a successful create whose local checkpoint failed, even
        // when the calendar event subsequently moved outside the scan window.
        for (final plan in beforeRead.values)
          if (!linkedIds.contains(plan.id) &&
              plan.data != null &&
              _inWindow(plan.data!, start, end))
            {
              'id': '',
              'key': 'pending:${plan.id}',
              'appToken': _token(scope, plan.id),
            },
      ],
    );
    check();
    final rawEvents = snapshot['events'];
    final rawMissing = snapshot['missingKeys'];
    if (rawEvents is! List ||
        rawMissing is! List ||
        snapshot['complete'] != true ||
        rawEvents.length > 10000) {
      throw PlatformException(code: 'calendar_invalid_snapshot');
    }
    final events = rawEvents
        .map((value) => SystemCalendarEvent.fromMap(_map(value)))
        .toList();
    final missing = rawMissing.cast<String>().toSet();
    final byKey = <String, SystemCalendarEvent>{};
    final ownTokens = <String>{};
    for (final event in events) {
      if (event.calendarId != calendar.id ||
          byKey.containsKey(event.key) ||
          missing.contains(event.key)) {
        throw PlatformException(code: 'calendar_invalid_snapshot');
      }
      if (_ownPlanId(event.appToken, scope) != null &&
          !ownTokens.add(event.appToken!)) {
        throw PlatformException(code: 'calendar_conflict');
      }
      byKey[event.key] = event;
    }
    // The platform read may have taken time. Re-read ordinary data before any
    // reconciliation decision, and check it again at every mutating operation.
    final plans = await _readPlans(accountId, state, calendar, check);
    final context = _Run(
      engine: this,
      accountId: accountId,
      state: state,
      calendar: calendar,
      canWrite: permissions.canWrite && calendar.writable,
      check: check,
      exposures: exposures,
      resolutions: resolutions,
    );
    final handledKeys = <String>{};
    final handledPlans = <String>{};
    for (final link in activeBindings) {
      check();
      final remote = byKey[link.remote.key];
      handledKeys.add(link.remote.key);
      handledPlans.add(link.planId);
      if (remote == null && !missing.contains(link.remote.key)) {
        // Absence from a range query is not deletion evidence.
        context.skipped++;
        continue;
      }
      if (remote != null &&
          remote.appToken != null &&
          _ownPlanId(remote.appToken, scope) == null) {
        context.skipped++;
        continue;
      }
      await context.reconcile(link, plans[link.planId], remote);
    }

    for (final remote in events) {
      check();
      if (handledKeys.contains(remote.key)) continue;
      final ownPlanId = _ownPlanId(remote.appToken, scope);
      if (remote.appToken != null && ownPlanId == null) {
        context.skipped++;
        continue;
      }
      if (!remote.inWindow && ownPlanId == null) continue;
      if (!_representable(remote)) {
        context.skipped++;
        continue;
      }
      final planId =
          ownPlanId ??
          _uuid.v5(_namespace, '$scope|${calendar.identity}|${remote.key}');
      if (handledPlans.contains(planId)) {
        throw PlatformException(code: 'calendar_conflict');
      }
      handledPlans.add(planId);
      handledKeys.add(remote.key);
      final local = _recoverAllDay(plans[planId], remote);
      final link = _Binding(
        calendarIdentity: calendar.identity,
        planId: planId,
        remote: remote,
        baseLocal: local?.data ?? _localContent(remote),
        baseRemote: remote,
        localBody: local?.document.body ?? _newBody(remote),
        pending: true,
      );
      state.bindings.add(link);
      if (local != null || ownPlanId != null) {
        await context.reconcile(link, local, remote);
      } else {
        await context.importNew(link, remote);
      }
    }

    for (final plan in plans.values) {
      check();
      final data = plan.data;
      if (handledPlans.contains(plan.id) || data == null) continue;
      if (!_inWindow(data, start, end) || !_representable(data)) continue;
      if (!context.canWrite) {
        context.skipped++;
        continue;
      }
      await context.exportNew(plan);
    }
    check();
    // A failed checkpoint leaves replayable effects. Do not falsely advance
    // baselines in another workspace or erase the original failure on cleanup.
    state.lastSyncedAt = date.toUtc();
    await _writeState(accountId, state);
    check();
    return SystemCalendarSyncResult(
      imported: context.imported,
      exported: context.exported,
      updated: context.updated,
      deleted: context.deleted,
      skipped: context.skipped,
      conflicts: List.unmodifiable(context.conflicts),
      localChanged: context.localChanged,
      lastSyncedAt: state.lastSyncedAt,
    );
  });

  Future<_State> _readState(String accountId) async {
    final encoded = await store.readSetting(settingKey, accountId: accountId);
    if (encoded == null) return _State();
    try {
      final map = _map(jsonDecode(encoded));
      if (map['version'] != 1 || map['configuration'] is! Map) {
        throw const FormatException('Invalid calendar state.');
      }
      final links = (map['bindings']! as List)
          .map((value) => _Binding.fromMap(_map(value)))
          .toList();
      final keys = <String>{};
      for (final link in links) {
        if (!keys.add('${link.calendarIdentity}|${link.planId}')) {
          throw const FormatException('Duplicate calendar binding.');
        }
      }
      return _State(
        configuration: SystemCalendarConfiguration.fromMap(
          _map(map['configuration']),
        ),
        scope: map['scope'] as String?,
        bindings: links,
        lastSyncedAt: map['lastSyncedAt'] == null
            ? null
            : DateTime.parse(map['lastSyncedAt']! as String),
      );
    } catch (_) {
      throw PlatformException(code: 'calendar_state_invalid');
    }
  }

  Future<void> _writeState(String accountId, _State state) =>
      store.writeSetting(
        settingKey,
        jsonEncode(state.toMap()),
        accountId: accountId,
      );

  Future<String> _scope(String accountId, void Function() check) async {
    if (accountId.startsWith('server:')) {
      return _uuid.v5(_namespace, 'server|$accountId');
    }
    var installation = await store.readSetting(installationSettingKey);
    check();
    if (installation == null) {
      installation = _uuid.v4();
      await store.writeSetting(installationSettingKey, installation);
      check();
    }
    return _uuid.v5(_namespace, 'local|$installation|$accountId');
  }

  Future<Map<String, _LocalPlan>> _readPlans(
    String accountId,
    _State state,
    SystemCalendarInfo calendar,
    void Function() check,
  ) async {
    final documents = await store.readDocuments(
      'plan_block',
      accountId: accountId,
    );
    check();
    final tasks = await store.readDocuments('task', accountId: accountId);
    check();
    final byTask = {for (final task in tasks) task.id: task.body};
    final links = {
      for (final link in state.bindings)
        if (link.calendarIdentity == calendar.identity) link.planId: link,
    };
    return {
      for (final document in documents)
        document.id: _LocalPlan.fromDocument(
          document,
          byTask,
          links[document.id],
        ),
    };
  }
}

class _Run {
  _Run({
    required this.engine,
    required this.accountId,
    required this.state,
    required this.calendar,
    required this.canWrite,
    required this.check,
    required this.exposures,
    required this.resolutions,
  });

  final SystemCalendarSyncEngine engine;
  final String accountId;
  final _State state;
  final SystemCalendarInfo calendar;
  final bool canWrite;
  final void Function() check;
  final Set<String> exposures;
  final Map<String, SystemCalendarConflictChoice> resolutions;
  final conflicts = <SystemCalendarConflict>[];
  int imported = 0;
  int exported = 0;
  int updated = 0;
  int deleted = 0;
  int skipped = 0;
  bool localChanged = false;

  Future<void> reconcile(
    _Binding link,
    _LocalPlan? plan,
    SystemCalendarEvent? remote,
  ) async {
    final local = plan?.data;
    if (local == null && remote == null) {
      state.bindings.remove(link);
      return;
    }
    if (local == null || remote == null) {
      await _conflict(
        link,
        plan,
        remote,
        local == null
            ? SystemCalendarConflictKind.localDeleted
            : SystemCalendarConflictKind.remoteDeleted,
      );
      return;
    }
    if (!_representable(remote)) {
      await _conflict(
        link,
        plan,
        remote,
        SystemCalendarConflictKind.unsupported,
      );
      return;
    }
    final localChanged = !local.sameContent(link.baseLocal);
    // Cloud plans carry instants and a zone, but no shared date-only marker.
    // A different device's midnight must not silently turn an all-day event
    // into a timed event on this device.
    final allDayZoneChanged =
        link.remote.allDay &&
        localChanged &&
        local.timeZone != link.baseLocal.timeZone;
    if (_equivalent(local, remote) && !allDayZoneChanged) {
      link.accept(plan!, remote);
      return;
    }
    final remoteChanged = !remote.sameContent(link.baseRemote);
    if (link.pending || allDayZoneChanged || (localChanged && remoteChanged)) {
      await _conflict(
        link,
        plan,
        remote,
        SystemCalendarConflictKind.bothChanged,
      );
    } else if (remoteChanged) {
      await _takeSystem(link, plan, remote);
    } else if (localChanged) {
      if (!canWrite || !remote.writable) {
        await _conflict(
          link,
          plan,
          remote,
          SystemCalendarConflictKind.readOnly,
        );
      } else {
        await _takeLocal(link, plan!, remote);
      }
    } else {
      // Different baselines can legitimately represent an empty external title
      // using a stable em dash in the stricter local plan schema.
      link.remote = remote;
    }
  }

  Future<void> _conflict(
    _Binding link,
    _LocalPlan? plan,
    SystemCalendarEvent? remote,
    SystemCalendarConflictKind kind,
  ) async {
    final local = plan?.data;
    final canKeepClient =
        canWrite &&
        (remote?.writable ?? true) &&
        (local == null || _representable(local));
    final id = SystemCalendarSyncEngine._uuid.v5(
      SystemCalendarSyncEngine._namespace,
      jsonEncode([
        calendar.identity,
        link.planId,
        local?.toMap(),
        remote?.revision,
        remote?.key,
      ]),
    );
    final resolution = resolutions[id];
    if (resolution == SystemCalendarConflictChoice.local && canKeepClient) {
      if (local == null && remote != null) {
        await _markExposure(link.planId, plan);
        await _assertLocalUnchanged(link.planId, plan);
        check();
        await engine.gateway.deleteEvent(
          calendarId: calendar.id,
          calendarFingerprint: calendar.fingerprint,
          existing: remote.toMap(),
        );
        check();
        state.bindings.remove(link);
        deleted++;
      } else if (plan != null && local != null) {
        await _takeLocal(link, plan, remote);
      }
      return;
    }
    if (resolution == SystemCalendarConflictChoice.system &&
        (remote == null || _representable(remote))) {
      if (remote == null) {
        await _assertLocalUnchanged(link.planId, plan);
        check();
        await engine.store.deleteDocument(
          'plan_block',
          link.planId,
          accountId: accountId,
        );
        check();
        state.bindings.remove(link);
        localChanged = true;
        deleted++;
      } else {
        await _takeSystem(link, plan, remote);
      }
      return;
    }
    conflicts.add(
      SystemCalendarConflict(
        id: id,
        planId: link.planId,
        local: local,
        remote: remote,
        kind: kind,
        canKeepClient: canKeepClient,
      ),
    );
  }

  Future<void> importNew(_Binding link, SystemCalendarEvent remote) async {
    await _takeSystem(link, null, remote);
    imported++;
    updated--;
  }

  Future<void> exportNew(_LocalPlan plan) async {
    await _markExposure(plan.id, plan);
    await _assertLocalUnchanged(plan.id, plan);
    check();
    final remote = SystemCalendarEvent.fromMap(
      await engine.gateway.upsertEvent(
        calendarId: calendar.id,
        calendarFingerprint: calendar.fingerprint,
        event: plan.data!.toMap(),
        token: _token(state.scope!, plan.id),
      ),
    );
    check();
    _validateReturned(remote);
    final link = _Binding(
      calendarIdentity: calendar.identity,
      planId: plan.id,
      remote: remote,
      baseLocal: plan.data!,
      baseRemote: remote,
      localBody: Map.of(plan.document.body),
    );
    state.bindings.add(link);
    exported++;
  }

  Future<void> _takeLocal(
    _Binding link,
    _LocalPlan plan,
    SystemCalendarEvent? remote,
  ) async {
    await _markExposure(link.planId, plan);
    await _assertLocalUnchanged(link.planId, plan);
    check();
    var desired = plan.data!;
    if (link.baseRemote.title.isEmpty &&
        desired.title == link.baseLocal.title) {
      desired = SystemCalendarEventData(
        title: '',
        startsAtMillis: desired.startsAtMillis,
        endsAtMillis: desired.endsAtMillis,
        timeZone: desired.timeZone,
        allDay: desired.allDay,
      );
    }
    final saved = SystemCalendarEvent.fromMap(
      await engine.gateway.upsertEvent(
        calendarId: calendar.id,
        calendarFingerprint: calendar.fingerprint,
        event: desired.toMap(),
        existing: remote?.toMap(),
        token: _token(state.scope!, link.planId),
      ),
    );
    check();
    _validateReturned(saved);
    link.accept(plan, saved);
    updated++;
  }

  Future<void> _takeSystem(
    _Binding link,
    _LocalPlan? plan,
    SystemCalendarEvent remote,
  ) async {
    await _markExposure(link.planId, plan);
    await _assertLocalUnchanged(link.planId, plan);
    check();
    final body = {
      ...link.localBody,
      ...?plan?.document.body,
      'title': _localContent(remote).title,
      'starts_at': remote.startsAt.toUtc().toIso8601String(),
      'ends_at': remote.endsAt.toUtc().toIso8601String(),
      'time_zone': remote.timeZone,
      'status': plan?.data == null
          ? 'scheduled'
          : plan!.document.body['status'] ?? 'scheduled',
    };
    // A linked task may have been removed after the plan itself was deleted.
    // Restoring calendar content does not restore or invent that task.
    final taskId = body['task_id'];
    if (taskId != null) {
      final tasks = await engine.store.readDocuments(
        'task',
        accountId: accountId,
      );
      check();
      if (!tasks.any((task) => task.id == taskId)) body['task_id'] = null;
      await _assertLocalUnchanged(link.planId, plan);
    }
    check();
    await engine.store.putDocument(
      'plan_block',
      link.planId,
      body,
      accountId: accountId,
    );
    check();
    link
      ..remote = remote
      ..baseLocal = _localContent(remote)
      ..baseRemote = remote
      ..localBody = body
      ..pending = false;
    localChanged = true;
    updated++;
  }

  Future<void> _markExposure(String planId, _LocalPlan? plan) async {
    check();
    final values = {
      'plan_block\u0000$planId',
      if (plan?.document.body['task_id'] case final String taskId)
        'task\u0000$taskId',
    };
    if (exposures.containsAll(values)) return;
    final next = {...exposures, ...values};
    await engine.store.writeSetting(
      calendarExposureSettingKey,
      encodeSystemCalendarExposure(next),
      accountId: accountId,
    );
    check();
    exposures.addAll(values);
  }

  Future<void> _assertLocalUnchanged(
    String planId,
    _LocalPlan? expected,
  ) async {
    check();
    final current = (await engine._readPlans(
      accountId,
      state,
      calendar,
      check,
    ))[planId];
    check();
    if (jsonEncode(current?.document.body) !=
            jsonEncode(expected?.document.body) ||
        !_sameNullable(current?.data, expected?.data)) {
      throw PlatformException(code: 'calendar_conflict');
    }
  }

  void _validateReturned(SystemCalendarEvent event) {
    if (event.calendarId != calendar.id || !_representable(event)) {
      throw PlatformException(code: 'calendar_invalid_snapshot');
    }
  }
}

class _LocalPlan {
  _LocalPlan(this.document, this.data);

  factory _LocalPlan.fromDocument(
    StoredDocument document,
    Map<String, Map<String, Object?>> tasks,
    _Binding? binding,
  ) {
    final body = document.body;
    if (body['status'] == 'cancelled') return _LocalPlan(document, null);
    final title =
        body['title'] as String? ??
        tasks[body['task_id']]?['title'] as String? ??
        '';
    final starts = DateTime.parse(body['starts_at']! as String).toLocal();
    final ends = DateTime.parse(body['ends_at']! as String).toLocal();
    final unchangedTimes =
        binding != null &&
        starts.millisecondsSinceEpoch == binding.baseLocal.startsAtMillis &&
        ends.millisecondsSinceEpoch == binding.baseLocal.endsAtMillis;
    final allDay =
        binding?.remote.allDay == true &&
        (unchangedTimes || (_midnight(starts) && _midnight(ends)));
    return _LocalPlan(
      document,
      SystemCalendarEventData(
        title: title,
        startsAtMillis: starts.millisecondsSinceEpoch,
        endsAtMillis: ends.millisecondsSinceEpoch,
        timeZone: body['time_zone'] as String? ?? 'UTC',
        allDay: allDay,
      ),
    );
  }

  final StoredDocument document;
  final SystemCalendarEventData? data;
  String get id => document.id;
}

class _State {
  _State({
    this.configuration = const SystemCalendarConfiguration(),
    this.scope,
    List<_Binding>? bindings,
    this.lastSyncedAt,
  }) : bindings = bindings ?? [];

  SystemCalendarConfiguration configuration;
  String? scope;
  final List<_Binding> bindings;
  DateTime? lastSyncedAt;

  Map<String, Object?> toMap() => {
    'version': 1,
    'configuration': configuration.toMap(),
    'scope': scope,
    'bindings': bindings.map((value) => value.toMap()).toList(),
    'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
  };
}

class _Binding {
  _Binding({
    required this.calendarIdentity,
    required this.planId,
    required this.remote,
    required this.baseLocal,
    required this.baseRemote,
    required this.localBody,
    this.pending = false,
  });

  factory _Binding.fromMap(Map<String, Object?> map) => _Binding(
    calendarIdentity: map['calendarIdentity']! as String,
    planId: map['planId']! as String,
    remote: SystemCalendarEvent.fromMap(_map(map['remote'])),
    baseLocal: SystemCalendarEventData.fromMap(_map(map['baseLocal'])),
    baseRemote: SystemCalendarEventData.fromMap(_map(map['baseRemote'])),
    localBody: _map(map['localBody']),
    pending: map['pending'] == true,
  );

  final String calendarIdentity;
  final String planId;
  SystemCalendarEvent remote;
  SystemCalendarEventData baseLocal;
  SystemCalendarEventData baseRemote;
  Map<String, Object?> localBody;
  bool pending;

  void accept(_LocalPlan local, SystemCalendarEvent external) {
    remote = external;
    baseLocal = local.data!;
    baseRemote = external;
    localBody = Map.of(local.document.body);
    pending = false;
  }

  Map<String, Object?> toMap() => {
    'calendarIdentity': calendarIdentity,
    'planId': planId,
    'remote': remote.toMap(),
    'baseLocal': baseLocal.toMap(),
    'baseRemote': baseRemote.toMap(),
    'localBody': localBody,
    'pending': pending,
  };
}

String _token(String scope, String planId) =>
    'pactick://calendar/$scope/$planId';

String? _ownPlanId(String? token, String scope) {
  if (token == null) return null;
  final uri = Uri.tryParse(token);
  if (uri == null ||
      uri.scheme != 'pactick' ||
      uri.host != 'calendar' ||
      uri.pathSegments.length != 2 ||
      uri.pathSegments[0] != scope ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(uri.pathSegments[1])) {
    return null;
  }
  return uri.pathSegments[1];
}

bool _midnight(DateTime value) =>
    value.hour == 0 &&
    value.minute == 0 &&
    value.second == 0 &&
    value.millisecond == 0 &&
    value.microsecond == 0;

bool _representable(SystemCalendarEventData data) =>
    systemCalendarEventRepresentable(data);

bool _inWindow(SystemCalendarEventData data, DateTime from, DateTime to) =>
    data.endsAtMillis > from.millisecondsSinceEpoch &&
    data.startsAtMillis < to.millisecondsSinceEpoch;

SystemCalendarEventData _localContent(SystemCalendarEventData value) =>
    SystemCalendarEventData(
      title: value.title.isEmpty ? '—' : value.title,
      startsAtMillis: value.startsAtMillis,
      endsAtMillis: value.endsAtMillis,
      timeZone: value.timeZone,
      allDay: value.allDay,
    );

bool _equivalent(
  SystemCalendarEventData local,
  SystemCalendarEventData remote,
) => local.sameContent(_localContent(remote));

bool _sameNullable(SystemCalendarEventData? a, SystemCalendarEventData? b) =>
    a == null ? b == null : b != null && a.sameContent(b);

_LocalPlan? _recoverAllDay(_LocalPlan? plan, SystemCalendarEvent remote) {
  final data = plan?.data;
  if (plan == null ||
      data == null ||
      !remote.allDay ||
      !_midnight(data.startsAt) ||
      !_midnight(data.endsAt)) {
    return plan;
  }
  return _LocalPlan(
    plan.document,
    SystemCalendarEventData(
      title: data.title,
      startsAtMillis: data.startsAtMillis,
      endsAtMillis: data.endsAtMillis,
      timeZone: data.timeZone,
      allDay: true,
    ),
  );
}

Map<String, Object?> _newBody(SystemCalendarEvent remote) => {
  'task_id': null,
  'title': _localContent(remote).title,
  'starts_at': remote.startsAt.toUtc().toIso8601String(),
  'ends_at': remote.endsAt.toUtc().toIso8601String(),
  'time_zone': remote.timeZone,
  'status': 'scheduled',
  'original_plan_block_id': null,
};

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map);
