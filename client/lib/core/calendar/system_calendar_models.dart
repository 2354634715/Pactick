/// Device-calendar metadata. None of these objects belongs to the cloud schema.
class SystemCalendarPermissions {
  const SystemCalendarPermissions({
    required this.supported,
    required this.canRead,
    required this.canWrite,
  });

  factory SystemCalendarPermissions.fromMap(Map<String, Object?> map) =>
      SystemCalendarPermissions(
        supported: map['supported'] == true,
        canRead: map['read'] == true,
        canWrite: map['write'] == true,
      );

  final bool supported;
  final bool canRead;
  final bool canWrite;
}

class SystemCalendarInfo {
  const SystemCalendarInfo({
    required this.id,
    required this.fingerprint,
    required this.displayName,
    this.accountLabel = '',
    required this.writable,
  });

  factory SystemCalendarInfo.fromMap(Map<String, Object?> map) =>
      SystemCalendarInfo(
        id: map['id']! as String,
        fingerprint: map['fingerprint']! as String,
        displayName: map['displayName']! as String,
        accountLabel: map['accountLabel'] as String? ?? '',
        writable: map['writable'] == true,
      );

  final String id;
  final String fingerprint;
  final String displayName;
  final String accountLabel;
  final bool writable;

  String get identity => '$id:$fingerprint';

  Map<String, Object?> toMap() => {
    'id': id,
    'fingerprint': fingerprint,
    'displayName': displayName,
    'accountLabel': accountLabel,
    'writable': writable,
  };
}

class SystemCalendarConfiguration {
  const SystemCalendarConfiguration({
    this.enabled = false,
    this.calendar,
    this.pastDays = 30,
    this.futureDays = 180,
  });

  final bool enabled;
  final SystemCalendarInfo? calendar;
  final int pastDays;
  final int futureDays;

  factory SystemCalendarConfiguration.fromMap(Map<String, Object?> map) =>
      SystemCalendarConfiguration(
        enabled: map['enabled'] == true,
        calendar: map['calendar'] is Map
            ? SystemCalendarInfo.fromMap(_stringMap(map['calendar']))
            : null,
        pastDays: (map['pastDays'] as num?)?.toInt() ?? 30,
        futureDays: (map['futureDays'] as num?)?.toInt() ?? 180,
      );

  Map<String, Object?> toMap() => {
    'enabled': enabled,
    'calendar': calendar?.toMap(),
    'pastDays': pastDays,
    'futureDays': futureDays,
  };
}

/// Fields owned by the bridge. Descriptions, locations, attendees and reminders
/// deliberately never enter this value or a write to an existing event.
class SystemCalendarEventData {
  const SystemCalendarEventData({
    required this.title,
    required this.startsAtMillis,
    required this.endsAtMillis,
    required this.timeZone,
    this.allDay = false,
  });

  factory SystemCalendarEventData.fromMap(Map<String, Object?> map) =>
      SystemCalendarEventData(
        title: map['title']! as String,
        startsAtMillis: (map['startsAtMillis']! as num).toInt(),
        endsAtMillis: (map['endsAtMillis']! as num).toInt(),
        timeZone: map['timeZone']! as String,
        allDay: map['allDay'] == true,
      );

  final String title;
  final int startsAtMillis;
  final int endsAtMillis;
  final String timeZone;
  final bool allDay;

  DateTime get startsAt => DateTime.fromMillisecondsSinceEpoch(startsAtMillis);
  DateTime get endsAt => DateTime.fromMillisecondsSinceEpoch(endsAtMillis);

  Map<String, Object?> toMap() => {
    'title': title,
    'startsAtMillis': startsAtMillis,
    'endsAtMillis': endsAtMillis,
    'timeZone': timeZone,
    'allDay': allDay,
  };

  bool sameContent(SystemCalendarEventData other) =>
      title == other.title &&
      startsAtMillis == other.startsAtMillis &&
      endsAtMillis == other.endsAtMillis &&
      timeZone == other.timeZone &&
      allDay == other.allDay;
}

class SystemCalendarEvent extends SystemCalendarEventData {
  const SystemCalendarEvent({
    required this.id,
    required this.key,
    required this.calendarId,
    required super.title,
    required super.startsAtMillis,
    required super.endsAtMillis,
    required super.timeZone,
    super.allDay,
    required this.revision,
    this.recurring = false,
    this.seriesId,
    this.originalStartMillis,
    this.appToken,
    this.inWindow = true,
    this.writable = true,
  });

  factory SystemCalendarEvent.fromMap(Map<String, Object?> map) =>
      SystemCalendarEvent(
        id: map['id']! as String,
        key: map['key']! as String,
        calendarId: map['calendarId']! as String,
        title: map['title']! as String,
        startsAtMillis: (map['startsAtMillis']! as num).toInt(),
        endsAtMillis: (map['endsAtMillis']! as num).toInt(),
        timeZone: map['timeZone']! as String,
        allDay: map['allDay'] == true,
        revision: map['revision']! as String,
        recurring: map['recurring'] == true,
        seriesId: map['seriesId'] as String?,
        originalStartMillis: (map['originalStartMillis'] as num?)?.toInt(),
        appToken: map['appToken'] as String?,
        inWindow: map['inWindow'] != false,
        writable: map['writable'] != false,
      );

  final String id;
  final String key;
  final String calendarId;
  final String revision;
  final bool recurring;
  final String? seriesId;
  final int? originalStartMillis;
  final String? appToken;
  final bool inWindow;
  final bool writable;

  @override
  Map<String, Object?> toMap() => {
    ...super.toMap(),
    'id': id,
    'key': key,
    'calendarId': calendarId,
    'revision': revision,
    'recurring': recurring,
    'seriesId': seriesId,
    'originalStartMillis': originalStartMillis,
    'appToken': appToken,
    'inWindow': inWindow,
    'writable': writable,
  };
}

enum SystemCalendarConflictChoice {
  local,
  system;

  static const client = local;
}

enum SystemCalendarConflictKind {
  bothChanged,
  localDeleted,
  remoteDeleted,
  readOnly,
  unsupported,
}

class SystemCalendarConflict {
  const SystemCalendarConflict({
    required this.id,
    required this.planId,
    required this.local,
    required this.remote,
    required this.kind,
    required this.canKeepClient,
  });

  final String id;
  final String planId;
  final SystemCalendarEventData? local;
  final SystemCalendarEvent? remote;
  final SystemCalendarConflictKind kind;
  final bool canKeepClient;

  SystemCalendarEventData? get clientBlock => local;
  SystemCalendarEvent? get systemEvent => remote;
  String get reason => kind.name;
  bool get canKeepSystem =>
      remote == null || systemCalendarEventRepresentable(remote!);
}

bool systemCalendarEventRepresentable(SystemCalendarEventData data) =>
    data.endsAtMillis > data.startsAtMillis &&
    data.endsAtMillis - data.startsAtMillis <=
        const Duration(days: 7).inMilliseconds &&
    data.title.length <= 500 &&
    data.timeZone.isNotEmpty;

class SystemCalendarSyncResult {
  const SystemCalendarSyncResult({
    this.imported = 0,
    this.exported = 0,
    this.updated = 0,
    this.deleted = 0,
    this.skipped = 0,
    this.conflicts = const [],
    this.localChanged = false,
    this.lastSyncedAt,
  });

  final int imported;
  final int exported;
  final int updated;
  final int deleted;
  final int skipped;
  final List<SystemCalendarConflict> conflicts;
  final bool localChanged;
  final DateTime? lastSyncedAt;
}

class SystemCalendarSyncCancelled implements Exception {
  const SystemCalendarSyncCancelled();
}

Map<String, Object?> _stringMap(Object? value) =>
    Map<String, Object?>.from(value! as Map);
