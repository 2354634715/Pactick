CREATE SEQUENCE sync_cursor_seq;

CREATE TABLE users (
    id uuid PRIMARY KEY,
    email text NOT NULL,
    password_hash text NOT NULL,
    display_name text NOT NULL,
    time_zone text NOT NULL,
    locale text NOT NULL DEFAULT 'zh-CN',
    week_starts_on smallint NOT NULL DEFAULT 1 CHECK (week_starts_on BETWEEN 0 AND 6),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

CREATE UNIQUE INDEX users_email_unique ON users (lower(email)) WHERE deleted_at IS NULL;

CREATE TABLE devices (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name text NOT NULL,
    platform text NOT NULL CHECK (platform IN ('android', 'windows', 'linux')),
    app_version text NOT NULL DEFAULT '',
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz
);

CREATE INDEX devices_user_idx ON devices (user_id);

CREATE TABLE refresh_tokens (
    id uuid PRIMARY KEY,
    family_id uuid NOT NULL,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    token_hash bytea NOT NULL UNIQUE,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    replaced_by uuid REFERENCES refresh_tokens(id)
);

CREATE INDEX refresh_tokens_user_device_idx ON refresh_tokens (user_id, device_id);
CREATE INDEX refresh_tokens_family_idx ON refresh_tokens (family_id);

CREATE TABLE projects (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body jsonb NOT NULL CHECK (jsonb_typeof(body) = 'object'),
    version bigint NOT NULL CHECK (version > 0),
    field_versions jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    deleted_at timestamptz,
    created_by_device_id uuid NOT NULL REFERENCES devices(id),
    updated_by_device_id uuid NOT NULL REFERENCES devices(id),
    last_change_seq bigint NOT NULL UNIQUE
);

CREATE TABLE tasks (LIKE projects INCLUDING ALL);
ALTER TABLE tasks ADD FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE tasks ADD FOREIGN KEY (created_by_device_id) REFERENCES devices(id);
ALTER TABLE tasks ADD FOREIGN KEY (updated_by_device_id) REFERENCES devices(id);

CREATE TABLE task_recurrence_rules (LIKE projects INCLUDING ALL);
ALTER TABLE task_recurrence_rules ADD FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE task_recurrence_rules ADD FOREIGN KEY (created_by_device_id) REFERENCES devices(id);
ALTER TABLE task_recurrence_rules ADD FOREIGN KEY (updated_by_device_id) REFERENCES devices(id);

CREATE TABLE tags (LIKE projects INCLUDING ALL);
ALTER TABLE tags ADD FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE tags ADD FOREIGN KEY (created_by_device_id) REFERENCES devices(id);
ALTER TABLE tags ADD FOREIGN KEY (updated_by_device_id) REFERENCES devices(id);

CREATE TABLE task_tags (LIKE projects INCLUDING ALL);
ALTER TABLE task_tags ADD FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE task_tags ADD FOREIGN KEY (created_by_device_id) REFERENCES devices(id);
ALTER TABLE task_tags ADD FOREIGN KEY (updated_by_device_id) REFERENCES devices(id);

CREATE TABLE plan_blocks (LIKE projects INCLUDING ALL);
ALTER TABLE plan_blocks ADD FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE plan_blocks ADD FOREIGN KEY (created_by_device_id) REFERENCES devices(id);
ALTER TABLE plan_blocks ADD FOREIGN KEY (updated_by_device_id) REFERENCES devices(id);

CREATE TABLE day_plan_entries (LIKE projects INCLUDING ALL);
ALTER TABLE day_plan_entries ADD FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE day_plan_entries ADD FOREIGN KEY (created_by_device_id) REFERENCES devices(id);
ALTER TABLE day_plan_entries ADD FOREIGN KEY (updated_by_device_id) REFERENCES devices(id);

CREATE TABLE focus_policies (LIKE projects INCLUDING ALL);
ALTER TABLE focus_policies ADD FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE focus_policies ADD FOREIGN KEY (created_by_device_id) REFERENCES devices(id);
ALTER TABLE focus_policies ADD FOREIGN KEY (updated_by_device_id) REFERENCES devices(id);

CREATE TABLE focus_sessions (LIKE projects INCLUDING ALL);
ALTER TABLE focus_sessions ADD FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE focus_sessions ADD FOREIGN KEY (created_by_device_id) REFERENCES devices(id);
ALTER TABLE focus_sessions ADD FOREIGN KEY (updated_by_device_id) REFERENCES devices(id);

CREATE TABLE focus_interruptions (LIKE projects INCLUDING ALL);
ALTER TABLE focus_interruptions ADD FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE focus_interruptions ADD FOREIGN KEY (created_by_device_id) REFERENCES devices(id);
ALTER TABLE focus_interruptions ADD FOREIGN KEY (updated_by_device_id) REFERENCES devices(id);

CREATE TABLE reminders (LIKE projects INCLUDING ALL);
ALTER TABLE reminders ADD FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE reminders ADD FOREIGN KEY (created_by_device_id) REFERENCES devices(id);
ALTER TABLE reminders ADD FOREIGN KEY (updated_by_device_id) REFERENCES devices(id);

CREATE INDEX projects_user_active_idx ON projects (user_id) WHERE deleted_at IS NULL;
CREATE INDEX tasks_user_status_idx ON tasks (user_id, (body ->> 'status')) WHERE deleted_at IS NULL;
CREATE INDEX tasks_user_due_idx ON tasks (user_id, (body ->> 'due_at')) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX tasks_recurrence_occurrence_unique ON tasks (
    user_id, (body ->> 'recurrence_source_task_id'), (body ->> 'occurrence_date')
) WHERE deleted_at IS NULL
    AND body ->> 'recurrence_source_task_id' IS NOT NULL
    AND body ->> 'occurrence_date' IS NOT NULL;
CREATE INDEX task_recurrence_user_idx ON task_recurrence_rules (user_id) WHERE deleted_at IS NULL;
CREATE INDEX tags_user_active_idx ON tags (user_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX task_tags_pair_unique ON task_tags (
    user_id, (body ->> 'task_id'), (body ->> 'tag_id')
) WHERE deleted_at IS NULL;
CREATE INDEX plan_blocks_user_start_idx ON plan_blocks (user_id, (body ->> 'starts_at')) WHERE deleted_at IS NULL;
CREATE INDEX day_entries_user_date_idx ON day_plan_entries (user_id, (body ->> 'local_date')) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX day_entries_plan_date_unique ON day_plan_entries (
    user_id, (body ->> 'plan_block_id'), (body ->> 'local_date')
) WHERE deleted_at IS NULL AND body ? 'plan_block_id' AND body ->> 'plan_block_id' IS NOT NULL;
CREATE INDEX focus_sessions_user_start_idx ON focus_sessions (user_id, (body ->> 'started_at')) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX focus_sessions_one_active_per_user ON focus_sessions (user_id)
    WHERE deleted_at IS NULL AND body ->> 'status' IN ('running', 'paused');
CREATE INDEX focus_interruptions_session_idx ON focus_interruptions (
    user_id, (body ->> 'focus_session_id')
) WHERE deleted_at IS NULL;
CREATE INDEX reminders_user_trigger_idx ON reminders (user_id, (body ->> 'trigger_at'))
    WHERE deleted_at IS NULL AND body ->> 'status' = 'scheduled';

CREATE TABLE sync_changes (
    seq bigint PRIMARY KEY DEFAULT nextval('sync_cursor_seq'),
    change_id uuid NOT NULL UNIQUE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    operation text NOT NULL CHECK (operation IN ('upsert', 'delete')),
    version bigint NOT NULL,
    body jsonb NOT NULL,
    changed_fields text[] NOT NULL DEFAULT '{}',
    device_id uuid NOT NULL REFERENCES devices(id),
    client_changed_at timestamptz,
    changed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX sync_changes_user_seq_idx ON sync_changes (user_id, seq);

CREATE TABLE sync_applied_operations (
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    operation_id uuid NOT NULL,
    device_id uuid NOT NULL REFERENCES devices(id),
    result jsonb NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, operation_id)
);

CREATE TABLE sync_conflicts (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    operation_id uuid NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    base_version bigint NOT NULL,
    server_version bigint NOT NULL,
    conflict_fields text[] NOT NULL,
    server_values jsonb NOT NULL,
    client_values jsonb NOT NULL,
    resolution text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX sync_conflicts_user_created_idx ON sync_conflicts (user_id, created_at DESC);
