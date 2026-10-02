import 'dart:convert';

import '../../core/models/domain_models.dart';
import '../../core/sync/sync_entity_contract.dart';
import '../../core/sync/sync_models.dart';

/// Portable user content only. Server identities, credentials, device
/// registrations, operation IDs and sync cursors are deliberately absent.
class WorkspaceArchive {
  const WorkspaceArchive({
    required this.createdAt,
    required this.documents,
    required this.settings,
    required this.pendingChanges,
  });

  static const format = 'pactick-workspace';
  static const version = 1;
  static const maxBytes = 50 * 1024 * 1024;
  static const maxDocuments = 100000;
  static const portableSettings = {
    'theme_preference',
    'use_dynamic_color',
    'notifications_enabled',
    'focus_app_whitelists_v1',
    'legacy_sample_content_removed_v1',
  };

  final DateTime createdAt;
  final List<ArchiveDocument> documents;
  final Map<String, String> settings;
  final List<ArchivePendingChange> pendingChanges;

  Map<String, Object?> toJson() => {
    'format': format,
    'version': version,
    'created_at': createdAt.toUtc().toIso8601String(),
    'documents': documents.map((value) => value.toJson()).toList(),
    'settings': settings,
    'pending_changes': pendingChanges.map((value) => value.toJson()).toList(),
  };

  String encode() {
    final encoded = const JsonEncoder.withIndent('  ').convert(toJson());
    if (utf8.encode(encoded).length > maxBytes) {
      throw const FormatException('备份超过 50 MiB 限制。');
    }
    return encoded;
  }

  factory WorkspaceArchive.decode(String encoded) {
    if (encoded.length > maxBytes || utf8.encode(encoded).length > maxBytes) {
      throw const FormatException('备份超过 50 MiB 限制。');
    }
    return WorkspaceArchive.fromJson(_map(jsonDecode(encoded), 'backup'));
  }

  factory WorkspaceArchive.fromJson(Map<String, Object?> json) {
    _keys(json, {
      'format',
      'version',
      'created_at',
      'documents',
      'settings',
      'pending_changes',
    });
    if (json['format'] != format || json['version'] != version) {
      throw const FormatException('不支持的备份格式或版本。');
    }
    final createdAt = _date(json['created_at'], 'created_at');
    final documents = _list(json['documents'], 'documents')
        .map((value) => ArchiveDocument.fromJson(_map(value, 'document')))
        .toList(growable: false);
    final byKey = <String, ArchiveDocument>{};
    for (final document in documents) {
      if (byKey.containsKey(document.key)) {
        throw const FormatException('备份含有重复记录。');
      }
      byKey[document.key] = document;
    }
    for (final document in documents) {
      _validateReferences(document, byKey);
    }
    final rawSettings = _map(json['settings'], 'settings');
    final settings = <String, String>{};
    for (final entry in rawSettings.entries) {
      if (!portableSettings.contains(entry.key) || entry.value is! String) {
        throw FormatException('不允许恢复的设置：${entry.key}。');
      }
      final value = entry.value! as String;
      _validateSetting(entry.key, value);
      settings[entry.key] = value;
    }
    final changes = _list(json['pending_changes'], 'pending_changes')
        .map((value) => ArchivePendingChange.fromJson(_map(value, 'change')))
        .toList(growable: false);
    for (final change in changes) {
      if (!byKey.containsKey('${change.entityType}\u0000${change.entityId}')) {
        throw const FormatException('未同步修改引用了缺失记录。');
      }
      if (change.patch != null) {
        _validateReferences(
          ArchiveDocument(
            entityType: change.entityType,
            id: change.entityId,
            body: {
              ...byKey['${change.entityType}\u0000${change.entityId}']!.body,
              ...change.patch!,
            },
            updatedAt: change.changedAt,
            deleted: false,
          ),
          byKey,
        );
      }
    }
    return WorkspaceArchive(
      createdAt: createdAt,
      documents: List.unmodifiable(documents),
      settings: Map.unmodifiable(settings),
      pendingChanges: List.unmodifiable(changes),
    );
  }
}

class ArchiveDocument {
  const ArchiveDocument({
    required this.entityType,
    required this.id,
    required this.body,
    required this.updatedAt,
    required this.deleted,
  });

  final String entityType;
  final String id;
  final Map<String, Object?> body;
  final DateTime updatedAt;
  final bool deleted;
  String get key => '$entityType\u0000$id';

  Set<String> get referenceKeys => _referenceKeys(entityType, body);

  Map<String, Object?> toJson() => {
    'entity_type': entityType,
    'id': id,
    'body': body,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
  };

  factory ArchiveDocument.fromJson(Map<String, Object?> json) {
    _keys(json, {'entity_type', 'id', 'body', 'updated_at', 'deleted'});
    final type = SyncEntityType.fromWire(json['entity_type']);
    final id = _id(json['id']);
    final deleted = json['deleted'];
    if (deleted is! bool) throw const FormatException('Invalid deleted flag.');
    final body = _map(json['body'], 'body');
    _validateBody(type, body, requireFields: !deleted);
    return ArchiveDocument(
      entityType: type.wireName,
      id: id,
      body: Map.unmodifiable(body),
      updatedAt: _date(json['updated_at'], 'updated_at'),
      deleted: deleted,
    );
  }
}

/// Preserves unresolved local intent for inspection. Restore uses the latest
/// document state, never replays an old server's operation envelopes.
class ArchivePendingChange {
  const ArchivePendingChange({
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.patch,
    required this.changedAt,
  });

  final String entityType;
  final String entityId;
  final SyncAction action;
  final Map<String, Object?>? patch;
  final DateTime changedAt;

  factory ArchivePendingChange.fromOperation(SyncOperation operation) =>
      ArchivePendingChange(
        entityType: operation.entityType.wireName,
        entityId: operation.entityId,
        action: operation.action,
        patch: operation.patch,
        changedAt: operation.clientChangedAt,
      );

  Map<String, Object?> toJson() => {
    'entity_type': entityType,
    'entity_id': entityId,
    'action': action.wireName,
    'patch': patch,
    'changed_at': changedAt.toUtc().toIso8601String(),
  };

  factory ArchivePendingChange.fromJson(Map<String, Object?> json) {
    _keys(json, {'entity_type', 'entity_id', 'action', 'patch', 'changed_at'});
    final type = SyncEntityType.fromWire(json['entity_type']);
    final action = SyncAction.fromWire(json['action']);
    Map<String, Object?>? patch;
    if (action == SyncAction.upsert) {
      patch = _map(json['patch'], 'patch');
      if (patch.isEmpty) throw const FormatException('Empty change patch.');
      _validateBody(type, patch, requireFields: false);
    } else if (json['patch'] != null) {
      throw const FormatException('Delete change must have a null patch.');
    }
    return ArchivePendingChange(
      entityType: type.wireName,
      entityId: _id(json['entity_id']),
      action: action,
      patch: patch == null ? null : Map.unmodifiable(patch),
      changedAt: _date(json['changed_at'], 'changed_at'),
    );
  }
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('Invalid $field object.');
  }
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value, String field) {
  if (value is! List || value.length > WorkspaceArchive.maxDocuments) {
    throw FormatException('Invalid or oversized $field list.');
  }
  return List<Object?>.from(value);
}

void _keys(Map<String, Object?> value, Set<String> keys) {
  if (value.keys.any((key) => !keys.contains(key)) ||
      keys.any((key) => !value.containsKey(key))) {
    throw const FormatException('备份字段不完整或包含未知字段。');
  }
}

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String _id(Object? value) {
  if (value is! String || !_uuidPattern.hasMatch(value)) {
    throw const FormatException('Invalid entity ID.');
  }
  return value;
}

DateTime _date(Object? value, String field) {
  if (value is! String || DateTime.tryParse(value) == null) {
    throw FormatException('Invalid $field date.');
  }
  return DateTime.parse(value).toUtc();
}

void _validateSetting(String key, String value) {
  if (key == 'theme_preference' &&
      !{'system', 'light', 'dark'}.contains(value)) {
    throw const FormatException('Invalid theme preference.');
  }
  if ({'use_dynamic_color', 'notifications_enabled'}.contains(key) &&
      !{'true', 'false'}.contains(value)) {
    throw const FormatException('Invalid boolean preference.');
  }
  if (key == 'focus_app_whitelists_v1') {
    final map = _map(jsonDecode(value), key);
    for (final apps in map.values) {
      if (apps is! List || apps.any((app) => app is! String)) {
        throw const FormatException('Invalid application whitelist.');
      }
    }
  }
}

void _validateBody(
  SyncEntityType type,
  Map<String, Object?> body, {
  required bool requireFields,
}) {
  final allowed = SyncEntityContract.cloudPatch(type, body).keys.toSet();
  if (type == SyncEntityType.task) allowed.addAll({'rank', 'tags'});
  if (type == SyncEntityType.focusPolicy) allowed.add('allowed_app_ids');
  if (body.keys.any((key) => !allowed.contains(key))) {
    throw FormatException('Unknown ${type.wireName} content field.');
  }
  const integers = {
    'sort_order',
    'estimated_duration_seconds',
    'interval',
    'day_of_month',
    'max_occurrences',
    'early_exit_wait_seconds',
    'max_app_exits',
    'planned_duration_seconds',
    'paused_duration_seconds',
    'actual_duration_seconds',
    'app_exit_count',
    'interruption_count',
    'duration_seconds',
  };
  const booleans = {
    'archived',
    'allow_pause',
    'sound_enabled',
    'vibration_enabled',
  };
  const stringLists = {'tags', 'allowed_app_ids', 'emergency_app_categories'};
  for (final entry in body.entries) {
    final key = entry.key;
    final value = entry.value;
    if (value == null) continue;
    if (integers.contains(key)) {
      if (value is! int) throw FormatException('Invalid $key integer.');
    } else if (booleans.contains(key)) {
      if (value is! bool) throw FormatException('Invalid $key boolean.');
    } else if (key == 'rank') {
      if (value is! num || !value.isFinite) {
        throw const FormatException('Invalid rank.');
      }
    } else if (stringLists.contains(key)) {
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('Invalid $key list.');
      }
    } else if (key == 'days_of_week') {
      if (value is! List ||
          value.any((item) => item is! int || item < 0 || item > 6)) {
        throw const FormatException('Invalid days_of_week.');
      }
    } else if (key == 'pause_intervals') {
      for (final item in _list(value, key)) {
        final interval = _map(item, key);
        _keys(interval, {'started_at', 'ended_at'});
        final start = _date(interval['started_at'], 'started_at');
        if (interval['ended_at'] != null &&
            _date(interval['ended_at'], 'ended_at').isBefore(start)) {
          throw const FormatException('Invalid pause interval.');
        }
      }
    } else {
      if (value is! String) throw FormatException('Invalid $key string.');
      if (key.endsWith('_at') ||
          key.endsWith('_on') ||
          key == 'local_date' ||
          key == 'occurrence_date' ||
          key == 'deferred_from_date') {
        _date(value, key);
      } else if (key.endsWith('_id') && key != 'started_device_id') {
        _id(value);
      }
    }
  }
  if (!requireFields) return;
  // These parsers are the same ones used to load the workspace in the UI.
  // Reject malformed input before any row is written or selected.
  try {
    switch (type) {
      case SyncEntityType.project:
        ProjectItem.fromDocument('', body);
      case SyncEntityType.task:
        TaskItem.fromDocument('', body);
      case SyncEntityType.planBlock:
        final block = PlanBlockItem.fromDocument('', body);
        if (!block.endsAt.isAfter(block.startsAt)) {
          throw const FormatException('Invalid plan interval.');
        }
      case SyncEntityType.focusPolicy:
        FocusPolicyItem.fromDocument('', body);
      case SyncEntityType.focusSession:
        FocusSessionItem.fromDocument('', body);
      case SyncEntityType.tag:
        _required(body, {'name'});
      case SyncEntityType.taskTag:
        _required(body, {'task_id', 'tag_id'});
      case SyncEntityType.taskRecurrenceRule:
        _required(body, {'task_id', 'frequency', 'starts_on'});
      case SyncEntityType.dayEntry:
        _required(body, {'local_date', 'title', 'source', 'status'});
      case SyncEntityType.focusInterruption:
        _required(body, {'focus_session_id', 'kind', 'started_at'});
      case SyncEntityType.reminder:
        _required(body, {'target_type', 'target_id', 'trigger_at'});
    }
  } catch (error) {
    throw FormatException('Invalid ${type.wireName} content: $error');
  }
}

void _required(Map<String, Object?> body, Set<String> fields) {
  if (fields.any((field) => body[field] == null)) {
    throw const FormatException('Missing required content fields.');
  }
}

void _validateReferences(
  ArchiveDocument document,
  Map<String, ArchiveDocument> documents,
) {
  for (final key in document.referenceKeys) {
    if (!documents.containsKey(key)) {
      throw FormatException(
        '记录 ${document.id} 引用了缺失的 ${key.split('\u0000').first}。',
      );
    }
  }
}

Set<String> _referenceKeys(String entityType, Map<String, Object?> body) {
  const references = {
    'project_id': 'project',
    'task_id': 'task',
    'recurrence_rule_id': 'task_recurrence_rule',
    'recurrence_source_task_id': 'task',
    'tag_id': 'tag',
    'plan_block_id': 'plan_block',
    'original_plan_block_id': 'plan_block',
    'focus_policy_id': 'focus_policy',
    'focus_session_id': 'focus_session',
  };
  final result = <String>{};
  for (final entry in body.entries) {
    var targetType = references[entry.key];
    if (entityType == 'reminder' && entry.key == 'target_id') {
      targetType = body['target_type'] as String?;
      if (!{
        'task',
        'plan_block',
        'focus_session',
        'day_entry',
      }.contains(targetType)) {
        throw const FormatException('Invalid reminder target type.');
      }
    }
    if (targetType != null && entry.value != null) {
      result.add('$targetType\u0000${entry.value}');
    }
  }
  return result;
}
