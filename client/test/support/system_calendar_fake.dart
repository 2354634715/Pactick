import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pactick/core/calendar/system_calendar_models.dart';
import 'package:pactick/data/platform/system_calendar_gateway.dart';

class FakeSystemCalendar extends SystemCalendarGateway {
  FakeSystemCalendar({this.readGranted = true, this.writeGranted = true});

  static const calendar = SystemCalendarInfo(
    id: '1',
    fingerprint: 'test-calendar-identity',
    displayName: '使用者的日历 Calendar',
    accountLabel: 'Demo calendar',
    writable: true,
  );
  final events = <String, Map<String, Object?>>{};
  final changesController = StreamController<void>.broadcast(sync: true);
  bool readGranted;
  bool writeGranted;
  bool denyWrites = false;
  int reads = 0;
  int writes = 0;
  int permissionRequests = 0;
  int _nextId = 100;
  Future<void> Function()? beforeRead;

  @override
  bool get isSupported => true;
  @override
  Stream<void> get changes => changesController.stream;
  @override
  Future<Map<String, Object?>> getPermissions() async => {
    'supported': true,
    'read': readGranted,
    'write': writeGranted,
  };
  @override
  Future<Map<String, Object?>> requestPermissions({bool write = false}) async {
    permissionRequests++;
    readGranted = true;
    if (write) writeGranted = !denyWrites;
    return getPermissions();
  }

  @override
  Future<List<Map<String, Object?>>> listCalendars() async =>
      readGranted ? [calendar.toMap()] : [];

  String add(String title, {DateTime? start}) {
    final from = start ?? DateTime.now().add(const Duration(hours: 1));
    final id = '${_nextId++}';
    events[id] = {
      'id': id,
      'key': id,
      'calendarId': '1',
      'title': title,
      'startsAtMillis': from.millisecondsSinceEpoch,
      'endsAtMillis': from.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      'timeZone': 'UTC',
      'allDay': false,
      'revision': '1',
      'recurring': false,
      'appToken': null,
      'inWindow': true,
      'writable': true,
    };
    return id;
  }

  @override
  Future<Map<String, Object?>> readEvents({
    required String calendarId,
    required String calendarFingerprint,
    required int fromMillis,
    required int toMillis,
    required List<Map<String, Object?>> tracked,
  }) async {
    reads++;
    await beforeRead?.call();
    if (!readGranted) {
      throw PlatformException(code: 'calendar_permission_denied');
    }
    return {
      'complete': true,
      'events': events.values
          .map((event) => Map<String, Object?>.from(event))
          .toList(),
      'missingKeys': [
        for (final link in tracked)
          if (link['id'] != '' &&
              !events.values.any((e) => e['key'] == link['key']))
            link['key'],
      ],
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
    if (!writeGranted) {
      throw PlatformException(code: 'calendar_permission_denied');
    }
    Map<String, Object?>? current;
    if (existing != null) {
      current = events[existing['id']];
      if (current == null || current['revision'] != existing['revision']) {
        throw PlatformException(code: 'calendar_conflict');
      }
    } else {
      for (final candidate in events.values) {
        if (candidate['appToken'] == token) current = candidate;
      }
    }
    writes++;
    final id = current?['id'] as String? ?? '${_nextId++}';
    final saved = <String, Object?>{
      ...?current,
      ...event,
      'id': id,
      'key': current?['key'] ?? id,
      'calendarId': calendarId,
      'revision': '${int.parse(current?['revision'] as String? ?? '0') + 1}',
      'appToken': token,
      'recurring': false,
      'inWindow': true,
      'writable': true,
    };
    events[id] = saved;
    return Map<String, Object?>.from(saved);
  }

  @override
  Future<void> deleteEvent({
    required String calendarId,
    required String calendarFingerprint,
    required Map<String, Object?> existing,
  }) async {
    if (!writeGranted) {
      throw PlatformException(code: 'calendar_permission_denied');
    }
    final current = events[existing['id']];
    if (current == null || current['revision'] != existing['revision']) {
      throw PlatformException(code: 'calendar_conflict');
    }
    writes++;
    events.remove(existing['id']);
  }

  Future<void> close() => changesController.close();
}
