package account

import (
	"encoding/json"
	"errors"
	"testing"

	"github.com/google/uuid"

	"pactick/server/internal/auth"
	"pactick/server/internal/database"
	"pactick/server/internal/sync"
	"pactick/server/internal/testpostgres"
)

func TestPostgresExportUsesOneSnapshot(t *testing.T) {
	for _, pauseAfter := range []string{"FROM users", "FROM projects"} {
		t.Run(pauseAfter, func(t *testing.T) {
			f := testpostgres.New(t)
			if err := database.Migrate(f.Ctx, f.Pool); err != nil {
				t.Fatal(err)
			}
			userID, deviceID := f.Account(t)
			store := sync.NewPostgresStore(f.Pool)
			projectID, taskID := uuid.NewString(), uuid.NewString()
			apply := func(entityType, id string, fields []string, body map[string]any) {
				t.Helper()
				patch, _ := json.Marshal(body)
				result, err := store.Apply(f.Ctx, userID, deviceID, sync.Operation{
					OperationID: uuid.NewString(), EntityType: entityType, EntityID: id,
					Action: sync.ActionUpsert, ChangedFields: fields, Patch: patch,
				})
				if err != nil || result.Status != "applied" {
					t.Fatalf("seed %s: result=%+v err=%v", entityType, result, err)
				}
			}
			apply("project", projectID, []string{"name"}, map[string]any{"name": "Before"})
			apply("task", taskID, []string{"title", "priority", "status", "project_id"}, map[string]any{
				"title": "Before", "priority": "none", "status": "open", "project_id": projectID,
			})
			gate := testpostgres.NewQueryGate(pauseAfter)
			defer close(gate.Release)
			service := NewService(f.TracedPool(t, gate, "export"))
			type exportResult struct {
				data Export
				err  error
			}
			done := make(chan exportResult, 1)
			go func() {
				data, err := service.Build(f.Ctx, userID)
				done <- exportResult{data, err}
			}()
			gate.Wait(t, f.Ctx)
			// One committed transaction changes profile/device data, updates a
			// project, deletes an existing task and creates a new project/task pair.
			tx, err := f.Pool.Begin(f.Ctx)
			if err != nil {
				t.Fatal(err)
			}
			defer func() { _ = tx.Rollback(f.Ctx) }()
			if err := database.LockSyncWrites(f.Ctx, tx, userID); err != nil {
				t.Fatal(err)
			}
			for _, query := range []string{
				`UPDATE users SET display_name = 'After' WHERE id = $1`,
				`UPDATE devices SET name = 'After', revoked_at = now() WHERE user_id = $1`,
				`UPDATE projects SET body = '{"name":"After"}', version = version + 1 WHERE user_id = $1`,
				`UPDATE tasks SET deleted_at = now(), version = version + 1 WHERE user_id = $1`,
			} {
				if _, err := tx.Exec(f.Ctx, query, userID); err != nil {
					t.Fatal(err)
				}
			}
			newProjectID, newTaskID := uuid.NewString(), uuid.NewString()
			for _, item := range []struct{ table, id, body string }{
				{"projects", newProjectID, `{"name":"New"}`},
				{"tasks", newTaskID, `{"title":"New","priority":"none","status":"open","project_id":"` + newProjectID + `"}`},
			} {
				if _, err := tx.Exec(f.Ctx, `INSERT INTO `+item.table+`
					(id, user_id, body, version, created_at, updated_at, created_by_device_id, updated_by_device_id, last_change_seq)
					VALUES ($1, $2, $3, 1, now(), now(), $4, $4, nextval('sync_cursor_seq'))`,
					item.id, userID, item.body, deviceID,
				); err != nil {
					t.Fatal(err)
				}
			}
			if err := tx.Commit(f.Ctx); err != nil {
				t.Fatal(err)
			}
			gate.Release <- struct{}{}
			result := <-done
			if result.err != nil {
				t.Fatal(result.err)
			}
			if result.data.User.DisplayName != "Before" || len(result.data.Devices) != 1 ||
				result.data.Devices[0].Name != "Before" || result.data.Devices[0].RevokedAt != nil {
				t.Fatalf("profile/devices came from another snapshot: %+v", result.data)
			}
			if len(result.data.Entities) != 2 {
				t.Fatalf("export included newly committed entities: %+v", result.data.Entities)
			}
			for _, entity := range result.data.Entities {
				if entity.Version != 1 || entity.Deleted || (entity.ID != projectID && entity.ID != taskID) {
					t.Fatalf("export entity came from another snapshot: %+v", entity)
				}
				if entity.EntityType == "project" && entity.Body["name"] != "Before" {
					t.Fatalf("project update leaked into export: %+v", entity)
				}
				if entity.EntityType == "task" && entity.Body["project_id"] != projectID {
					t.Fatalf("task reference has no exported project: %+v", entity)
				}
			}
			latest, err := NewService(f.Pool).Build(f.Ctx, userID)
			if err != nil || latest.User.DisplayName != "After" || len(latest.Entities) != 4 {
				t.Fatalf("subsequent export did not see committed writes: result=%+v err=%v", latest, err)
			}
		})
	}
}

func TestPostgresExportMissingAccount(t *testing.T) {
	f := testpostgres.New(t)
	if err := database.Migrate(f.Ctx, f.Pool); err != nil {
		t.Fatal(err)
	}
	_, err := NewService(f.Pool).Build(f.Ctx, uuid.NewString())
	if !errors.Is(err, auth.ErrInvalidToken) {
		t.Fatalf("missing account error = %v", err)
	}
}
