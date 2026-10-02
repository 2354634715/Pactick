package sync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"pactick/server/internal/database"
)

type PostgresStore struct {
	pool *pgxpool.Pool
	now  func() time.Time
}

type storedEntity struct {
	body          map[string]any
	version       int64
	fieldVersions map[string]int64
	createdAt     time.Time
	updatedAt     time.Time
	deletedAt     *time.Time
	cursor        int64
}

func NewPostgresStore(pool *pgxpool.Pool) *PostgresStore {
	return &PostgresStore{pool: pool, now: time.Now}
}

func (s *PostgresStore) Apply(ctx context.Context, userID, deviceID string, operation Operation) (OperationResult, error) {
	definition, ok := definitionFor(operation.EntityType)
	if !ok {
		return rejected(operation.OperationID, "unknown_entity_type", ErrUnknownEntity.Error(), nil), nil
	}
	if err := validateOperationEnvelope(operation); err != nil {
		return rejected(operation.OperationID, "invalid_operation", err.Error(), validationDetails(err)), nil
	}

	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return OperationResult{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := database.LockSyncWrites(ctx, tx, userID); err != nil {
		return OperationResult{}, err
	}

	active, err := activeDevice(ctx, tx, userID, deviceID)
	if err != nil {
		return OperationResult{}, fmt.Errorf("check device: %w", err)
	}
	if !active {
		return OperationResult{}, ErrDeviceUnauthorized
	}

	if result, found, err := appliedResult(ctx, tx, userID, operation.OperationID); err != nil {
		return OperationResult{}, err
	} else if found {
		return result, nil
	}

	current, found, err := loadEntity(ctx, tx, definition.table, userID, operation.EntityID)
	if err != nil {
		return OperationResult{}, err
	}
	if found && operation.EntityType == "focus_session" {
		startedDevice, _ := stringValue(current.body, "started_device_id")
		if startedDevice != deviceID {
			return rejected(operation.OperationID, "focus_device_mismatch",
				"only the device that started the focus session may update or delete it", nil), nil
		}
	}

	var result OperationResult
	if operation.Action == ActionDelete {
		result, err = s.applyDelete(ctx, tx, userID, deviceID, operation, definition, current, found)
	} else {
		result, err = s.applyUpsert(ctx, tx, userID, deviceID, operation, definition, current, found)
	}
	if err != nil {
		if apiResult, handled := resultForOperationError(operation.OperationID, err); handled {
			return apiResult, nil
		}
		return OperationResult{}, err
	}

	if err := rememberResult(ctx, tx, userID, deviceID, result); err != nil {
		return OperationResult{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		if activeFocusViolation(err) {
			return rejected(operation.OperationID, "active_focus_exists", ErrActiveFocusExists.Error(), nil), nil
		}
		return OperationResult{}, err
	}
	return result, nil
}

func (s *PostgresStore) applyUpsert(
	ctx context.Context,
	tx pgx.Tx,
	userID, deviceID string,
	operation Operation,
	definition entityDefinition,
	current storedEntity,
	found bool,
) (OperationResult, error) {
	patch, err := decodeObject(operation.Patch)
	if err != nil {
		return OperationResult{}, &ValidationError{Field: "patch", Message: err.Error()}
	}
	if found && current.deletedAt != nil {
		return OperationResult{}, ErrEntityTombstoned
	}
	if found && operation.BaseVersion == 0 {
		return OperationResult{}, ErrEntityExists
	}
	if !found && operation.BaseVersion != 0 {
		return OperationResult{}, ErrEntityNotFound
	}
	if found && operation.BaseVersion > current.version {
		return OperationResult{}, ErrFutureBaseVersion
	}

	now := s.now().UTC()
	newVersion := int64(1)
	existingBody := map[string]any{}
	fieldVersions := map[string]int64{}
	if found {
		newVersion = current.version + 1
		existingBody = current.body
		fieldVersions = current.fieldVersions
	}
	merged, err := mergeDocument(existingBody, fieldVersions, patch, operation.ChangedFields, operation.BaseVersion, newVersion)
	if err != nil {
		return OperationResult{}, err
	}
	if err := validateEntity(operation.EntityType, existingBody, merged.body, !found); err != nil {
		return OperationResult{}, err
	}
	if operation.EntityType == "focus_session" && !found {
		startedDevice, _ := stringValue(merged.body, "started_device_id")
		if startedDevice != deviceID {
			return OperationResult{}, &ValidationError{Field: "started_device_id", Message: "must match the device that created the session"}
		}
	}
	if err := validateReferences(ctx, tx, userID, operation.EntityType, merged.body); err != nil {
		return OperationResult{}, err
	}
	if operation.EntityType == "focus_session" {
		if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtextextended($1, 1))", userID); err != nil {
			return OperationResult{}, fmt.Errorf("lock focus sessions: %w", err)
		}
		overlaps, err := focusSessionOverlaps(ctx, tx, userID, operation.EntityID, merged.body)
		if err != nil {
			return OperationResult{}, err
		}
		if overlaps {
			return OperationResult{}, ErrFocusSessionOverlap
		}
	}

	seq, err := nextCursor(ctx, tx)
	if err != nil {
		return OperationResult{}, err
	}
	bodyJSON, err := json.Marshal(merged.body)
	if err != nil {
		return OperationResult{}, err
	}
	fieldVersionsJSON, err := json.Marshal(merged.fieldVersions)
	if err != nil {
		return OperationResult{}, err
	}
	if found {
		query := fmt.Sprintf(`
			UPDATE %s SET body = $3, version = $4, field_versions = $5,
				updated_at = $6, updated_by_device_id = $7, last_change_seq = $8
			WHERE user_id = $1 AND id = $2`, definition.table)
		_, err = tx.Exec(ctx, query, userID, operation.EntityID, bodyJSON, newVersion, fieldVersionsJSON, now, deviceID, seq)
	} else {
		query := fmt.Sprintf(`
			INSERT INTO %s (
				id, user_id, body, version, field_versions, created_at, updated_at,
				created_by_device_id, updated_by_device_id, last_change_seq
			) VALUES ($1, $2, $3, $4, $5, $6, $6, $7, $7, $8)`, definition.table)
		_, err = tx.Exec(ctx, query, operation.EntityID, userID, bodyJSON, newVersion, fieldVersionsJSON, now, deviceID, seq)
	}
	if err != nil {
		if activeFocusViolation(err) {
			return OperationResult{}, ErrActiveFocusExists
		}
		if duplicateRelationViolation(err) {
			return OperationResult{}, ErrDuplicateRelation
		}
		return OperationResult{}, fmt.Errorf("write %s: %w", operation.EntityType, err)
	}
	if err := insertChange(ctx, tx, seq, userID, deviceID, operation, newVersion, bodyJSON); err != nil {
		return OperationResult{}, err
	}
	if len(merged.conflictFields) > 0 {
		if err := insertConflict(ctx, tx, userID, operation, current.version, merged, "incoming_write_wins_by_server_receive_order"); err != nil {
			return OperationResult{}, err
		}
	}

	resolution := ""
	if len(merged.conflictFields) > 0 {
		resolution = "incoming_write_wins_by_server_receive_order"
	}
	return OperationResult{
		OperationID: operation.OperationID,
		Status:      "applied",
		Snapshot: &Snapshot{
			EntityType: operation.EntityType,
			EntityID:   operation.EntityID,
			Version:    newVersion,
			Body:       merged.body,
			UpdatedAt:  now,
			Cursor:     seq,
		},
		ConflictFields: merged.conflictFields,
		Resolution:     resolution,
	}, nil
}

func (s *PostgresStore) applyDelete(
	ctx context.Context,
	tx pgx.Tx,
	userID, deviceID string,
	operation Operation,
	definition entityDefinition,
	current storedEntity,
	found bool,
) (OperationResult, error) {
	if len(operation.Patch) > 0 && string(operation.Patch) != "null" && string(operation.Patch) != "{}" {
		return OperationResult{}, &ValidationError{Field: "patch", Message: "must be absent for delete"}
	}
	if len(operation.ChangedFields) > 0 {
		return OperationResult{}, &ValidationError{Field: "changed_fields", Message: "must be empty for delete"}
	}
	now := s.now().UTC()
	if !found {
		return OperationResult{
			OperationID: operation.OperationID,
			Status:      "applied",
			Snapshot: &Snapshot{
				EntityType: operation.EntityType,
				EntityID:   operation.EntityID,
				Deleted:    true,
				UpdatedAt:  now,
			},
			Resolution: "already_absent",
		}, nil
	}
	if operation.BaseVersion > current.version {
		return OperationResult{}, ErrFutureBaseVersion
	}
	if current.deletedAt != nil {
		return OperationResult{
			OperationID: operation.OperationID,
			Status:      "applied",
			Snapshot:    snapshotFromStored(operation.EntityType, operation.EntityID, current),
			Resolution:  "already_deleted",
		}, nil
	}

	newVersion := current.version + 1
	seq, err := nextCursor(ctx, tx)
	if err != nil {
		return OperationResult{}, err
	}
	versions := cloneVersions(current.fieldVersions)
	versions["__deleted"] = newVersion
	versionsJSON, _ := json.Marshal(versions)
	query := fmt.Sprintf(`
		UPDATE %s SET version = $3, field_versions = $4, deleted_at = $5,
			updated_at = $5, updated_by_device_id = $6, last_change_seq = $7
		WHERE user_id = $1 AND id = $2`, definition.table)
	if _, err := tx.Exec(ctx, query, userID, operation.EntityID, newVersion, versionsJSON, now, deviceID, seq); err != nil {
		return OperationResult{}, fmt.Errorf("delete %s: %w", operation.EntityType, err)
	}
	bodyJSON, _ := json.Marshal(current.body)
	deleteOperation := operation
	deleteOperation.ChangedFields = []string{"__deleted"}
	if err := insertChange(ctx, tx, seq, userID, deviceID, deleteOperation, newVersion, bodyJSON); err != nil {
		return OperationResult{}, err
	}

	conflictFields := []string(nil)
	resolution := ""
	if operation.BaseVersion < current.version {
		conflictFields = []string{"__deleted"}
		resolution = "delete_wins"
		merged := mergeResult{
			conflictFields: conflictFields,
			serverValues:   map[string]any{"body": current.body},
			clientValues:   map[string]any{"deleted": true},
		}
		if err := insertConflict(ctx, tx, userID, operation, current.version, merged, "delete_wins"); err != nil {
			return OperationResult{}, err
		}
	}
	return OperationResult{
		OperationID: operation.OperationID,
		Status:      "applied",
		Snapshot: &Snapshot{
			EntityType: operation.EntityType,
			EntityID:   operation.EntityID,
			Version:    newVersion,
			Body:       current.body,
			Deleted:    true,
			UpdatedAt:  now,
			Cursor:     seq,
		},
		ConflictFields: conflictFields,
		Resolution:     resolution,
	}, nil
}

func (s *PostgresStore) Pull(ctx context.Context, userID string, after int64, limit int) (PullResponse, error) {
	current, err := s.CurrentCursor(ctx, userID)
	if err != nil {
		return PullResponse{}, err
	}
	rows, err := s.pool.Query(ctx, `
		SELECT seq, change_id, entity_type, entity_id, operation, version, body,
		       changed_fields, device_id, client_changed_at, changed_at
		FROM sync_changes
		WHERE user_id = $1 AND seq > $2 AND seq <= $3
		ORDER BY seq
		LIMIT $4`, userID, after, current, limit+1)
	if err != nil {
		return PullResponse{}, fmt.Errorf("query sync changes: %w", err)
	}
	defer rows.Close()

	changes := make([]Change, 0, limit)
	for rows.Next() {
		var change Change
		var bodyJSON []byte
		if err := rows.Scan(
			&change.Cursor, &change.ChangeID, &change.EntityType, &change.EntityID, &change.Action,
			&change.Version, &bodyJSON, &change.ChangedFields, &change.DeviceID,
			&change.ClientChangedAt, &change.ChangedAt,
		); err != nil {
			return PullResponse{}, fmt.Errorf("scan sync change: %w", err)
		}
		body, err := decodeObject(bodyJSON)
		if err != nil {
			return PullResponse{}, fmt.Errorf("decode sync change: %w", err)
		}
		change.Body = body
		changes = append(changes, change)
	}
	if err := rows.Err(); err != nil {
		return PullResponse{}, err
	}

	hasMore := len(changes) > limit
	if hasMore {
		changes = changes[:limit]
	}
	nextCursor := after
	if len(changes) > 0 {
		nextCursor = changes[len(changes)-1].Cursor
	} else if !hasMore {
		nextCursor = current
	}
	return PullResponse{
		Changes:       changes,
		NextCursor:    nextCursor,
		CurrentCursor: current,
		HasMore:       hasMore,
	}, nil
}

func (s *PostgresStore) CurrentCursor(ctx context.Context, userID string) (int64, error) {
	var cursor int64
	if err := s.pool.QueryRow(ctx,
		"SELECT COALESCE(MAX(seq), 0) FROM sync_changes WHERE user_id = $1", userID,
	).Scan(&cursor); err != nil {
		return 0, fmt.Errorf("read sync cursor: %w", err)
	}
	return cursor, nil
}

func validateOperationEnvelope(operation Operation) error {
	if _, err := uuid.Parse(operation.OperationID); err != nil {
		return &ValidationError{Field: "operation_id", Message: "must be a UUID"}
	}
	if _, err := uuid.Parse(operation.EntityID); err != nil {
		return &ValidationError{Field: "entity_id", Message: "must be a UUID"}
	}
	if operation.Action != ActionUpsert && operation.Action != ActionDelete {
		return &ValidationError{Field: "action", Message: "must be upsert or delete"}
	}
	if operation.BaseVersion < 0 {
		return &ValidationError{Field: "base_version", Message: "must not be negative"}
	}
	if operation.ClientChangedAt != nil {
		normalized := operation.ClientChangedAt.UTC()
		operation.ClientChangedAt = &normalized
	}
	return nil
}

func loadEntity(ctx context.Context, tx pgx.Tx, table, userID, entityID string) (storedEntity, bool, error) {
	query := fmt.Sprintf(`
		SELECT body, version, field_versions, created_at, updated_at, deleted_at, last_change_seq
		FROM %s WHERE user_id = $1 AND id = $2 FOR UPDATE`, table)
	var entity storedEntity
	var bodyJSON, fieldVersionsJSON []byte
	err := tx.QueryRow(ctx, query, userID, entityID).Scan(
		&bodyJSON, &entity.version, &fieldVersionsJSON, &entity.createdAt,
		&entity.updatedAt, &entity.deletedAt, &entity.cursor,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return storedEntity{}, false, nil
	}
	if err != nil {
		return storedEntity{}, false, fmt.Errorf("load %s: %w", table, err)
	}
	entity.body, err = decodeObject(bodyJSON)
	if err != nil {
		return storedEntity{}, false, err
	}
	if err := json.Unmarshal(fieldVersionsJSON, &entity.fieldVersions); err != nil {
		return storedEntity{}, false, err
	}
	return entity, true, nil
}

func activeDevice(ctx context.Context, tx pgx.Tx, userID, deviceID string) (bool, error) {
	var active bool
	err := tx.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM devices
			WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL
		)`, deviceID, userID,
	).Scan(&active)
	return active, err
}

func appliedResult(ctx context.Context, tx pgx.Tx, userID, operationID string) (OperationResult, bool, error) {
	var raw []byte
	err := tx.QueryRow(ctx,
		"SELECT result FROM sync_applied_operations WHERE user_id = $1 AND operation_id = $2",
		userID, operationID,
	).Scan(&raw)
	if errors.Is(err, pgx.ErrNoRows) {
		return OperationResult{}, false, nil
	}
	if err != nil {
		return OperationResult{}, false, err
	}
	var result OperationResult
	if err := json.Unmarshal(raw, &result); err != nil {
		return OperationResult{}, false, err
	}
	return result, true, nil
}

func rememberResult(ctx context.Context, tx pgx.Tx, userID, deviceID string, result OperationResult) error {
	raw, err := json.Marshal(result)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO sync_applied_operations (user_id, operation_id, device_id, result)
		VALUES ($1, $2, $3, $4)`, userID, result.OperationID, deviceID, raw)
	return err
}

func nextCursor(ctx context.Context, tx pgx.Tx) (int64, error) {
	var seq int64
	if err := tx.QueryRow(ctx, "SELECT nextval('sync_cursor_seq')").Scan(&seq); err != nil {
		return 0, fmt.Errorf("allocate sync cursor: %w", err)
	}
	return seq, nil
}

func insertChange(
	ctx context.Context,
	tx pgx.Tx,
	seq int64,
	userID, deviceID string,
	operation Operation,
	version int64,
	bodyJSON []byte,
) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO sync_changes (
			seq, change_id, user_id, entity_type, entity_id, operation, version,
			body, changed_fields, device_id, client_changed_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
		seq, uuid.NewString(), userID, operation.EntityType, operation.EntityID, operation.Action,
		version, bodyJSON, operation.ChangedFields, deviceID, operation.ClientChangedAt,
	)
	if err != nil {
		return fmt.Errorf("insert sync change: %w", err)
	}
	return nil
}

func insertConflict(
	ctx context.Context,
	tx pgx.Tx,
	userID string,
	operation Operation,
	serverVersion int64,
	merged mergeResult,
	resolution string,
) error {
	serverValues, _ := json.Marshal(merged.serverValues)
	clientValues, _ := json.Marshal(merged.clientValues)
	_, err := tx.Exec(ctx, `
		INSERT INTO sync_conflicts (
			id, user_id, operation_id, entity_type, entity_id, base_version,
			server_version, conflict_fields, server_values, client_values, resolution
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
		uuid.NewString(), userID, operation.OperationID, operation.EntityType, operation.EntityID,
		operation.BaseVersion, serverVersion, merged.conflictFields, serverValues, clientValues,
		resolution,
	)
	return err
}

func snapshotFromStored(entityType, entityID string, current storedEntity) *Snapshot {
	return &Snapshot{
		EntityType: entityType,
		EntityID:   entityID,
		Version:    current.version,
		Body:       current.body,
		Deleted:    current.deletedAt != nil,
		UpdatedAt:  current.updatedAt,
		Cursor:     current.cursor,
	}
}

func rejected(operationID, code, message string, details map[string]any) OperationResult {
	return OperationResult{
		OperationID: operationID,
		Status:      "rejected",
		Error:       &APIError{Code: code, Message: message, Details: details},
	}
}

func resultForOperationError(operationID string, err error) (OperationResult, bool) {
	var validationErr *ValidationError
	switch {
	case errors.As(err, &validationErr):
		return rejected(operationID, "validation_error", validationErr.Error(), validationDetails(err)), true
	case errors.Is(err, ErrEntityNotFound):
		return rejected(operationID, "entity_not_found", err.Error(), nil), true
	case errors.Is(err, ErrEntityExists):
		return rejected(operationID, "entity_exists", err.Error(), nil), true
	case errors.Is(err, ErrEntityTombstoned):
		return rejected(operationID, "entity_tombstoned", err.Error(), nil), true
	case errors.Is(err, ErrFutureBaseVersion):
		return rejected(operationID, "future_base_version", err.Error(), nil), true
	case errors.Is(err, ErrActiveFocusExists):
		return rejected(operationID, "active_focus_exists", err.Error(), nil), true
	case errors.Is(err, ErrFocusSessionOverlap):
		return rejected(operationID, "focus_session_overlap", err.Error(), nil), true
	case errors.Is(err, ErrDuplicateRelation):
		return rejected(operationID, "duplicate_relation", err.Error(), nil), true
	default:
		return OperationResult{}, false
	}
}

func activeFocusViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "focus_sessions_one_active_per_user"
}

func duplicateRelationViolation(err error) bool {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.Code != "23505" {
		return false
	}
	switch pgErr.ConstraintName {
	case "task_tags_pair_unique", "day_entries_plan_date_unique", "tasks_recurrence_occurrence_unique":
		return true
	default:
		return false
	}
}

func validateReferences(ctx context.Context, tx pgx.Tx, userID, entityType string, body map[string]any) error {
	type reference struct {
		field string
		table string
	}
	var refs []reference
	switch entityType {
	case "task":
		refs = []reference{
			{"project_id", "projects"},
			{"recurrence_rule_id", "task_recurrence_rules"},
			{"recurrence_source_task_id", "tasks"},
		}
	case "task_recurrence_rule":
		refs = []reference{{"task_id", "tasks"}}
	case "task_tag":
		refs = []reference{{"task_id", "tasks"}, {"tag_id", "tags"}}
	case "plan_block":
		refs = []reference{{"task_id", "tasks"}, {"original_plan_block_id", "plan_blocks"}}
	case "day_entry":
		refs = []reference{{"task_id", "tasks"}, {"plan_block_id", "plan_blocks"}}
	case "focus_session":
		refs = []reference{{"task_id", "tasks"}, {"plan_block_id", "plan_blocks"}, {"focus_policy_id", "focus_policies"}}
	case "focus_interruption":
		refs = []reference{{"focus_session_id", "focus_sessions"}}
	case "reminder":
		targetType, _ := bodyStringValue(body, "target_type")
		if targetType == "task" {
			refs = []reference{{"target_id", "tasks"}}
		} else if targetType == "plan_block" {
			refs = []reference{{"target_id", "plan_blocks"}}
		}
	}
	for _, ref := range refs {
		value, exists := body[ref.field]
		if !exists || value == nil {
			continue
		}
		id, ok := value.(string)
		if !ok {
			continue
		}
		query := fmt.Sprintf("SELECT EXISTS (SELECT 1 FROM %s WHERE user_id = $1 AND id = $2)", ref.table)
		var existsForUser bool
		if err := tx.QueryRow(ctx, query, userID, id).Scan(&existsForUser); err != nil {
			return err
		}
		if !existsForUser {
			return &ValidationError{Field: ref.field, Message: "does not reference an entity in this account"}
		}
	}
	if entityType == "focus_session" {
		deviceID, _ := body["started_device_id"].(string)
		var existsForUser bool
		if err := tx.QueryRow(ctx,
			"SELECT EXISTS (SELECT 1 FROM devices WHERE user_id = $1 AND id = $2)", userID, deviceID,
		).Scan(&existsForUser); err != nil {
			return err
		}
		if !existsForUser {
			return &ValidationError{Field: "started_device_id", Message: "does not reference a device in this account"}
		}
	}
	return nil
}

func focusSessionOverlaps(ctx context.Context, tx pgx.Tx, userID, entityID string, body map[string]any) (bool, error) {
	startedAt, ok := bodyStringValue(body, "started_at")
	if !ok {
		return false, nil
	}
	endedAt, hasEnd := bodyStringValue(body, "ended_at")
	if !hasEnd {
		endedAt = "infinity"
	}
	var overlaps bool
	err := tx.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM focus_sessions
			WHERE user_id = $1 AND id <> $2 AND deleted_at IS NULL
			  AND (body ->> 'started_at')::timestamptz < $4::timestamptz
			  AND COALESCE((body ->> 'ended_at')::timestamptz, 'infinity'::timestamptz) > $3::timestamptz
		)`, userID, entityID, startedAt, endedAt,
	).Scan(&overlaps)
	if err != nil {
		return false, fmt.Errorf("check focus session overlap: %w", err)
	}
	return overlaps, nil
}

func bodyStringValue(body map[string]any, field string) (string, bool) {
	value, ok := body[field].(string)
	return value, ok && value != ""
}
