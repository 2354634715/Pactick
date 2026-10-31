import 'dart:io';

import 'package:flutter/services.dart';

/// Wire boundary for the device Calendar Provider. Calendar identities and
/// binding metadata stay outside the account synchronization protocol.
class SystemCalendarGateway {
  const SystemCalendarGateway();

  static const _channel = MethodChannel('pactick/system_calendar');
  static const _eventChannel = EventChannel('pactick/system_calendar_changes');
  static final Stream<void> _changes = _eventChannel
      .receiveBroadcastStream()
      .map<void>((_) {});

  bool get isSupported => Platform.isAndroid;

  Stream<void> get changes =>
      isSupported ? _changes : const Stream<void>.empty();

  Future<Map<String, Object?>> getPermissions() async {
    if (!isSupported) {
      return const {'supported': false, 'read': false, 'write': false};
    }
    return _map(await _channel.invokeMethod<Object?>('permissions'));
  }

  Future<Map<String, Object?>> requestPermissions({bool write = false}) async {
    if (!isSupported) return getPermissions();
    return _map(
      await _channel.invokeMethod<Object?>('requestPermissions', {
        'write': write,
      }),
    );
  }

  Future<List<Map<String, Object?>>> listCalendars() async {
    if (!isSupported) return const [];
    final result = await _channel.invokeListMethod<Object?>('calendars');
    return (result ?? const []).map(_map).toList(growable: false);
  }

  Future<Map<String, Object?>> readEvents({
    required String calendarId,
    required String calendarFingerprint,
    required int fromMillis,
    required int toMillis,
    required List<Map<String, Object?>> tracked,
  }) async {
    _requireSupport();
    return _map(
      await _channel.invokeMethod<Object?>('readEvents', {
        'calendarId': calendarId,
        'calendarFingerprint': calendarFingerprint,
        'fromMillis': fromMillis,
        'toMillis': toMillis,
        'tracked': tracked,
      }),
    );
  }

  Future<Map<String, Object?>> upsertEvent({
    required String calendarId,
    required String calendarFingerprint,
    required Map<String, Object?> event,
    Map<String, Object?>? existing,
    required String token,
  }) async {
    _requireSupport();
    return _map(
      await _channel.invokeMethod<Object?>('upsertEvent', {
        'calendarId': calendarId,
        'calendarFingerprint': calendarFingerprint,
        'event': event,
        'existing': existing,
        'token': token,
      }),
    );
  }

  Future<void> deleteEvent({
    required String calendarId,
    required String calendarFingerprint,
    required Map<String, Object?> existing,
  }) async {
    _requireSupport();
    await _channel.invokeMethod<void>('deleteEvent', {
      'calendarId': calendarId,
      'calendarFingerprint': calendarFingerprint,
      'existing': existing,
    });
  }

  void _requireSupport() {
    if (!isSupported) {
      throw PlatformException(code: 'calendar_unsupported');
    }
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid system calendar response.');
    }
    return Map<String, Object?>.from(value);
  }
}
