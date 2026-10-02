import 'sync_models.dart';

/// Maps the richer device-local document into the public sync contract.
///
/// Anything not explicitly allow-listed here is never sent to the server.
abstract final class SyncEntityContract {
  static const Map<SyncEntityType, Set<String>> _cloudFields = {
    SyncEntityType.project: {'name', 'color', 'archived', 'sort_order'},
    SyncEntityType.task: {
      'title',
      'note',
      'project_id',
      'priority',
      'due_at',
      'estimated_duration_seconds',
      'status',
      'completed_at',
      'recurrence_rule_id',
      'recurrence_source_task_id',
      'occurrence_date',
    },
    SyncEntityType.taskRecurrenceRule: {
      'task_id',
      'frequency',
      'interval',
      'days_of_week',
      'day_of_month',
      'starts_on',
      'ends_on',
      'max_occurrences',
      'time_zone',
    },
    SyncEntityType.tag: {'name', 'color'},
    SyncEntityType.taskTag: {'task_id', 'tag_id'},
    SyncEntityType.planBlock: {
      'task_id',
      'title',
      'starts_at',
      'ends_at',
      'time_zone',
      'status',
      'original_plan_block_id',
    },
    SyncEntityType.dayEntry: {
      'local_date',
      'task_id',
      'plan_block_id',
      'title',
      'source',
      'rank',
      'status',
      'deferred_from_date',
    },
    SyncEntityType.focusPolicy: {
      'name',
      'mode',
      'allow_pause',
      'early_exit_mode',
      'early_exit_wait_seconds',
      'max_app_exits',
      'emergency_app_categories',
      'notification_mode',
      'sound_enabled',
      'vibration_enabled',
    },
    SyncEntityType.focusSession: {
      'task_id',
      'plan_block_id',
      'focus_policy_id',
      'planned_duration_seconds',
      'started_at',
      'ended_at',
      'pause_started_at',
      'pause_intervals',
      'paused_duration_seconds',
      'actual_duration_seconds',
      'started_device_id',
      'status',
      'termination_reason',
      'time_zone',
      'app_exit_count',
      'interruption_count',
    },
    SyncEntityType.focusInterruption: {
      'focus_session_id',
      'kind',
      'category',
      'started_at',
      'ended_at',
      'duration_seconds',
    },
    SyncEntityType.reminder: {
      'target_type',
      'target_id',
      'trigger_at',
      'time_zone',
      'status',
      'delivery_mode',
    },
  };

  static const Map<SyncEntityType, Set<String>> _deviceLocalFields = {
    // The current UI's numeric ordering and ad-hoc labels have not yet been
    // migrated to day_entry/tag/task_tag records, so they remain device-local.
    SyncEntityType.task: {'rank', 'tags'},
    // Package names and installed-app identifiers are device-private.
    SyncEntityType.focusPolicy: {'allowed_app_ids'},
  };

  static Map<String, Object?> cloudPatch(
    SyncEntityType type,
    Map<String, Object?> body, {
    String? deviceId,
  }) {
    final allowed = _cloudFields[type]!;
    final result = <String, Object?>{
      for (final entry in body.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
    };
    if (type == SyncEntityType.focusSession &&
        result.containsKey('started_device_id') &&
        deviceId != null) {
      result['started_device_id'] = deviceId;
    }
    return result;
  }

  /// Repairs the legacy client model's pause history before it is persisted.
  /// The UI currently sends an empty `pause_intervals` list on every save;
  /// deriving transitions here keeps the wire document valid without leaking
  /// device-only data or inventing intervals during upload.
  static Map<String, Object?> normalizeLocalBody(
    SyncEntityType type,
    Map<String, Object?> body,
    Map<String, Object?>? previousBody,
  ) {
    final result = Map<String, Object?>.from(body);
    if (type != SyncEntityType.focusSession) return result;

    final previousIntervals = _pauseIntervals(previousBody?['pause_intervals']);
    final suppliedIntervals = _pauseIntervals(body['pause_intervals']);
    if (suppliedIntervals.isNotEmpty) return result;

    final intervals = previousIntervals
        .map((value) => Map<String, Object?>.from(value))
        .toList();
    final previousStatus = previousBody?['status'];
    final status = body['status'];
    final pauseStartedAt = body['pause_started_at'];

    if (status == 'paused' && pauseStartedAt is String) {
      final alreadyOpen =
          intervals.isNotEmpty &&
          intervals.last['ended_at'] == null &&
          intervals.last['started_at'] == pauseStartedAt;
      if (!alreadyOpen) {
        if (intervals.isNotEmpty && intervals.last['ended_at'] == null) {
          intervals.removeLast();
        }
        intervals.add({'started_at': pauseStartedAt, 'ended_at': null});
      }
    } else if (intervals.isNotEmpty && intervals.last['ended_at'] == null) {
      final open = intervals.last;
      final start = DateTime.tryParse(open['started_at'] as String? ?? '');
      DateTime? end;
      if (body['ended_at'] case final String value) {
        end = DateTime.tryParse(value);
      }
      if (end == null && start != null) {
        final oldPaused = previousBody?['paused_duration_seconds'];
        final newPaused = body['paused_duration_seconds'];
        final delta =
            ((newPaused is int ? newPaused : 0) -
                    (oldPaused is int ? oldPaused : 0))
                .clamp(0, 365 * 24 * 60 * 60);
        end = start.add(Duration(seconds: delta));
      }
      if (end != null) open['ended_at'] = end.toUtc().toIso8601String();
    }

    if (previousStatus == 'paused' &&
        status != 'paused' &&
        intervals.isNotEmpty) {
      final last = intervals.last;
      final start = DateTime.tryParse(last['started_at'] as String? ?? '');
      final end = DateTime.tryParse(last['ended_at'] as String? ?? '');
      if (start != null && end != null && status != 'running') {
        final previousPaused = previousBody?['paused_duration_seconds'];
        final currentPaused = body['paused_duration_seconds'];
        final closedPause = end
            .difference(start)
            .inSeconds
            .clamp(0, 365 * 24 * 60 * 60);
        final minimum =
            (previousPaused is int ? previousPaused : 0) + closedPause;
        if (currentPaused is! int || currentPaused < minimum) {
          result['paused_duration_seconds'] = minimum;
        }
      }
    }
    result['pause_intervals'] = intervals;
    return result;
  }

  static Map<String, Object?> mergeRemoteBody(
    SyncEntityType type,
    Map<String, Object?> remoteBody,
    Map<String, Object?>? existingLocalBody,
  ) {
    final result = Map<String, Object?>.from(remoteBody);
    final localFields = _deviceLocalFields[type] ?? const <String>{};
    if (existingLocalBody != null) {
      for (final field in localFields) {
        if (existingLocalBody.containsKey(field)) {
          result[field] = existingLocalBody[field];
        }
      }
    }
    return result;
  }

  static int dependencyPriority(SyncOperation operation) {
    const upsertOrder = {
      SyncEntityType.project: 10,
      SyncEntityType.tag: 10,
      SyncEntityType.focusPolicy: 10,
      SyncEntityType.task: 20,
      SyncEntityType.taskRecurrenceRule: 30,
      SyncEntityType.taskTag: 30,
      SyncEntityType.planBlock: 30,
      SyncEntityType.dayEntry: 40,
      SyncEntityType.focusSession: 40,
      SyncEntityType.reminder: 50,
      SyncEntityType.focusInterruption: 50,
    };
    final rank = upsertOrder[operation.entityType] ?? 100;
    return operation.action == SyncAction.upsert ? rank : 1000 - rank;
  }

  static List<Map<String, Object?>> _pauseIntervals(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);
  }
}
