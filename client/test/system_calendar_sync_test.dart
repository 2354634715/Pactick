import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/calendar/system_calendar_models.dart';
import 'package:pactick/core/calendar/system_calendar_privacy.dart';
import 'package:pactick/core/calendar/system_calendar_sync_engine.dart';
import 'package:pactick/core/models/domain_models.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/system_calendar_gateway.dart';

const account = '__local__';
const planId = '11111111-1111-4111-8111-111111111111';
const taskId = '22222222-2222-4222-8222-222222222222';
final today = DateTime(2026, 10, 31, 10);
const calendar = SystemCalendarInfo(
  id: '1',
  fingerprint: 'calendar-owner-and-account-hash',
  displayName: '使用者的日历',
  accountLabel: '演示账户',
  writable: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Store store;
  late _Calendar provider;
  late SystemCalendarSyncEngine engine;

  setUp(() {
    store = _Store();
    provider = _Calendar();
    engine = SystemCalendarSyncEngine(store: store, gateway: provider);
  });

  Future<SystemCalendarSyncResult> sync({
    Map<String, SystemCalendarConflictChoice> resolutions = const {},
    bool Function()? isCurrent,
  }) => engine.sync(
    accountId: account,
    now: today,
    isCurrent: isCurrent ?? () => true,
    resolutions: resolutions,
  );

  Future<void> enable() =>
      engine.configure(account, enabled: true, calendar: calendar);

  test('disabled connection never queries the provider', () async {
    final configuration = await engine.loadConfiguration(account);
    expect(configuration.enabled, isFalse);
    expect(configuration.pastDays, 30);
    expect(configuration.futureDays, 180);
    expect((await sync()).localChanged, isFalse);
    expect(provider.permissionReads, 0);
  });

  test(
    'first sync imports external events and exports ordinary plans once',
    () async {
      await _plan(store, title: '本地日程原文');
      provider.add(_event(title: '系统日程原文'));
      await enable();
      final first = await sync();
      expect(first.imported, 1);
      expect(first.exported, 1);
      expect(first.conflicts, isEmpty);
      expect(
        (await store.readDocuments('plan_block')).map((p) => p.body['title']),
        containsAll(['本地日程原文', '系统日程原文']),
      );
      expect(
        provider.events.values.map((e) => e.title),
        containsAll(['本地日程原文', '系统日程原文']),
      );
      expect(provider.created, 1);
      final second = await sync();
      expect(second.imported + second.exported + second.updated, 0);
      expect(provider.created, 1);
      expect(await store.readDocuments('plan_block'), hasLength(2));
    },
  );

  test(
    'one-sided edits propagate while event-only metadata stays untouched',
    () async {
      provider.add(_event(title: '系统原文'));
      provider.sideMetadata['100'] = {
        'description': '私人备注',
        'location': '地址',
        'reminders': [10],
      };
      await enable();
      await sync();
      var imported = (await store.readDocuments('plan_block')).single;
      provider.change('100', {
        'title': '系统新标题',
        'startsAtMillis': today
            .add(const Duration(hours: 2))
            .millisecondsSinceEpoch,
        'endsAtMillis': today
            .add(const Duration(hours: 3))
            .millisecondsSinceEpoch,
      });
      expect((await sync()).updated, 1);
      imported = (await store.readDocuments('plan_block')).single;
      expect(imported.body['title'], '系统新标题');
      await store.putDocument('plan_block', imported.id, {
        ...imported.body,
        'title': '客户端改名',
      });
      expect((await sync()).updated, 1);
      expect(provider.events['100']!.title, '客户端改名');
      expect(provider.sideMetadata['100'], {
        'description': '私人备注',
        'location': '地址',
        'reminders': [10],
      });
      expect(
        provider.lastDesired!.keys,
        unorderedEquals([
          'title',
          'startsAtMillis',
          'endsAtMillis',
          'timeZone',
          'allDay',
        ]),
      );
      expect(
        provider.events['100']!.appToken,
        isNull,
        reason:
            'editing an external event must not replace its custom app link',
      );
    },
  );

  test(
    'divergent edits require an explicit choice and stale choices do not apply',
    () async {
      await _plan(store, title: '基线');
      await enable();
      await sync();
      var local = (await store.readDocuments('plan_block')).single;
      await store.putDocument('plan_block', planId, {
        ...local.body,
        'title': '本机修改',
      });
      final key = provider.events.keys.single;
      provider.change(key, {'title': '系统修改'});
      final conflict = (await sync()).conflicts.single;
      expect(conflict.kind, SystemCalendarConflictKind.bothChanged);
      expect(provider.events[key]!.title, '系统修改');
      provider.change(key, {'title': '选择后又变化'});
      final stale = await sync(
        resolutions: {conflict.id: SystemCalendarConflictChoice.local},
      );
      expect(stale.conflicts, hasLength(1));
      expect(stale.conflicts.single.id, isNot(conflict.id));
      expect(provider.events[key]!.title, '选择后又变化');
      final taken = await sync(
        resolutions: {
          stale.conflicts.single.id: SystemCalendarConflictChoice.system,
        },
      );
      expect(taken.conflicts, isEmpty);
      local = (await store.readDocuments('plan_block')).single;
      expect(local.body['title'], '选择后又变化');

      await store.putDocument('plan_block', planId, {
        ...local.body,
        'title': '保留本机',
      });
      provider.change(key, {'title': '另一个系统修改'});
      final next = (await sync()).conflicts.single;
      await sync(resolutions: {next.id: SystemCalendarConflictChoice.local});
      expect(provider.events[key]!.title, '保留本机');
    },
  );

  test(
    'range omission is not deletion; confirmed deletion needs review',
    () async {
      await _task(store);
      await _plan(store, title: null, linkedTaskId: taskId);
      await enable();
      await sync();
      final key = provider.events.keys.single;
      final old = provider.events.remove(key)!;
      provider.omitMissing = true;
      expect((await sync()).conflicts, isEmpty);
      expect(await store.readDocuments('plan_block'), hasLength(1));
      provider.omitMissing = false;
      final missing = (await sync()).conflicts.single;
      expect(missing.kind, SystemCalendarConflictKind.remoteDeleted);
      expect(await store.readDocuments('plan_block'), hasLength(1));
      await sync(
        resolutions: {missing.id: SystemCalendarConflictChoice.system},
      );
      expect(await store.readDocuments('plan_block'), isEmpty);
      expect(await store.readDocuments('task'), hasLength(1));
      expect(old.appToken, isNotNull);
    },
  );

  test(
    'local deletion never deletes the external event without a choice',
    () async {
      provider.add(_event(title: '需保留的系统事件'));
      await enable();
      await sync();
      final local = (await store.readDocuments('plan_block')).single;
      await store.deleteDocument('plan_block', local.id);
      final conflict = (await sync()).conflicts.single;
      expect(conflict.kind, SystemCalendarConflictKind.localDeleted);
      expect(provider.deleted, 0);
      await sync(
        resolutions: {conflict.id: SystemCalendarConflictChoice.local},
      );
      expect(provider.deleted, 1);
      expect(provider.events, isEmpty);
      expect((await sync()).imported, 0);
    },
  );

  test(
    'read-only calendars import but do not silently discard local edits',
    () async {
      provider.writeGranted = false;
      provider.add(_event(title: '只读来源'));
      await enable();
      expect((await sync()).imported, 1);
      final local = (await store.readDocuments('plan_block')).single;
      await store.putDocument('plan_block', local.id, {
        ...local.body,
        'title': '本机草稿',
      });
      final conflict = (await sync()).conflicts.single;
      expect(conflict.kind, SystemCalendarConflictKind.readOnly);
      expect(conflict.canKeepClient, isFalse);
      expect(provider.updated, 0);
      expect(
        (await store.readDocuments('plan_block')).single.body['title'],
        '本机草稿',
      );
      await sync(
        resolutions: {conflict.id: SystemCalendarConflictChoice.system},
      );
      expect(
        (await store.readDocuments('plan_block')).single.body['title'],
        '只读来源',
      );
    },
  );

  test(
    'revoked permissions and changed calendar identities stop before writes',
    () async {
      await _plan(store);
      await enable();
      provider.readGranted = false;
      await expectLater(sync(), throwsA(_code('calendar_permission_denied')));
      expect(provider.created, 0);
      provider.readGranted = true;
      provider.calendarFingerprint = 'different-owner';
      await expectLater(sync(), throwsA(_code('calendar_changed')));
      expect(provider.reads, 0);
    },
  );

  for (final complete in <bool?>[false, null]) {
    test(
      'snapshot complete=$complete cannot cause imports, exports, or deletion',
      () async {
        await _plan(store);
        provider.add(_event());
        provider.complete = complete;
        await enable();
        await expectLater(sync(), throwsA(_code('calendar_invalid_snapshot')));
        expect(provider.created, 0);
        expect(provider.updated, 0);
        expect(provider.deleted, 0);
        expect(await store.readDocuments('plan_block'), hasLength(1));
      },
    );
  }

  test(
    'successful provider create survives failed checkpoint without duplicates',
    () async {
      await _plan(store, title: '第一次写入');
      await enable();
      store.failCheckpoint = true;
      await expectLater(sync(), throwsStateError);
      expect(provider.created, 1);
      expect(provider.events, hasLength(1));
      store.failCheckpoint = false;
      // The event moved away while the client checkpoint was unavailable.
      final key = provider.events.keys.single;
      provider.change(key, {
        'startsAtMillis': today
            .add(const Duration(days: 500))
            .millisecondsSinceEpoch,
        'endsAtMillis': today
            .add(const Duration(days: 500, hours: 1))
            .millisecondsSinceEpoch,
      });
      final recovered = await sync();
      expect(provider.created, 1);
      expect(recovered.conflicts, hasLength(1));
      await sync(
        resolutions: {
          recovered.conflicts.single.id: SystemCalendarConflictChoice.local,
        },
      );
      expect(provider.created, 1);
      expect(
        provider.events[key]!.startsAtMillis,
        today.millisecondsSinceEpoch,
      );
    },
  );

  test('imported deterministic ID survives a checkpoint failure and preserves edits', () async {
    provider.add(_event(title: '外部标题'));
    await enable();
    store.failCheckpoint = true;
    await expectLater(sync(), throwsStateError);
    final imported = (await store.readDocuments('plan_block')).single;
    await store.putDocument('plan_block', imported.id, {
      ...imported.body,
      'title': '失败后编辑',
    });
    store.failCheckpoint = false;
    final result = await sync();
    expect(await store.readDocuments('plan_block'), hasLength(1));
    expect(result.conflicts, hasLength(1));
    expect(
      (await store.readDocuments('plan_block')).single.body['title'],
      '失败后编辑',
    );
  });

  test('late snapshot is ignored after switching workspace', () async {
    await _plan(store);
    await enable();
    var current = true;
    final wait = Completer<void>();
    final entered = Completer<void>();
    provider.beforeReadReturns = () async {
      entered.complete();
      await wait.future;
    };
    final pending = sync(isCurrent: () => current);
    await entered.future;
    await store.ensureAccount('other-account');
    current = false;
    wait.complete();
    await expectLater(pending, throwsA(isA<SystemCalendarSyncCancelled>()));
    expect(provider.created, 0);
    expect(
      await store.readDocuments('plan_block', accountId: 'other-account'),
      isEmpty,
    );
  });

  test(
    'local edits during provider read participate in the conflict',
    () async {
      await _plan(store, title: '共同基线');
      await enable();
      await sync();
      provider.change(provider.events.keys.single, {'title': '系统新值'});
      provider.beforeReadReturns = () async {
        final local = (await store.readDocuments('plan_block')).single;
        await store.putDocument('plan_block', planId, {
          ...local.body,
          'title': '读取时的本机编辑',
        });
      };
      final result = await sync();
      expect(result.conflicts.single.local!.title, '读取时的本机编辑');
      expect(
        (await store.readDocuments('plan_block')).single.body['title'],
        '读取时的本机编辑',
      );
      expect(provider.events.values.single.title, '系统新值');
    },
  );

  test(
    'exposure is durable before writes and failed exposure prevents publishing',
    () async {
      await _task(store);
      await _plan(store, title: null, linkedTaskId: taskId);
      await enable();
      store.failExposure = true;
      await expectLater(sync(), throwsStateError);
      expect(provider.created, 0);
      store.failExposure = false;
      provider.beforeWrite = () async {
        final exposed = decodeSystemCalendarExposure(
          await store.readSetting(calendarExposureSettingKey),
        );
        expect(
          exposed,
          containsAll(['plan_block\u0000$planId', 'task\u0000$taskId']),
        );
      };
      await sync();
      provider.beforeWrite = null;
      expect(provider.events.values.single.title, '用户中文标题');
      expect(provider.lastDesired.toString(), isNot(contains('备注不写入')));
      await engine.configure(account, enabled: false);
      expect(
        decodeSystemCalendarExposure(
          await store.readSetting(calendarExposureSettingKey),
        ),
        contains('task\u0000$taskId'),
      );
    },
  );

  test(
    'a local change after exposure marking is never overwritten or exported',
    () async {
      await _plan(store, title: '标记前');
      await enable();
      store.afterExposure = () async {
        final local = (await store.readDocuments('plan_block')).single;
        await store.putDocument('plan_block', planId, {
          ...local.body,
          'title': '标记后编辑',
        });
      };
      await expectLater(sync(), throwsA(_code('calendar_conflict')));
      expect(provider.created, 0);
      expect(
        (await store.readDocuments('plan_block')).single.body['title'],
        '标记后编辑',
      );
    },
  );

  test(
    'metadata stays out of backups and ordinary synchronization patches',
    () async {
      provider.add(_event(title: '用户数据原文'));
      await enable();
      await sync();
      final archive = await store.exportWorkspace(account);
      expect(
        archive.settings.keys,
        isNot(contains(SystemCalendarSyncEngine.settingKey)),
      );
      expect(
        archive.settings.keys,
        isNot(contains(calendarExposureSettingKey)),
      );
      expect(
        archive.settings.keys,
        isNot(contains(SystemCalendarSyncEngine.installationSettingKey)),
      );
      final operations = await store.readPendingOperations(account);
      for (final operation in operations) {
        expect(
          operation.patch?.keys.toSet().intersection({
            'calendarId',
            'appToken',
            'revision',
            'fingerprint',
          }),
          isEmpty,
        );
      }
      expect(store.readTypes.toSet(), {'plan_block', 'task'});
    },
  );

  test(
    'recurring instances retain identity and unsupported spans are skipped',
    () async {
      provider.add(_event(key: 'series:123', recurring: true));
      provider.add(
        _event(
          id: '200',
          title: '过长事件',
          ends: today.add(const Duration(days: 8)),
        ),
      );
      await enable();
      final first = await sync();
      expect(first.imported, 1);
      expect(first.skipped, 1);
      final local = (await store.readDocuments('plan_block')).single;
      await store.putDocument('plan_block', local.id, {
        ...local.body,
        'title': '仅改此实例',
      });
      await sync();
      expect(provider.events['series:123']!.title, '仅改此实例');
      expect(provider.events['series:123']!.key, 'series:123');
      expect(provider.events['200']!.title, '过长事件');
    },
  );

  test('empty titles use a stable placeholder without rewriting the provider title', () async {
    provider.add(_event(title: ''));
    await enable();
    await sync();
    var local = (await store.readDocuments('plan_block')).single;
    expect(local.body['title'], '—');
    expect((await sync()).updated, 0);
    await store.putDocument('plan_block', local.id, {
      ...local.body,
      'ends_at': today.add(const Duration(hours: 2)).toUtc().toIso8601String(),
    });
    await sync();
    expect(provider.events['100']!.title, '');
    local = (await store.readDocuments('plan_block')).single;
    expect(local.body['title'], '—');
  });

  test('foreign workspace tokens are not imported and binding configuration is isolated', () async {
    provider.add(
      _event(
        token:
            'pactick://calendar/foreign/33333333-3333-4333-8333-333333333333',
      ),
    );
    await enable();
    expect((await sync()).skipped, 1);
    expect(await store.readDocuments('plan_block'), isEmpty);
    await store.ensureAccount('server:https%3A%2F%2Fexample.test:user');
    expect(
      (await engine.loadConfiguration('server:https%3A%2F%2Fexample.test:user'))
          .enabled,
      isFalse,
    );
    await engine.configure(account, enabled: false);
    expect(provider.events, hasLength(1));
  });

  test(
    'corrupt exposure history fails closed without provider mutation',
    () async {
      await _plan(store);
      await enable();
      await store.writeSetting(calendarExposureSettingKey, '{broken');
      await expectLater(sync(), throwsFormatException);
      expect(provider.created, 0);
      expect(
        () => decodeSystemCalendarExposure('["unknown\\u0000x"]'),
        throwsFormatException,
      );
    },
  );

  test(
    'all-day instances retain their exclusive date end when moved',
    () async {
      final day = DateTime(2026, 10, 31);
      provider.add(
        SystemCalendarEvent.fromMap({
          ..._event().toMap(),
          'startsAtMillis': day.millisecondsSinceEpoch,
          'endsAtMillis': DateTime(2026, 11, 1).millisecondsSinceEpoch,
          'allDay': true,
        }),
      );
      await enable();
      await sync();
      final local = (await store.readDocuments('plan_block')).single;
      expect(
        DateTime.parse(local.body['ends_at']! as String).toLocal(),
        DateTime(2026, 11, 1),
      );
      expect((await sync()).updated, 0);
      await store.putDocument('plan_block', local.id, {
        ...local.body,
        'starts_at': DateTime(2026, 11, 1).toUtc().toIso8601String(),
        'ends_at': DateTime(2026, 11, 2).toUtc().toIso8601String(),
      });
      await sync();
      expect(provider.events['100']!.allDay, isTrue);
      expect(provider.events['100']!.startsAt, DateTime(2026, 11, 1));
      expect(provider.events['100']!.endsAt, DateTime(2026, 11, 2));
    },
  );

  test(
    'same cloud workspace recovers a tagged event without a second export',
    () async {
      const cloud = 'server:https%3A%2F%2Fcalendar.example.test:user';
      final firstStore = _Store();
      final secondStore = _Store();
      final body = PlanBlockItem(
        id: planId,
        title: '云端计划原文',
        startsAt: today,
        endsAt: today.add(const Duration(hours: 1)),
        timeZone: 'UTC',
        status: PlanBlockStatus.scheduled,
      ).toBody();
      await firstStore.putDocument(
        'plan_block',
        planId,
        body,
        accountId: cloud,
      );
      await secondStore.putDocument(
        'plan_block',
        planId,
        body,
        accountId: cloud,
      );
      final first = SystemCalendarSyncEngine(
        store: firstStore,
        gateway: provider,
      );
      final second = SystemCalendarSyncEngine(
        store: secondStore,
        gateway: provider,
      );
      await first.configure(cloud, enabled: true, calendar: calendar);
      await second.configure(cloud, enabled: true, calendar: calendar);
      await first.sync(accountId: cloud, now: today, isCurrent: () => true);
      final result = await second.sync(
        accountId: cloud,
        now: today,
        isCurrent: () => true,
      );
      expect(provider.created, 1);
      expect(result.conflicts, isEmpty);
      expect(result.exported, 0);
    },
  );

  test('a failed provider write retains the prior exposure history', () async {
    await _task(store);
    await _plan(store, title: null, linkedTaskId: taskId);
    await enable();
    provider.beforeWrite = () async =>
        throw PlatformException(code: 'calendar_operation_failed');
    await expectLater(sync(), throwsA(_code('calendar_operation_failed')));
    expect(provider.created, 0);
    expect(
      decodeSystemCalendarExposure(
        await store.readSetting(calendarExposureSettingKey),
      ),
      containsAll(['task\u0000$taskId', 'plan_block\u0000$planId']),
    );
  });

  test(
    'unsupported remote content disables only the unavailable resolution',
    () async {
      await _plan(store);
      await enable();
      await sync();
      provider.change(provider.events.keys.single, {
        'endsAtMillis': today
            .add(const Duration(days: 8))
            .millisecondsSinceEpoch,
      });
      final conflict = (await sync()).conflicts.single;
      expect(conflict.kind, SystemCalendarConflictKind.unsupported);
      expect(conflict.canKeepClient, isTrue);
      expect(conflict.canKeepSystem, isFalse);
      final ignored = await sync(
        resolutions: {conflict.id: SystemCalendarConflictChoice.system},
      );
      expect(ignored.conflicts.single.id, conflict.id);
      final accepted = await sync(
        resolutions: {conflict.id: SystemCalendarConflictChoice.local},
      );
      expect(accepted.conflicts, isEmpty);
      expect(
        provider.events.values.single.endsAtMillis -
            provider.events.values.single.startsAtMillis,
        const Duration(hours: 1).inMilliseconds,
      );
    },
  );

  test(
    'editing an imported all-day event to 09:00 writes a timed event',
    () async {
      provider.add(
        SystemCalendarEvent.fromMap({
          ..._event().toMap(),
          'startsAtMillis': DateTime(2026, 10, 31).millisecondsSinceEpoch,
          'endsAtMillis': DateTime(2026, 11, 1).millisecondsSinceEpoch,
          'allDay': true,
        }),
      );
      await enable();
      await sync();
      final local = (await store.readDocuments('plan_block')).single;
      await store.putDocument('plan_block', local.id, {
        ...local.body,
        'starts_at': DateTime(2026, 10, 31, 9).toUtc().toIso8601String(),
        'ends_at': DateTime(2026, 10, 31, 10).toUtc().toIso8601String(),
      });
      final result = await sync();
      expect(result.conflicts, isEmpty);
      expect(provider.events['100']!.allDay, isFalse);
      expect(provider.events['100']!.startsAt, DateTime(2026, 10, 31, 9));
      expect(provider.events['100']!.endsAt, DateTime(2026, 10, 31, 10));
      expect((await sync()).updated, 0);
    },
  );

  for (final choice in SystemCalendarConflictChoice.values) {
    test(
      'an all-day zone change requires confirmation before keeping ${choice.name}',
      () async {
        final original = SystemCalendarEvent.fromMap({
          ..._event().toMap(),
          'startsAtMillis': DateTime(2026, 10, 31).millisecondsSinceEpoch,
          'endsAtMillis': DateTime(2026, 11, 1).millisecondsSinceEpoch,
          'timeZone': 'Asia/Shanghai',
          'allDay': true,
        });
        provider.add(original);
        await enable();
        await sync();
        final local = (await store.readDocuments('plan_block')).single;
        // Another device stores the same calendar date using its own midnight.
        final shiftedStart = original.startsAt.add(const Duration(hours: 8));
        final shiftedEnd = original.endsAt.add(const Duration(hours: 8));
        await store.putDocument('plan_block', local.id, {
          ...local.body,
          'starts_at': shiftedStart.toUtc().toIso8601String(),
          'ends_at': shiftedEnd.toUtc().toIso8601String(),
          'time_zone': 'America/Los_Angeles',
        });
        final result = await sync();
        final conflict = result.conflicts.single;
        expect(conflict.kind, SystemCalendarConflictKind.bothChanged);
        expect(provider.updated, 0);
        expect(provider.events['100']!.sameContent(original), isTrue);
        final resolved = await sync(resolutions: {conflict.id: choice});
        expect(resolved.conflicts, isEmpty);
        if (choice == SystemCalendarConflictChoice.local) {
          expect(provider.updated, 1);
          expect(provider.events['100']!.allDay, isFalse);
          expect(provider.events['100']!.startsAt, shiftedStart);
        } else {
          expect(provider.updated, 0);
          expect(provider.events['100']!.sameContent(original), isTrue);
          final restored = (await store.readDocuments('plan_block')).single;
          expect(restored.body['time_zone'], original.timeZone);
          expect(
            DateTime.parse(restored.body['starts_at']! as String),
            original.startsAt.toUtc(),
          );
        }
        expect((await sync()).conflicts, isEmpty);
      },
    );
  }

  test(
    'a system title override retains the linked task and its original title',
    () async {
      await _task(store);
      await _plan(store, title: null, linkedTaskId: taskId);
      await enable();
      await sync();
      final key = provider.events.keys.single;
      provider.change(key, {'title': '系统里修改的日程名'});
      expect((await sync()).updated, 1);
      final plan = (await store.readDocuments('plan_block')).single;
      expect(plan.body['title'], '系统里修改的日程名');
      expect(plan.body['task_id'], taskId);
      expect(
        (await store.readDocuments('task')).single.body['title'],
        '用户中文标题',
      );
    },
  );

  test('all-day import can recover a lost binding checkpoint without a false conflict', () async {
    provider.add(
      SystemCalendarEvent.fromMap({
        ..._event().toMap(),
        'startsAtMillis': DateTime(2026, 10, 31).millisecondsSinceEpoch,
        'endsAtMillis': DateTime(2026, 11, 1).millisecondsSinceEpoch,
        'allDay': true,
      }),
    );
    await enable();
    store.failCheckpoint = true;
    await expectLater(sync(), throwsStateError);
    store.failCheckpoint = false;
    final result = await sync();
    expect(result.conflicts, isEmpty);
    expect(provider.created, 0);
    expect(await store.readDocuments('plan_block'), hasLength(1));
    expect((await sync()).updated, 0);
  });
}

Matcher _code(String code) =>
    isA<PlatformException>().having((error) => error.code, 'code', code);

Future<void> _task(DocumentStore store) => store.putDocument(
  'task',
  taskId,
  const TaskItem(
    id: taskId,
    title: '用户中文标题',
    note: '备注不写入系统日历',
    priority: TaskPriority.none,
    status: TaskStatus.open,
    rank: 0,
  ).toBody(),
);

Future<void> _plan(
  DocumentStore store, {
  String? title = '本机计划',
  String? linkedTaskId,
}) => store.putDocument(
  'plan_block',
  planId,
  PlanBlockItem(
    id: planId,
    title: title,
    taskId: linkedTaskId,
    startsAt: today,
    endsAt: today.add(const Duration(hours: 1)),
    timeZone: 'UTC',
    status: PlanBlockStatus.scheduled,
  ).toBody(),
);

SystemCalendarEvent _event({
  String id = '100',
  String? key,
  String title = '系统日程',
  DateTime? ends,
  bool recurring = false,
  String? token,
}) => SystemCalendarEvent(
  id: id,
  key: key ?? id,
  calendarId: calendar.id,
  title: title,
  startsAtMillis: today.millisecondsSinceEpoch,
  endsAtMillis:
      (ends ?? today.add(const Duration(hours: 1))).millisecondsSinceEpoch,
  timeZone: 'UTC',
  revision: 'revision-1',
  recurring: recurring,
  seriesId: recurring ? 'series' : null,
  originalStartMillis: recurring ? 123 : null,
  appToken: token,
);

class _Store extends MemoryDocumentStore {
  bool failCheckpoint = false;
  bool failExposure = false;
  Future<void> Function()? afterExposure;
  final readTypes = <String>[];

  @override
  Future<List<StoredDocument>> readDocuments(
    String entityType, {
    String accountId = DocumentStore.localAccountId,
  }) {
    readTypes.add(entityType);
    return super.readDocuments(entityType, accountId: accountId);
  }

  @override
  Future<void> writeSetting(
    String key,
    String value, {
    String accountId = DocumentStore.localAccountId,
  }) async {
    if (key == SystemCalendarSyncEngine.settingKey &&
        failCheckpoint &&
        (jsonDecode(value) as Map)['bindings'] is List &&
        ((jsonDecode(value) as Map)['bindings'] as List).isNotEmpty) {
      throw StateError('Injected checkpoint write failure');
    }
    if (key == calendarExposureSettingKey && failExposure) {
      throw StateError('Injected exposure write failure');
    }
    await super.writeSetting(key, value, accountId: accountId);
    if (key == calendarExposureSettingKey) {
      final callback = afterExposure;
      afterExposure = null;
      await callback?.call();
    }
  }
}

class _Calendar extends SystemCalendarGateway {
  final events = <String, SystemCalendarEvent>{};
  final sideMetadata = <String, Map<String, Object?>>{};
  bool readGranted = true;
  bool writeGranted = true;
  bool? complete = true;
  bool omitMissing = false;
  String calendarFingerprint = calendar.fingerprint;
  int permissionReads = 0;
  int reads = 0;
  int created = 0;
  int updated = 0;
  int deleted = 0;
  int revision = 1;
  int nextId = 1000;
  Map<String, Object?>? lastDesired;
  Future<void> Function()? beforeReadReturns;
  Future<void> Function()? beforeWrite;

  void add(SystemCalendarEvent event) => events[event.key] = event;
  void change(String key, Map<String, Object?> patch) {
    events[key] = SystemCalendarEvent.fromMap({
      ...events[key]!.toMap(),
      ...patch,
      'revision': 'revision-${++revision}',
    });
  }

  @override
  Future<Map<String, Object?>> getPermissions() async {
    permissionReads++;
    return {'supported': true, 'read': readGranted, 'write': writeGranted};
  }

  @override
  Future<List<Map<String, Object?>>> listCalendars() async => [
    {...calendar.toMap(), 'fingerprint': calendarFingerprint},
  ];

  @override
  Future<Map<String, Object?>> readEvents({
    required String calendarId,
    required String calendarFingerprint,
    required int fromMillis,
    required int toMillis,
    required List<Map<String, Object?>> tracked,
  }) async {
    reads++;
    final result = <String, SystemCalendarEvent>{};
    bool inWindow(SystemCalendarEvent event) =>
        event.startsAtMillis < toMillis && event.endsAtMillis > fromMillis;
    for (final event in events.values) {
      if (inWindow(event)) result[event.key] = event;
    }
    final missing = <String>[];
    for (final entry in tracked) {
      if (entry['id'] == '') {
        for (final event in events.values.where(
          (value) => value.appToken == entry['appToken'],
        )) {
          result[event.key] = event;
        }
      } else if (events[entry['key']] case final event?) {
        result[event.key] = event;
      } else if (!omitMissing) {
        missing.add(entry['key']! as String);
      }
    }
    final callback = beforeReadReturns;
    beforeReadReturns = null;
    await callback?.call();
    return {
      'events': result.values
          .map((event) => {...event.toMap(), 'inWindow': inWindow(event)})
          .toList(),
      'missingKeys': missing,
      if (complete != null) 'complete': complete,
    };
  }

  @override
  Future<Map<String, Object?>> upsertEvent({
    required String calendarId,
    required String calendarFingerprint,
    required Map<String, Object?> event,
    Map<String, Object?>? existing,
    required String token,
  }) async {
    await beforeWrite?.call();
    lastDesired = event;
    if (!writeGranted) {
      throw PlatformException(code: 'calendar_permission_denied');
    }
    if (existing == null) {
      final found = events.values
          .where((value) => value.appToken == token)
          .toList();
      if (found.length > 1) throw PlatformException(code: 'calendar_conflict');
      if (found.isNotEmpty) {
        if (!found.single.sameContent(SystemCalendarEventData.fromMap(event))) {
          throw PlatformException(code: 'calendar_conflict');
        }
        return found.single.toMap();
      }
      created++;
      final id = '${nextId++}';
      final saved = SystemCalendarEvent.fromMap({
        ...event,
        'id': id,
        'key': id,
        'calendarId': calendarId,
        'revision': 'revision-${++revision}',
        'appToken': token,
      });
      events[id] = saved;
      return saved.toMap();
    }
    final current = events[existing['key']];
    if (current == null || current.revision != existing['revision']) {
      throw PlatformException(code: 'calendar_conflict');
    }
    updated++;
    final saved = SystemCalendarEvent.fromMap({
      ...current.toMap(),
      ...event,
      'revision': 'revision-${++revision}',
    });
    events[saved.key] = saved;
    return saved.toMap();
  }

  @override
  Future<void> deleteEvent({
    required String calendarId,
    required String calendarFingerprint,
    required Map<String, Object?> existing,
  }) async {
    final current = events[existing['key']];
    if (current == null || current.revision != existing['revision']) {
      throw PlatformException(code: 'calendar_conflict');
    }
    deleted++;
    events.remove(current.key);
  }
}
