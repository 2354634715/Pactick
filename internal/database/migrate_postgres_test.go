package database_test

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"pactick/server/internal/database"
	"pactick/server/internal/sync"
	"pactick/server/internal/testpostgres"
)

func applyHistoricalMigration(t *testing.T, f *testpostgres.Fixture, version int, filename string) {
	t.Helper()
	raw, err := os.ReadFile("migrations/" + filename)
	if err != nil {
		t.Fatal(err)
	}
	tx, err := f.Pool.Begin(f.Ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = tx.Rollback(f.Ctx) }()
	if _, err := tx.Exec(f.Ctx, string(raw)); err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(f.Ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version bigint PRIMARY KEY, name text NOT NULL, checksum text NOT NULL,
			applied_at timestamptz NOT NULL DEFAULT now())`); err != nil {
		t.Fatal(err)
	}
	checksum := fmt.Sprintf("%x", sha256.Sum256(raw))
	if _, err := tx.Exec(f.Ctx, "INSERT INTO schema_migrations (version, name, checksum) VALUES ($1, $2, $3)", version, filename, checksum); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(f.Ctx); err != nil {
		t.Fatal(err)
	}
}

func TestPostgresPrivacyMigrationPurgesHistoricalCopies(t *testing.T) {
	f := testpostgres.New(t)
	applyHistoricalMigration(t, f, 1, "000001_initial.up.sql")
	userID, deviceID := f.Account(t)
	const privateID = "example.legacy.private"
	policyID, operationID := uuid.NewString(), uuid.NewString()
	body := map[string]any{
		"name": "Keep this name", "mode": "guard", "allow_pause": true,
		"early_exit_mode": "allow", "notification_mode": "silent", "allowed_app_ids": []string{privateID},
	}
	bodyJSON, _ := json.Marshal(body)
	if _, err := f.Pool.Exec(f.Ctx, `
		INSERT INTO focus_policies
		(id, user_id, body, version, field_versions, created_at, updated_at, created_by_device_id, updated_by_device_id, last_change_seq)
		VALUES ($1, $2, $3, 1, '{"allowed_app_ids":1,"name":1}', now(), now(), $4, $4, nextval('sync_cursor_seq'))`,
		policyID, userID, bodyJSON, deviceID,
	); err != nil {
		t.Fatal(err)
	}
	if _, err := f.Pool.Exec(f.Ctx, `
		INSERT INTO sync_changes (seq, change_id, user_id, entity_type, entity_id, operation, version, body, changed_fields, device_id)
		SELECT last_change_seq, $2, user_id, 'focus_policy', id, 'upsert', version, body, ARRAY['allowed_app_ids','name'], $3
		FROM focus_policies WHERE id = $1`, policyID, uuid.NewString(), deviceID,
	); err != nil {
		t.Fatal(err)
	}
	cached, _ := json.Marshal(sync.OperationResult{
		OperationID: operationID, Status: "applied", ConflictFields: []string{"allowed_app_ids"},
		Snapshot: &sync.Snapshot{EntityType: "focus_policy", EntityID: policyID, Version: 1, Body: body, UpdatedAt: time.Now().UTC(), Cursor: 1},
	})
	if _, err := f.Pool.Exec(f.Ctx, `INSERT INTO sync_applied_operations (user_id, operation_id, device_id, result) VALUES ($1, $2, $3, $4)`,
		userID, operationID, deviceID, cached,
	); err != nil {
		t.Fatal(err)
	}
	for _, values := range []map[string]any{
		{"allowed_app_ids": []string{privateID}, "name": "Keep this conflict"},
		{"body": body, "deleted": true},
	} {
		raw, _ := json.Marshal(values)
		if _, err := f.Pool.Exec(f.Ctx, `
			INSERT INTO sync_conflicts
			(id, user_id, operation_id, entity_type, entity_id, base_version, server_version, conflict_fields, server_values, client_values, resolution)
			VALUES ($1, $2, $3, 'focus_policy', $4, 0, 1, ARRAY['allowed_app_ids'], $5, $5, 'test')`,
			uuid.NewString(), userID, operationID, policyID, raw,
		); err != nil {
			t.Fatal(err)
		}
	}
	applyHistoricalMigration(t, f, 2, "000002_remove_synced_app_identifiers.up.sql")
	var historicalValueExists bool
	if err := f.Pool.QueryRow(f.Ctx, "SELECT EXISTS (SELECT 1 FROM sync_changes WHERE body ? 'allowed_app_ids')").Scan(&historicalValueExists); err != nil || !historicalValueExists {
		t.Fatalf("legacy fixture did not retain historical values: exists=%v err=%v", historicalValueExists, err)
	}
	if err := database.Migrate(f.Ctx, f.Pool); err != nil {
		t.Fatal(err)
	}
	if err := database.VerifyMigrations(f.Ctx, f.Pool); err != nil {
		t.Fatal(err)
	}
	// Inspect every actual JSON storage copy, not only the current policy.
	for _, query := range []string{
		"SELECT body FROM focus_policies",
		"SELECT body FROM sync_changes",
		"SELECT result FROM sync_applied_operations",
		"SELECT jsonb_build_object('server', server_values, 'client', client_values) FROM sync_conflicts",
	} {
		rows, err := f.Pool.Query(f.Ctx, query)
		if err != nil {
			t.Fatal(err)
		}
		for rows.Next() {
			var raw []byte
			if err := rows.Scan(&raw); err != nil {
				t.Fatal(err)
			}
			if strings.Contains(string(raw), privateID) {
				t.Fatalf("historical application identity retained by %s", query)
			}
			if strings.Contains(query, "sync_conflicts") {
				var values map[string]map[string]any
				if err := json.Unmarshal(raw, &values); err != nil {
					t.Fatal(err)
				}
				for _, side := range values {
					if nested, ok := side["body"].(map[string]any); ok {
						if nested["name"] != "Keep this name" || side["deleted"] != true {
							t.Fatalf("migration damaged delete conflict: %s", raw)
						}
					} else if side["name"] != "Keep this conflict" {
						t.Fatalf("migration damaged upsert conflict: %s", raw)
					}
				}
			}
		}
		if err := rows.Err(); err != nil {
			t.Fatal(err)
		}
		rows.Close()
	}
	store := sync.NewPostgresStore(f.Pool)
	pull, err := store.Pull(f.Ctx, userID, 0, 100)
	if err != nil || len(pull.Changes) != 2 {
		t.Fatalf("full pull: result=%+v err=%v", pull, err)
	}
	for _, change := range pull.Changes {
		if _, retained := change.Body["allowed_app_ids"]; retained || change.Body["name"] != "Keep this name" {
			t.Fatalf("full pull returned an unsanitized or damaged document: %+v", change)
		}
	}
	replay, err := store.Apply(f.Ctx, userID, deviceID, sync.Operation{
		OperationID: operationID, EntityType: "focus_policy", EntityID: policyID, Action: sync.ActionUpsert,
	})
	if err != nil || replay.Status != "applied" || replay.Snapshot == nil || replay.Snapshot.Body["name"] != "Keep this name" {
		t.Fatalf("idempotent replay: result=%+v err=%v", replay, err)
	}
	if _, retained := replay.Snapshot.Body["allowed_app_ids"]; retained {
		t.Fatal("idempotent replay returned historical application identities")
	}
	if err := database.Migrate(f.Ctx, f.Pool); err != nil {
		t.Fatalf("repeat migration: %v", err)
	}
	var changes int
	if err := f.Pool.QueryRow(f.Ctx, "SELECT count(*) FROM sync_changes").Scan(&changes); err != nil || changes != 2 {
		t.Fatalf("repeat migration changed sync history: changes=%d err=%v", changes, err)
	}
}
