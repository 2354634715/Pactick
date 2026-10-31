package sync

import (
	"encoding/json"
	"strings"
	"testing"
)

func terminalFocusBody(status string) map[string]any {
	return map[string]any{
		"planned_duration_seconds": int64(1500),
		"started_at":               "2026-08-31T02:00:00Z",
		"ended_at":                 "2026-08-31T02:20:00Z",
		"actual_duration_seconds":  int64(1200),
		"started_device_id":        "7b87bbcb-dcb6-4d88-8a94-b115899b8307",
		"status":                   status,
		"time_zone":                "Asia/Shanghai",
	}
}

func TestTerminalFocusCanAssociateAnUnassignedTask(t *testing.T) {
	for _, status := range []string{"completed", "abandoned", "interrupted"} {
		t.Run(status, func(t *testing.T) {
			existing := terminalFocusBody(status)
			body := cloneMap(existing)
			body["task_id"] = "d89f2a7c-23c3-4e9a-b10d-62548765455c"
			if err := validateEntity("focus_session", existing, body, false); err != nil {
				t.Fatalf("associate task: %v", err)
			}
		})
	}
}

func TestTerminalFocusAssociationPreservesEveryOtherField(t *testing.T) {
	for field := range allowedFields["focus_session"] {
		if field == "task_id" {
			continue
		}
		t.Run(field, func(t *testing.T) {
			existing := terminalFocusBody("completed")
			body := cloneMap(existing)
			body["task_id"] = "d89f2a7c-23c3-4e9a-b10d-62548765455c"
			body[field] = "changed"
			if err := validateEntity("focus_session", existing, body, false); err == nil || !strings.Contains(err.Error(), field) {
				t.Fatalf("mutation of %s: error=%v", field, err)
			}
		})
	}
}

func TestTerminalFocusAssociationPreservesPauseHistory(t *testing.T) {
	existing := terminalFocusBody("completed")
	existing["paused_duration_seconds"] = int64(60)
	existing["pause_intervals"] = []any{map[string]any{
		"started_at": "2026-08-31T02:05:00Z",
		"ended_at":   "2026-08-31T02:06:00Z",
	}}
	body := cloneMap(existing)
	body["task_id"] = "d89f2a7c-23c3-4e9a-b10d-62548765455c"
	if err := validateEntity("focus_session", existing, body, false); err != nil {
		t.Fatalf("associate a task while retaining pause history: %v", err)
	}
	body = cloneMap(existing)
	body["task_id"] = "d89f2a7c-23c3-4e9a-b10d-62548765455c"
	body["pause_intervals"] = []any{}
	if err := validateEntity("focus_session", existing, body, false); err == nil || !strings.Contains(err.Error(), "pause_intervals") {
		t.Fatalf("cleared pause history: error=%v", err)
	}
}

func TestTerminalFocusAssociationAcceptsDecodedJSONPatches(t *testing.T) {
	stored := terminalFocusBody("completed")
	stored["paused_duration_seconds"] = int64(60)
	stored["pause_intervals"] = []any{map[string]any{
		"started_at": "2026-08-31T02:05:00Z",
		"ended_at":   "2026-08-31T02:06:00Z",
	}}
	storedJSON, err := json.Marshal(stored)
	if err != nil {
		t.Fatal(err)
	}
	for _, fullBody := range []bool{false, true} {
		name := "task_only"
		if fullBody {
			name = "full_body"
		}
		t.Run(name, func(t *testing.T) {
			existing, err := decodeObject(storedJSON)
			if err != nil {
				t.Fatal(err)
			}
			patch := map[string]any{"task_id": "d89f2a7c-23c3-4e9a-b10d-62548765455c"}
			if fullBody {
				for field, value := range stored {
					patch[field] = value
				}
				// Explicit null and omitted optional fields represent the same value.
				patch["plan_block_id"] = nil
			}
			patchJSON, err := json.Marshal(patch)
			if err != nil {
				t.Fatal(err)
			}
			decodedPatch, err := decodeObject(patchJSON)
			if err != nil {
				t.Fatal(err)
			}
			changedFields := make([]string, 0, len(decodedPatch))
			for field := range decodedPatch {
				changedFields = append(changedFields, field)
			}
			merged, err := mergeDocument(existing, nil, decodedPatch, changedFields, 1, 2)
			if err != nil {
				t.Fatal(err)
			}
			if err := validateEntity("focus_session", existing, merged.body, false); err != nil {
				t.Fatalf("associate task with a decoded JSON patch: %v", err)
			}
		})
	}
}

func TestTerminalFocusTaskCannotBeReplacedOrCleared(t *testing.T) {
	for _, taskID := range []any{nil, "d89f2a7c-23c3-4e9a-b10d-62548765455c", "e59e02da-aa75-49bf-9e15-1ba8042364f5"} {
		existing := terminalFocusBody("completed")
		existing["task_id"] = "d89f2a7c-23c3-4e9a-b10d-62548765455c"
		body := cloneMap(existing)
		body["task_id"] = taskID
		if err := validateEntity("focus_session", existing, body, false); err == nil {
			t.Fatalf("accepted change to an already associated session: task_id=%v", taskID)
		}
	}
}

func TestTerminalFocusAssociationRequiresAValidTaskID(t *testing.T) {
	for _, taskID := range []any{nil, "", "invalid-task-id"} {
		existing := terminalFocusBody("completed")
		body := cloneMap(existing)
		body["task_id"] = taskID
		if err := validateEntity("focus_session", existing, body, false); err == nil {
			t.Fatalf("accepted invalid task_id=%v", taskID)
		}
	}
}

func TestStaleTerminalFocusAssociationCannotOverwriteFirstAssociation(t *testing.T) {
	existing := terminalFocusBody("completed")
	existing["task_id"] = "d89f2a7c-23c3-4e9a-b10d-62548765455c"
	merged, err := mergeDocument(existing, map[string]int64{"task_id": 2}, map[string]any{
		"task_id": "e59e02da-aa75-49bf-9e15-1ba8042364f5",
	}, []string{"task_id"}, 1, 3)
	if err != nil {
		t.Fatal(err)
	}
	if len(merged.conflictFields) != 1 || merged.conflictFields[0] != "task_id" {
		t.Fatalf("expected a task association conflict, got %v", merged.conflictFields)
	}
	if err := validateEntity("focus_session", existing, merged.body, false); err == nil {
		t.Fatal("stale association overwrote the first association")
	}
}
