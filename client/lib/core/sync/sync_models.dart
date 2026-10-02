enum SyncEntityType {
  project('project'),
  task('task'),
  taskRecurrenceRule('task_recurrence_rule'),
  tag('tag'),
  taskTag('task_tag'),
  planBlock('plan_block'),
  dayEntry('day_entry'),
  focusPolicy('focus_policy'),
  focusSession('focus_session'),
  focusInterruption('focus_interruption'),
  reminder('reminder');

  const SyncEntityType(this.wireName);

  final String wireName;

  static SyncEntityType fromWire(Object? value) {
    if (value is! String) {
      throw const FormatException('Missing or invalid "entity_type".');
    }
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    throw FormatException('Unknown sync entity type "$value".');
  }
}

enum SyncAction {
  upsert('upsert'),
  delete('delete');

  const SyncAction(this.wireName);

  final String wireName;

  static SyncAction fromWire(Object? value) {
    if (value is! String) {
      throw const FormatException('Missing or invalid "action".');
    }
    for (final action in values) {
      if (action.wireName == value) return action;
    }
    throw FormatException('Unknown sync action "$value".');
  }
}

enum SyncOperationStatus {
  applied('applied'),
  rejected('rejected');

  const SyncOperationStatus(this.wireName);

  final String wireName;

  static SyncOperationStatus fromWire(Object? value) {
    if (value is! String) {
      throw const FormatException('Missing or invalid sync status.');
    }
    for (final status in values) {
      if (status.wireName == value) return status;
    }
    throw FormatException('Unknown sync operation status "$value".');
  }
}

class SyncOperation {
  const SyncOperation({
    required this.operationId,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.baseVersion,
    required this.changedFields,
    required this.clientChangedAt,
    this.patch,
  });

  final String operationId;
  final SyncEntityType entityType;
  final String entityId;
  final SyncAction action;
  final int baseVersion;
  final List<String> changedFields;
  final Map<String, Object?>? patch;
  final DateTime clientChangedAt;

  Map<String, Object?> toJson() => {
    'operation_id': operationId,
    'entity_type': entityType.wireName,
    'entity_id': entityId,
    'action': action.wireName,
    'base_version': baseVersion,
    'changed_fields': changedFields,
    if (patch != null) 'patch': patch,
    'client_changed_at': clientChangedAt.toUtc().toIso8601String(),
  };

  SyncOperation copyWith({
    List<String>? changedFields,
    Map<String, Object?>? patch,
  }) {
    return SyncOperation(
      operationId: operationId,
      entityType: entityType,
      entityId: entityId,
      action: action,
      baseVersion: baseVersion,
      changedFields: changedFields ?? this.changedFields,
      patch: action == SyncAction.delete ? null : patch ?? this.patch,
      clientChangedAt: clientChangedAt,
    );
  }
}

class SyncSnapshot {
  const SyncSnapshot({
    required this.entityType,
    required this.entityId,
    required this.version,
    required this.body,
    required this.deleted,
    required this.updatedAt,
    required this.cursor,
  });

  final SyncEntityType entityType;
  final String entityId;
  final int version;
  final Map<String, Object?> body;
  final bool deleted;
  final DateTime updatedAt;
  final int cursor;

  factory SyncSnapshot.fromJson(Map<String, Object?> json) {
    final deleted = _requiredBool(json, 'deleted');
    final bodyValue = json['body'];
    return SyncSnapshot(
      entityType: SyncEntityType.fromWire(json['entity_type']),
      entityId: _requiredString(json, 'entity_id'),
      version: _requiredInt(json, 'version'),
      // Deleting an entity that is already absent returns a tombstone with a
      // nil Go map (`body: null`). Treat it as an empty tombstone snapshot.
      body: bodyValue == null && deleted
          ? const {}
          : _requiredMap(json, 'body'),
      deleted: deleted,
      updatedAt: _requiredDateTime(json, 'updated_at'),
      cursor: _requiredInt(json, 'cursor'),
    );
  }
}

class SyncError {
  const SyncError({
    required this.code,
    required this.message,
    this.details = const {},
  });

  final String code;
  final String message;
  final Map<String, Object?> details;

  factory SyncError.fromJson(Map<String, Object?> json) {
    return SyncError(
      code: _requiredString(json, 'code'),
      message: _requiredString(json, 'message'),
      details: json['details'] == null
          ? const {}
          : _requiredMap(json, 'details'),
    );
  }
}

class SyncOperationResult {
  const SyncOperationResult({
    required this.operationId,
    required this.status,
    this.snapshot,
    this.conflictFields = const [],
    this.resolution,
    this.error,
  });

  final String operationId;
  final SyncOperationStatus status;
  final SyncSnapshot? snapshot;
  final List<String> conflictFields;
  final String? resolution;
  final SyncError? error;

  factory SyncOperationResult.fromJson(Map<String, Object?> json) {
    final status = SyncOperationStatus.fromWire(json['status']);
    final snapshotValue = json['snapshot'];
    final errorValue = json['error'];
    final result = SyncOperationResult(
      operationId: _requiredString(json, 'operation_id'),
      status: status,
      snapshot: snapshotValue == null
          ? null
          : SyncSnapshot.fromJson(_asMap(snapshotValue, 'snapshot')),
      conflictFields: _stringList(json['conflict_fields'], optional: true),
      resolution: _optionalString(json['resolution']),
      error: errorValue == null
          ? null
          : SyncError.fromJson(_asMap(errorValue, 'error')),
    );
    if (status == SyncOperationStatus.applied && result.snapshot == null) {
      throw const FormatException('Applied operation is missing a snapshot.');
    }
    if (status == SyncOperationStatus.rejected && result.error == null) {
      throw const FormatException('Rejected operation is missing an error.');
    }
    return result;
  }
}

class SyncPushResponse {
  const SyncPushResponse({required this.results, required this.currentCursor});

  final List<SyncOperationResult> results;
  final int currentCursor;

  factory SyncPushResponse.fromJson(Map<String, Object?> json) {
    final values = json['results'];
    if (values is! List) {
      throw const FormatException('Missing or invalid "results".');
    }
    return SyncPushResponse(
      results: values
          .map(
            (value) =>
                SyncOperationResult.fromJson(_asMap(value, 'operation result')),
          )
          .toList(growable: false),
      currentCursor: _requiredInt(json, 'current_cursor'),
    );
  }
}

class SyncChange {
  const SyncChange({
    required this.cursor,
    required this.changeId,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.version,
    required this.body,
    required this.changedFields,
    required this.deviceId,
    required this.changedAt,
    this.clientChangedAt,
  });

  final int cursor;
  final String changeId;
  final SyncEntityType entityType;
  final String entityId;
  final SyncAction action;
  final int version;
  final Map<String, Object?> body;
  final List<String> changedFields;
  final String deviceId;
  final DateTime? clientChangedAt;
  final DateTime changedAt;

  factory SyncChange.fromJson(Map<String, Object?> json) {
    return SyncChange(
      cursor: _requiredInt(json, 'cursor'),
      changeId: _requiredString(json, 'change_id'),
      entityType: SyncEntityType.fromWire(json['entity_type']),
      entityId: _requiredString(json, 'entity_id'),
      action: SyncAction.fromWire(json['action']),
      version: _requiredInt(json, 'version'),
      body: _requiredMap(json, 'body'),
      changedFields: _stringList(json['changed_fields']),
      deviceId: _requiredString(json, 'device_id'),
      clientChangedAt: _optionalDateTime(json['client_changed_at']),
      changedAt: _requiredDateTime(json, 'changed_at'),
    );
  }

  SyncSnapshot toSnapshot() => SyncSnapshot(
    entityType: entityType,
    entityId: entityId,
    version: version,
    body: body,
    deleted: action == SyncAction.delete,
    updatedAt: changedAt,
    cursor: cursor,
  );
}

class SyncPullResponse {
  const SyncPullResponse({
    required this.changes,
    required this.nextCursor,
    required this.currentCursor,
    required this.hasMore,
  });

  final List<SyncChange> changes;
  final int nextCursor;
  final int currentCursor;
  final bool hasMore;

  factory SyncPullResponse.fromJson(Map<String, Object?> json) {
    final values = json['changes'];
    if (values is! List) {
      throw const FormatException('Missing or invalid "changes".');
    }
    return SyncPullResponse(
      changes: values
          .map((value) => SyncChange.fromJson(_asMap(value, 'change')))
          .toList(growable: false),
      nextCursor: _requiredInt(json, 'next_cursor'),
      currentCursor: _requiredInt(json, 'current_cursor'),
      hasMore: _requiredBool(json, 'has_more'),
    );
  }
}

class RejectedSyncOperation {
  const RejectedSyncOperation({
    required this.operation,
    required this.error,
    required this.rejectedAt,
  });

  final SyncOperation operation;
  final SyncError error;
  final DateTime rejectedAt;
}

Map<String, Object?> _asMap(Object? value, String field) {
  if (value is! Map) throw FormatException('Invalid $field.');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

Map<String, Object?> _requiredMap(Map<String, Object?> json, String key) {
  return _asMap(json[key], '"$key"');
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Missing or invalid "$key".');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Expected a string.');
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('Missing or invalid "$key".');
  return value;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Missing or invalid "$key".');
  return value;
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final parsed = _optionalDateTime(json[key]);
  if (parsed == null) throw FormatException('Missing or invalid "$key".');
  return parsed;
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Expected a date-time.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException('Invalid date-time.');
  return parsed.toUtc();
}

List<String> _stringList(Object? value, {bool optional = false}) {
  if (value == null && optional) return const [];
  if (value is! List || value.any((item) => item is! String)) {
    throw const FormatException('Expected a string array.');
  }
  return value.cast<String>().toList(growable: false);
}
