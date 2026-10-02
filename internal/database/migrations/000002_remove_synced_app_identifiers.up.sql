-- Application identities and project-scoped whitelists became device-local in
-- protocol 0.2. Rewrite any policy created by the earlier contract and publish
-- a normal sync snapshot so already-connected clients converge without a full
-- resync. The last updating device remains the audit actor for this system
-- privacy migration because sync_changes requires an account device.
WITH candidates AS MATERIALIZED (
    SELECT
        id,
        user_id,
        body - 'allowed_app_ids' AS new_body,
        version + 1 AS new_version,
        field_versions || jsonb_build_object('allowed_app_ids', version + 1) AS new_field_versions,
        updated_by_device_id AS device_id,
        nextval('sync_cursor_seq') AS new_seq,
        clock_timestamp() AS changed_at
    FROM focus_policies
    WHERE body ? 'allowed_app_ids'
    FOR UPDATE
), updated AS (
    UPDATE focus_policies AS policy
    SET
        body = candidate.new_body,
        version = candidate.new_version,
        field_versions = candidate.new_field_versions,
        updated_at = candidate.changed_at,
        last_change_seq = candidate.new_seq
    FROM candidates AS candidate
    WHERE policy.id = candidate.id
    RETURNING
        policy.id,
        policy.user_id,
        policy.body,
        policy.version,
        policy.updated_by_device_id,
        policy.last_change_seq,
        policy.updated_at
)
INSERT INTO sync_changes (
    seq,
    change_id,
    user_id,
    entity_type,
    entity_id,
    operation,
    version,
    body,
    changed_fields,
    device_id,
    client_changed_at,
    changed_at
)
SELECT
    last_change_seq,
    gen_random_uuid(),
    user_id,
    'focus_policy',
    id,
    'upsert',
    version,
    body,
    ARRAY['allowed_app_ids']::text[],
    updated_by_device_id,
    NULL,
    updated_at
FROM updated;
