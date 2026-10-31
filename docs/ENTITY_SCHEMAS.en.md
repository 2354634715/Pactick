[简体中文](ENTITY_SCHEMAS.md) | English

# Sync entity field contracts

This document defines domain fields in the `patch` of `POST /v1/sync/push`. Entity IDs, versions, deletion state, and device audit information travel in the sync envelope and are not part of `patch`.

When creating an entity, `base_version` is 0 and `patch` must contain all required fields for that entity. Updates upload only changed top-level fields; the field set must exactly match `changed_fields`. Passing `null` for an optional field clears it.

Integer values must be JSON integers. Instants must use RFC 3339 with an offset; the server stores them uniformly in UTC.

## project

| Field | Requirement | Description |
| --- | --- | --- |
| `name` | Required, 1–120 characters | Project or list name |
| `color` | Optional | `#RRGGBB` or `#RRGGBBAA` |
| `archived` | Optional boolean | Whether archived |
| `sort_order` | Optional integer | Ordering value in project lists |

## task

| Field | Requirement | Description |
| --- | --- | --- |
| `title` | Required, 1–500 characters | Task title |
| `note` | Optional, up to 50,000 characters | Notes |
| `project_id` | Optional UUID | Empty means Inbox |
| `priority` | Required | `none`, `low`, `medium`, `high`, `urgent` |
| `due_at` | Optional instant | Deadline; does not represent scheduling |
| `estimated_duration_seconds` | Optional nonnegative integer | Estimated total time |
| `status` | Required | `open`, `completed`, `cancelled` |
| `completed_at` | Conditionally required | Must exist for `completed` and be cleared for other statuses |
| `recurrence_rule_id` | Optional UUID | Simple recurrence rule |
| `recurrence_source_task_id` | Optional UUID | Source task for a recurring instance |
| `occurrence_date` | Optional local date | Present together with the source task; format `YYYY-MM-DD` |

`(recurrence_source_task_id, occurrence_date)` is unique within an account. Offline clients should generate instance IDs with a stable UUIDv5. If clients generate different IDs, the database uniqueness constraint still rejects duplicate instances of the same source task on the same date.

Current general Android task lists use `urgent → high → medium → low → none`, then the client's existing numeric `rank`, then task ID. This client `rank` is not in the server's `task.patch` field allowlist in this section. It is a different field from the string contract for `day_entry.rank` below. Display ordering adds no sync fields and does not change deadlines or plan blocks. Today retains its own scheduling and manual order.

The ordinary `task` contract has no private fields. The private task vault uses a separate local ciphertext table and does not sync tasks, plans, or focus through this contract. See the [private task vault](PRIVATE_TASK_VAULT.en.md) for storage and backup formats.

## task_recurrence_rule

| Field | Requirement | Description |
| --- | --- | --- |
| `task_id` | Required UUID | Source task owning this rule |
| `frequency` | Required | `daily`, `weekly`, `monthly` |
| `interval` | Required, 1–365 | Number of intervals between occurrences |
| `days_of_week` | Required for weekly recurrence | Deduplicated array of 0–6; 0 means Sunday |
| `day_of_month` | Required for monthly recurrence | 1–31; clients use the month's last day for shorter months |
| `starts_on` | Required date | First date eligible for generation |
| `ends_on` | Optional date | Last date eligible for generation |
| `max_occurrences` | Optional positive integer | Maximum number of instances |
| `time_zone` | Required | IANA time zone |

To create a recurring task, first create the task without `recurrence_rule_id`, then create the rule, and finally write the rule UUID back to the task. This avoids submission-order problems caused by cyclic task/rule references.

## tag and task_tag

`tag` must contain `name` (1–80 characters) and may contain `color`. `task_tag` must contain `task_id` and `tag_id`. Association records are immutable. Soft-delete a record to remove the association; create a new record with a new UUID to associate again. A task/tag pair can have only one active association.

## plan_block

| Field | Requirement | Description |
| --- | --- | --- |
| `task_id` | Optional UUID | Linked task |
| `title` | Conditionally required | Required without a linked task |
| `starts_at` | Required instant | Planned start |
| `ends_at` | Required instant | Planned end; later than start and no more than seven days apart |
| `time_zone` | Required | IANA time zone used when creating this plan |
| `status` | Required | `scheduled`, `completed`, `cancelled` |
| `original_plan_block_id` | Optional UUID | Source plan when splitting or deferring |

## day_entry

| Field | Requirement | Description |
| --- | --- | --- |
| `local_date` | Required date | Local date of the Today list |
| `task_id` | Optional UUID | Linked task |
| `plan_block_id` | Optional UUID | Linked plan block |
| `title` | Conditionally required | Required if neither task nor plan is linked |
| `source` | Required | `planned`, `manual` |
| `rank` | Required, 1–100 characters | Ordered string mergeable offline, such as fractional rank |
| `status` | Required | `pending`, `completed`, `deferred`, `skipped` |
| `deferred_from_date` | Optional date | Original date before deferral |

A plan-block/date pair can have only one active Today entry. The Today read model returns a derived entry when a plan for that day has not yet been persisted as a formal Today entry.

## focus_policy

| Field | Requirement | Description |
| --- | --- | --- |
| `name` | Required, 1–120 characters | Policy name |
| `mode` | Required | `normal`, `guard`, `strict` |
| `allow_pause` | Required boolean | Whether pausing is allowed |
| `early_exit_mode` | Required | `allow`, `reason`, `countdown` |
| `early_exit_wait_seconds` | Optional, 0–300 | Seconds to wait before early exit |
| `max_app_exits` | Optional, 0–1000 | Allowed exit count |
| `allowed_app_ids` | Compatibility field; only `null` or an empty array | Since 0.2, app identifiers and project-specific allowlists stay on the device; nonempty arrays are rejected |
| `emergency_app_categories` | Optional string array | Categories such as phone, maps, and authentication |
| `notification_mode` | Required | `silent`, `sound`, `vibrate`, `sound_and_vibrate` |
| `sound_enabled` | Optional boolean | Sound switch |
| `vibration_enabled` | Optional boolean | Vibration switch |

Installed-app inventories, package names, app labels, the current foreground app, Usage Access/overlay permission states, and allowlists saved by Inbox or project are private device data and do not enter the sync protocol. Only policy parameters without app identities sync across devices.

When sending `allowed_app_ids` for compatibility with older documents, clients must send an empty array; omitting the field is recommended. For existing servers, migration `000002_remove_synced_app_identifiers` removes this field from current policy bodies and publishes sanitized entity snapshots. The later `000003_purge_historical_app_identifiers` migration cleans the field from current policies, old sync logs, idempotent result snapshots, and the top level or `body` of conflict records. Pulling from cursor 0 or replaying old operations no longer returns those app identifiers.

Migrations do not rewrite existing database backups. Older backups may still contain app identifiers; administrators should handle them according to applicable retention requirements. After restoring an old backup, run all migrations before exposing the API. Stop the old API before upgrading; old versions do not observe the current sync write lock and cannot run alongside migration.

## focus_session

| Field | Requirement | Description |
| --- | --- | --- |
| `task_id` | Optional UUID | Task actually worked on |
| `plan_block_id` | Optional UUID | Corresponding plan block |
| `focus_policy_id` | Optional UUID | Policy used for this session |
| `planned_duration_seconds` | Required positive integer | Target duration |
| `started_at` | Required instant | Actual start |
| `ended_at` | Required in terminal states | Actual end |
| `pause_started_at` | Required when paused | Start of the current pause |
| `pause_intervals` | Conditionally required | All pause intervals when any pause exists; only a paused session may have an open final interval |
| `paused_duration_seconds` | Optional nonnegative integer | Pause seconds accumulated using a reliable clock |
| `actual_duration_seconds` | Required in terminal states | Actual focus seconds accumulated using a reliable clock |
| `started_device_id` | Required UUID | Must equal the device creating the record |
| `status` | Required | `running`, `paused`, `completed`, `abandoned`, `interrupted` |
| `termination_reason` | Optional, up to 1,000 characters | Early termination or abnormal-ending reason |
| `time_zone` | Required | IANA time zone at session start |
| `app_exit_count` | Optional nonnegative integer | Aggregate exit count |
| `interruption_count` | Optional nonnegative integer | Aggregate interruption count |

Terminal focus records allow only the first task association: when the original `task_id` is empty, the initiating device may set it to an undeleted task in the same account. This operation must not change start or end times, pause intervals, actual duration, status, counts, or any other session field. An existing task association cannot be replaced or cleared. Continuing work requires a new focus record. Updates and deletions of an existing session must be submitted by its `started_device_id`. Other devices receive `focus_device_mismatch` but may still read synced snapshots and history. An account-level constraint prohibits multiple active focus sessions for the same account. Time-interval constraints detect overlap between ended offline records.

## focus_interruption

| Field | Requirement | Description |
| --- | --- | --- |
| `focus_session_id` | Required UUID | Parent focus session |
| `kind` | Required | `app_exit`, `phone`, `unlock`, `permission_disabled`, `clock_change`, `process_recovered`, `manual` |
| `category` | Required | `emergency`, `allowed`, `restricted`, `unknown` |
| `started_at` | Required instant | Interruption start |
| `ended_at` | Optional instant | Interruption end |
| `duration_seconds` | Optional nonnegative integer | Duration accumulated using a reliable clock |

Interruption records are immutable and should be appended after the event ends. Clients should evaluate allowlists locally and upload only classifications and aggregates. The server rejects specific app IDs, package names, app names, foreground apps, and detailed app-usage fields.

## reminder

| Field | Requirement | Description |
| --- | --- | --- |
| `target_type` | Required | `task`, `plan_block` |
| `target_id` | Required UUID | Target in the same account |
| `trigger_at` | Required instant | Trigger time |
| `time_zone` | Required | IANA time zone when creating the reminder |
| `status` | Required | `scheduled`, `fired`, `dismissed`, `cancelled` |
| `delivery_mode` | Required | Fixed to `local` in the first version |

This section defines server-supported reminder entities. Current Android deadline/plan-start reminders are generated locally from tasks and plans rather than by creating these entities. Their native identifiers, event snapshots, preferences, and permission state do not become sync fields. The server only synchronizes reminder definitions and states; triggering a locally available reminder should not require cloud connectivity.

The current [task reminder in the notification area](GETTING_STARTED.en.md) displays one ongoing silent notification based only on the current local workspace's count of `open` tasks. It does not create or fire `reminder` entities and does not schedule by `trigger_at`, deadlines, or calendar blocks. Its switch, native count snapshot, and permission state are not sync fields.
