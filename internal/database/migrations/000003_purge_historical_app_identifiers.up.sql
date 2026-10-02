-- Migration 000002 rewrote current policies and published sanitized snapshots.
-- Remove the former field from stored historical copies as well. This migration
-- does not restore identifiers on rollback and cannot rewrite existing backups.
UPDATE focus_policies
SET body = body - 'allowed_app_ids'
WHERE body ? 'allowed_app_ids';

UPDATE sync_changes
SET body = body - 'allowed_app_ids'
WHERE entity_type = 'focus_policy' AND body ? 'allowed_app_ids';

UPDATE sync_applied_operations
SET result = result #- '{snapshot,body,allowed_app_ids}'
WHERE result #>> '{snapshot,entity_type}' = 'focus_policy'
    AND (result #> '{snapshot,body}') ? 'allowed_app_ids';

-- Upsert conflicts store field values at the top level; delete conflicts store
-- the former document inside server_values.body. Preserve all unrelated values.
UPDATE sync_conflicts
SET server_values = (server_values - 'allowed_app_ids') #- '{body,allowed_app_ids}',
    client_values = (client_values - 'allowed_app_ids') #- '{body,allowed_app_ids}'
WHERE entity_type = 'focus_policy'
    AND (server_values ? 'allowed_app_ids'
        OR client_values ? 'allowed_app_ids'
        OR (server_values -> 'body') ? 'allowed_app_ids'
        OR (client_values -> 'body') ? 'allowed_app_ids');
