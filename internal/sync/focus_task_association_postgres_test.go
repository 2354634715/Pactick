package sync

import (
	"encoding/json"
	"reflect"
	"testing"

	"github.com/google/uuid"

	"pactick/server/internal/database"
	"pactick/server/internal/testpostgres"
)

func TestPostgresTerminalFocusTaskAssociation(t *testing.T) {
	f := testpostgres.New(t)
	if err := database.Migrate(f.Ctx, f.Pool); err != nil {
		t.Fatal(err)
	}
	userID, deviceID := f.Account(t)
	otherUserID, otherUserDeviceID := f.Account(t)
	store := NewPostgresStore(f.Pool)
	create := func(account, device, entityType, id string, body map[string]any) OperationResult {
		t.Helper()
		patch, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		changed := make([]string, 0, len(body))
		for field := range body {
			changed = append(changed, field)
		}
		result, err := store.Apply(f.Ctx, account, device, Operation{
			OperationID: uuid.NewString(), EntityType: entityType, EntityID: id,
			Action: ActionUpsert, Patch: patch, ChangedFields: changed,
		})
		if err != nil || result.Status != "applied" {
			t.Fatalf("create %s: result=%+v error=%v", entityType, result, err)
		}
		return result
	}
	taskID, deletedTaskID, alienTaskID := uuid.NewString(), uuid.NewString(), uuid.NewString()
	taskBody := map[string]any{"title": "After focus", "priority": "none", "status": "open"}
	create(userID, deviceID, "task", taskID, taskBody)
	create(userID, deviceID, "task", deletedTaskID, taskBody)
	create(otherUserID, otherUserDeviceID, "task", alienTaskID, taskBody)
	deleted, err := store.Apply(f.Ctx, userID, deviceID, Operation{
		OperationID: uuid.NewString(), EntityType: "task", EntityID: deletedTaskID,
		Action: ActionDelete, BaseVersion: 1,
	})
	if err != nil || deleted.Status != "applied" {
		t.Fatalf("delete target task: result=%+v error=%v", deleted, err)
	}
	sessionID := uuid.NewString()
	body := terminalFocusBody("completed")
	body["started_device_id"] = deviceID
	body["paused_duration_seconds"] = int64(60)
	body["pause_intervals"] = []any{map[string]any{
		"started_at": "2026-08-31T02:05:00Z",
		"ended_at":   "2026-08-31T02:06:00Z",
	}}
	created := create(userID, deviceID, "focus_session", sessionID, body)
	associate := func(target string) Operation {
		patch, _ := json.Marshal(map[string]any{"task_id": target})
		return Operation{
			OperationID: uuid.NewString(), EntityType: "focus_session", EntityID: sessionID,
			Action: ActionUpsert, BaseVersion: 1, ChangedFields: []string{"task_id"}, Patch: patch,
		}
	}
	for _, target := range []string{uuid.NewString(), alienTaskID, deletedTaskID} {
		result, err := store.Apply(f.Ctx, userID, deviceID, associate(target))
		if err != nil || result.Status != "rejected" || result.Error == nil || result.Error.Code != "validation_error" {
			t.Fatalf("invalid target %s: result=%+v error=%v", target, result, err)
		}
	}
	otherDeviceID := uuid.NewString()
	if _, err := f.Pool.Exec(f.Ctx, `
		INSERT INTO devices (id, user_id, name, platform) VALUES ($1, $2, 'Other', 'android')`, otherDeviceID, userID,
	); err != nil {
		t.Fatal(err)
	}
	result, err := store.Apply(f.Ctx, userID, otherDeviceID, associate(taskID))
	if err != nil || result.Error == nil || result.Error.Code != "focus_device_mismatch" {
		t.Fatalf("other device association: result=%+v error=%v", result, err)
	}
	operation := associate(taskID)
	associated, err := store.Apply(f.Ctx, userID, deviceID, operation)
	if err != nil || associated.Status != "applied" || associated.Snapshot.Version != 2 || associated.Snapshot.Body["task_id"] != taskID {
		t.Fatalf("associate task: result=%+v error=%v", associated, err)
	}
	for field, value := range created.Snapshot.Body {
		if !reflect.DeepEqual(value, associated.Snapshot.Body[field]) {
			t.Fatalf("association changed %s: before=%v after=%v", field, value, associated.Snapshot.Body[field])
		}
	}
	replayed, err := store.Apply(f.Ctx, userID, deviceID, operation)
	if err != nil || replayed.Snapshot == nil || replayed.Snapshot.Version != 2 {
		t.Fatalf("association retry: result=%+v error=%v", replayed, err)
	}
	result, err = store.Apply(f.Ctx, userID, deviceID, associate(deletedTaskID))
	if err != nil || result.Status != "rejected" || result.Error == nil || result.Error.Code != "validation_error" {
		t.Fatalf("stale reassignment: result=%+v error=%v", result, err)
	}
	pull, err := store.Pull(f.Ctx, userID, created.Snapshot.Cursor, 100)
	if err != nil || len(pull.Changes) != 1 || pull.Changes[0].EntityID != sessionID || pull.Changes[0].Body["task_id"] != taskID {
		t.Fatalf("association published once: response=%+v error=%v", pull, err)
	}
	var sessions, actual int64
	if err := f.Pool.QueryRow(f.Ctx, `
		SELECT count(*), sum((body ->> 'actual_duration_seconds')::bigint)
		FROM focus_sessions WHERE user_id = $1 AND body ->> 'task_id' = $2`, userID, taskID,
	).Scan(&sessions, &actual); err != nil || sessions != 1 || actual != 1200 {
		t.Fatalf("associated actual time: sessions=%d seconds=%d error=%v", sessions, actual, err)
	}
}
