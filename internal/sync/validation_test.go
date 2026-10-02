package sync

import (
	"strings"
	"testing"
)

func TestValidateTaskSeparatesDeadlineAndCompletion(t *testing.T) {
	body := map[string]any{
		"title":                      "Write report",
		"priority":                   "high",
		"status":                     "open",
		"due_at":                     "2026-08-31T10:00:00+08:00",
		"estimated_duration_seconds": int64(3600),
	}
	if err := validateEntity("task", nil, body, true); err != nil {
		t.Fatalf("validateEntity() error = %v", err)
	}
	if body["due_at"] != "2026-08-31T02:00:00Z" {
		t.Fatalf("due_at was not normalized to UTC: %v", body["due_at"])
	}
}

func TestValidatePlanBlockRequiresOrderedTimes(t *testing.T) {
	body := map[string]any{
		"title":     "Planning",
		"starts_at": "2026-08-31T12:00:00Z",
		"ends_at":   "2026-08-31T11:00:00Z",
		"time_zone": "Asia/Shanghai",
		"status":    "scheduled",
	}
	err := validateEntity("plan_block", nil, body, true)
	if err == nil || !strings.Contains(err.Error(), "ends_at") {
		t.Fatalf("validateEntity() error = %v", err)
	}
}

func TestValidateFocusSessionState(t *testing.T) {
	body := map[string]any{
		"planned_duration_seconds": int64(1500),
		"started_at":               "2026-08-31T02:00:00Z",
		"ended_at":                 "2026-08-31T02:20:00Z",
		"actual_duration_seconds":  int64(1200),
		"started_device_id":        "7b87bbcb-dcb6-4d88-8a94-b115899b8307",
		"status":                   "completed",
		"time_zone":                "Asia/Shanghai",
	}
	if err := validateEntity("focus_session", nil, body, true); err != nil {
		t.Fatalf("validateEntity() error = %v", err)
	}
	delete(body, "actual_duration_seconds")
	if err := validateEntity("focus_session", nil, body, true); err == nil {
		t.Fatal("validateEntity() accepted a terminal session without actual duration")
	}
}

func TestValidateFocusInterruptionRejectsApplicationIdentity(t *testing.T) {
	body := map[string]any{
		"focus_session_id": "d89f2a7c-23c3-4e9a-b10d-62548765455c",
		"kind":             "app_exit",
		"category":         "restricted",
		"started_at":       "2026-08-31T02:00:00Z",
		"app_id":           "example.private.application",
	}
	err := validateEntity("focus_interruption", nil, body, true)
	if err == nil || !strings.Contains(err.Error(), "app_id") {
		t.Fatalf("validateEntity() error = %v", err)
	}
}

func TestValidateFocusPolicyKeepsApplicationWhitelistDeviceLocal(t *testing.T) {
	body := map[string]any{
		"name":                     "守护专注",
		"mode":                     "guard",
		"allow_pause":              true,
		"early_exit_mode":          "reason",
		"max_app_exits":            int64(3),
		"allowed_app_ids":          []any{},
		"emergency_app_categories": []any{"phone", "maps", "authentication"},
		"notification_mode":        "vibrate",
	}
	if err := validateEntity("focus_policy", nil, body, true); err != nil {
		t.Fatalf("validateEntity() rejected an empty compatibility field: %v", err)
	}

	body["allowed_app_ids"] = []any{"com.example.private"}
	err := validateEntity("focus_policy", nil, body, true)
	if err == nil || !strings.Contains(err.Error(), "device-local") {
		t.Fatalf("validateEntity() error = %v", err)
	}
}

func TestFocusTransitionRejectsTerminalMutation(t *testing.T) {
	existing := map[string]any{"status": "completed"}
	body := map[string]any{
		"planned_duration_seconds": int64(1500),
		"started_at":               "2026-08-31T02:00:00Z",
		"ended_at":                 "2026-08-31T02:20:00Z",
		"actual_duration_seconds":  int64(1200),
		"started_device_id":        "7b87bbcb-dcb6-4d88-8a94-b115899b8307",
		"status":                   "completed",
		"time_zone":                "Asia/Shanghai",
	}
	if err := validateEntity("focus_session", existing, body, false); err == nil {
		t.Fatal("validateEntity() allowed mutation of a terminal focus session")
	}
}

func TestValidatePausedFocusTracksPauseInterval(t *testing.T) {
	body := map[string]any{
		"planned_duration_seconds": int64(1500),
		"started_at":               "2026-08-31T02:00:00Z",
		"pause_started_at":         "2026-08-31T02:10:00Z",
		"pause_intervals": []any{
			map[string]any{"started_at": "2026-08-31T02:10:00Z"},
		},
		"paused_duration_seconds": int64(0),
		"started_device_id":       "7b87bbcb-dcb6-4d88-8a94-b115899b8307",
		"status":                  "paused",
		"time_zone":               "Asia/Shanghai",
	}
	if err := validateEntity("focus_session", nil, body, true); err != nil {
		t.Fatalf("validateEntity() error = %v", err)
	}
	body["pause_started_at"] = "2026-08-31T02:11:00Z"
	if err := validateEntity("focus_session", nil, body, true); err == nil {
		t.Fatal("validateEntity() accepted a mismatched open pause interval")
	}
}

func TestValidateFocusSessionKeepsStartIdentity(t *testing.T) {
	existing := map[string]any{
		"planned_duration_seconds": int64(1500),
		"started_at":               "2026-08-31T02:00:00Z",
		"started_device_id":        "7b87bbcb-dcb6-4d88-8a94-b115899b8307",
		"status":                   "running",
		"time_zone":                "Asia/Shanghai",
	}
	body := cloneMap(existing)
	body["started_at"] = "2026-08-31T02:01:00Z"
	if err := validateEntity("focus_session", existing, body, false); err == nil {
		t.Fatal("validateEntity() allowed started_at to change")
	}
}
