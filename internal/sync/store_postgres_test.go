package sync

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"

	"pactick/server/internal/database"
	"pactick/server/internal/testpostgres"
)

func TestPostgresAccountCursorCommitOrder(t *testing.T) {
	for _, action := range []string{ActionUpsert, ActionDelete} {
		t.Run(action, func(t *testing.T) {
			f := testpostgres.New(t)
			if err := database.Migrate(f.Ctx, f.Pool); err != nil {
				t.Fatal(err)
			}
			userID, deviceID := f.Account(t)
			store := NewPostgresStore(f.Pool)
			first := Operation{
				OperationID: uuid.NewString(), EntityType: "project", EntityID: uuid.NewString(),
				Action: ActionUpsert, ChangedFields: []string{"name"}, Patch: json.RawMessage(`{"name":"First"}`),
			}
			var after int64
			if action == ActionDelete {
				created, err := store.Apply(f.Ctx, userID, deviceID, first)
				if err != nil || created.Status != "applied" {
					t.Fatalf("seed entity: result=%+v err=%v", created, err)
				}
				after = created.Snapshot.Cursor
				first.OperationID = uuid.NewString()
				first.Action, first.BaseVersion = ActionDelete, 1
				first.ChangedFields, first.Patch = nil, nil
			}
			gate := testpostgres.NewQueryGate("SELECT nextval('sync_cursor_seq')")
			defer close(gate.Release)
			firstStore := NewPostgresStore(f.TracedPool(t, gate, "first"))
			type applyResult struct {
				result OperationResult
				err    error
			}
			firstDone := make(chan applyResult, 1)
			go func() {
				result, err := firstStore.Apply(f.Ctx, userID, deviceID, first)
				firstDone <- applyResult{result, err}
			}()
			gate.Wait(t, f.Ctx)
			second := Operation{
				OperationID: uuid.NewString(), EntityType: "tag", EntityID: uuid.NewString(),
				Action: ActionUpsert, ChangedFields: []string{"name"}, Patch: json.RawMessage(`{"name":"Second"}`),
			}
			secondDone := make(chan applyResult, 1)
			go func() {
				result, err := store.Apply(f.Ctx, userID, deviceID, second)
				secondDone <- applyResult{result, err}
			}()
			// Wait for an actual PostgreSQL lock wait, not a scheduling delay.
			for {
				var waiting bool
				if err := f.Pool.QueryRow(f.Ctx, `
					SELECT EXISTS (SELECT 1 FROM pg_stat_activity
					WHERE application_name = $1 AND wait_event_type = 'Lock'
					AND cardinality(pg_blocking_pids(pid)) > 0)`,
					f.Config.ConnConfig.RuntimeParams["application_name"],
				).Scan(&waiting); err != nil {
					t.Fatal(err)
				}
				if waiting {
					break
				}
				select {
				case result := <-secondDone:
					t.Fatalf("higher cursor committed while first transaction was open: %+v", result)
				case <-f.Ctx.Done():
					t.Fatal(f.Ctx.Err())
				case <-time.After(10 * time.Millisecond):
				}
			}
			pending, err := store.Pull(f.Ctx, userID, after, 100)
			if err != nil || len(pending.Changes) != 0 || pending.NextCursor != after {
				t.Fatalf("pull while first transaction is open: response=%+v err=%v", pending, err)
			}
			gate.Release <- struct{}{}
			a, b := <-firstDone, <-secondDone
			if a.err != nil || b.err != nil || a.result.Status != "applied" || b.result.Status != "applied" {
				t.Fatalf("apply results: first=%+v second=%+v", a, b)
			}
			if a.result.Snapshot.Cursor >= b.result.Snapshot.Cursor {
				t.Fatalf("account cursors did not follow commit order: first=%d second=%d", a.result.Snapshot.Cursor, b.result.Snapshot.Cursor)
			}
			page, err := store.Pull(f.Ctx, userID, pending.NextCursor, 1)
			if err != nil || len(page.Changes) != 1 || page.Changes[0].EntityID != first.EntityID || !page.HasMore {
				t.Fatalf("first page: response=%+v err=%v", page, err)
			}
			page, err = store.Pull(f.Ctx, userID, page.NextCursor, 1)
			if err != nil || len(page.Changes) != 1 || page.Changes[0].EntityID != second.EntityID || page.HasMore {
				t.Fatalf("second page: response=%+v err=%v", page, err)
			}
		})
	}
}

func TestPostgresFocusControlRequiresStartingDevice(t *testing.T) {
	f := testpostgres.New(t)
	if err := database.Migrate(f.Ctx, f.Pool); err != nil {
		t.Fatal(err)
	}
	userID, deviceID := f.Account(t)
	otherDevice := uuid.NewString()
	if _, err := f.Pool.Exec(f.Ctx, `
		INSERT INTO devices (id, user_id, name, platform) VALUES ($1, $2, 'Other', 'android')`, otherDevice, userID,
	); err != nil {
		t.Fatal(err)
	}
	store := NewPostgresStore(f.Pool)
	sessionID := uuid.NewString()
	body, _ := json.Marshal(map[string]any{
		"planned_duration_seconds": 1500, "started_at": "2026-10-01T00:00:00Z",
		"started_device_id": deviceID, "status": "running", "time_zone": "UTC",
	})
	created, err := store.Apply(f.Ctx, userID, deviceID, Operation{
		OperationID: uuid.NewString(), EntityType: "focus_session", EntityID: sessionID, Action: ActionUpsert,
		Patch: body, ChangedFields: []string{"planned_duration_seconds", "started_at", "started_device_id", "status", "time_zone"},
	})
	if err != nil || created.Status != "applied" {
		t.Fatalf("create focus: result=%+v err=%v", created, err)
	}
	for _, action := range []string{ActionUpsert, ActionDelete} {
		operation := Operation{
			OperationID: uuid.NewString(), EntityType: "focus_session", EntityID: sessionID,
			Action: action, BaseVersion: 1,
		}
		if action == ActionUpsert {
			operation.Patch = json.RawMessage(`{"planned_duration_seconds":1800}`)
			operation.ChangedFields = []string{"planned_duration_seconds"}
		}
		result, err := store.Apply(f.Ctx, userID, otherDevice, operation)
		if err != nil || result.Status != "rejected" || result.Error == nil || result.Error.Code != "focus_device_mismatch" {
			t.Fatalf("other device %s: result=%+v err=%v", action, result, err)
		}
	}
	updated, err := store.Apply(f.Ctx, userID, deviceID, Operation{
		OperationID: uuid.NewString(), EntityType: "focus_session", EntityID: sessionID, Action: ActionUpsert,
		BaseVersion: 1, Patch: json.RawMessage(`{"planned_duration_seconds":1800}`), ChangedFields: []string{"planned_duration_seconds"},
	})
	if err != nil || updated.Status != "applied" || updated.Snapshot.Version != 2 {
		t.Fatalf("starting device update: result=%+v err=%v", updated, err)
	}
	pull, err := store.Pull(f.Ctx, userID, 0, 100)
	if err != nil || len(pull.Changes) != 2 {
		t.Fatalf("shared history read: response=%+v err=%v", pull, err)
	}
}

func TestPostgresMigrationWaitsForSyncWriter(t *testing.T) {
	f := testpostgres.New(t)
	if err := database.Migrate(f.Ctx, f.Pool); err != nil {
		t.Fatal(err)
	}
	userID, deviceID := f.Account(t)
	policyID := uuid.NewString()
	if _, err := f.Pool.Exec(f.Ctx, `
		INSERT INTO focus_policies
		(id, user_id, body, version, created_at, updated_at, created_by_device_id, updated_by_device_id, last_change_seq)
		VALUES ($1, $2, '{"name":"Legacy","allowed_app_ids":["example.legacy.private"]}',
		1, now(), now(), $3, $3, nextval('sync_cursor_seq'))`, policyID, userID, deviceID,
	); err != nil {
		t.Fatal(err)
	}
	// This isolated fixture represents a database awaiting the historical
	// migration that itself allocates a cursor and inserts a sync change.
	if _, err := f.Pool.Exec(f.Ctx, "DELETE FROM schema_migrations WHERE version >= 2"); err != nil {
		t.Fatal(err)
	}
	gate := testpostgres.NewQueryGate("SELECT nextval('sync_cursor_seq')")
	defer close(gate.Release)
	store := NewPostgresStore(f.TracedPool(t, gate, "writer"))
	writerDone := make(chan error, 1)
	projectID := uuid.NewString()
	go func() {
		result, err := store.Apply(f.Ctx, userID, deviceID, Operation{
			OperationID: uuid.NewString(), EntityType: "project", EntityID: projectID, Action: ActionUpsert,
			Patch: json.RawMessage(`{"name":"First"}`), ChangedFields: []string{"name"},
		})
		if err == nil && result.Status != "applied" {
			err = result.Error
		}
		writerDone <- err
	}()
	gate.Wait(t, f.Ctx)
	migrationDone := make(chan error, 1)
	go func() { migrationDone <- database.Migrate(f.Ctx, f.Pool) }()
	for {
		var waiting bool
		if err := f.Pool.QueryRow(f.Ctx, `
			SELECT EXISTS (SELECT 1 FROM pg_stat_activity
			WHERE application_name = $1 AND wait_event_type = 'Lock'
			AND cardinality(pg_blocking_pids(pid)) > 0)`,
			f.Config.ConnConfig.RuntimeParams["application_name"],
		).Scan(&waiting); err != nil {
			t.Fatal(err)
		}
		if waiting {
			break
		}
		select {
		case err := <-migrationDone:
			t.Fatalf("migration did not wait for the uncommitted sync writer: %v", err)
		case <-f.Ctx.Done():
			t.Fatal(f.Ctx.Err())
		case <-time.After(10 * time.Millisecond):
		}
	}
	gate.Release <- struct{}{}
	if err := <-writerDone; err != nil {
		t.Fatal(err)
	}
	if err := <-migrationDone; err != nil {
		t.Fatal(err)
	}
	pull, err := NewPostgresStore(f.Pool).Pull(f.Ctx, userID, 0, 100)
	if err != nil || len(pull.Changes) != 2 || pull.Changes[0].EntityID != projectID || pull.Changes[1].EntityID != policyID {
		t.Fatalf("migration cursor did not follow committed writer: result=%+v err=%v", pull, err)
	}
	if _, present := pull.Changes[1].Body["allowed_app_ids"]; present {
		t.Fatal("migration published application identities")
	}
}
