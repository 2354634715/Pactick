package sync

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

var colorPattern = regexp.MustCompile(`^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$`)

var allowedFields = map[string]map[string]struct{}{
	"project": fields("name", "color", "archived", "sort_order"),
	"task": fields(
		"title", "note", "project_id", "priority", "due_at", "estimated_duration_seconds",
		"status", "completed_at", "recurrence_rule_id", "recurrence_source_task_id", "occurrence_date",
	),
	"task_recurrence_rule": fields(
		"task_id", "frequency", "interval", "days_of_week", "day_of_month", "starts_on",
		"ends_on", "max_occurrences", "time_zone",
	),
	"tag":      fields("name", "color"),
	"task_tag": fields("task_id", "tag_id"),
	"plan_block": fields(
		"task_id", "title", "starts_at", "ends_at", "time_zone", "status", "original_plan_block_id",
	),
	"day_entry": fields(
		"local_date", "task_id", "plan_block_id", "title", "source", "rank", "status", "deferred_from_date",
	),
	"focus_policy": fields(
		"name", "mode", "allow_pause", "early_exit_mode", "early_exit_wait_seconds", "max_app_exits",
		"allowed_app_ids", "emergency_app_categories", "notification_mode", "sound_enabled", "vibration_enabled",
	),
	"focus_session": fields(
		"task_id", "plan_block_id", "focus_policy_id", "planned_duration_seconds", "started_at", "ended_at",
		"pause_started_at", "pause_intervals", "paused_duration_seconds", "actual_duration_seconds", "started_device_id", "status",
		"termination_reason", "time_zone", "app_exit_count", "interruption_count",
	),
	"focus_interruption": fields(
		"focus_session_id", "kind", "category", "started_at", "ended_at", "duration_seconds",
	),
	"reminder": fields(
		"target_type", "target_id", "trigger_at", "time_zone", "status", "delivery_mode",
	),
}

func validateEntity(entityType string, existing, body map[string]any, isCreate bool) error {
	allowed, ok := allowedFields[entityType]
	if !ok {
		return ErrUnknownEntity
	}
	for field := range body {
		if _, exists := allowed[field]; !exists {
			return &ValidationError{Field: field, Message: "is not supported for " + entityType}
		}
	}
	if !isCreate {
		switch entityType {
		case "task_tag", "focus_interruption":
			return &ValidationError{Message: entityType + " records are immutable; delete and create a new record instead"}
		case "focus_session":
			if status, _ := stringValue(existing, "status"); isTerminalFocusStatus(status) {
				return &ValidationError{Field: "status", Message: "a terminal focus session is immutable"}
			}
		}
	}

	var err error
	switch entityType {
	case "project":
		err = validateProject(body)
	case "task":
		err = validateTask(body)
	case "task_recurrence_rule":
		err = validateRecurrence(body)
	case "tag":
		err = validateTag(body)
	case "task_tag":
		err = validateTaskTag(body)
	case "plan_block":
		err = validatePlanBlock(body)
	case "day_entry":
		err = validateDayEntry(body)
	case "focus_policy":
		err = validateFocusPolicy(body)
	case "focus_session":
		err = validateFocusSession(existing, body, isCreate)
	case "focus_interruption":
		err = validateFocusInterruption(body)
	case "reminder":
		err = validateReminder(body)
	}
	if err != nil || isCreate {
		return err
	}
	switch entityType {
	case "task":
		return ensureFieldsUnchanged(existing, body, "recurrence_source_task_id", "occurrence_date")
	case "task_recurrence_rule":
		return ensureFieldsUnchanged(existing, body, "task_id")
	case "focus_session":
		return ensureFieldsUnchanged(existing, body, "started_at", "started_device_id")
	default:
		return nil
	}
}

func validateProject(body map[string]any) error {
	if _, err := requiredString(body, "name", 1, 120); err != nil {
		return err
	}
	if err := optionalColor(body, "color"); err != nil {
		return err
	}
	if err := optionalBool(body, "archived"); err != nil {
		return err
	}
	return optionalInteger(body, "sort_order", -1_000_000_000, 1_000_000_000)
}

func validateTask(body map[string]any) error {
	if _, err := requiredString(body, "title", 1, 500); err != nil {
		return err
	}
	if err := optionalString(body, "note", 50_000); err != nil {
		return err
	}
	if err := optionalUUID(body, "project_id"); err != nil {
		return err
	}
	if err := requiredEnum(body, "priority", "none", "low", "medium", "high", "urgent"); err != nil {
		return err
	}
	if _, err := optionalTimestamp(body, "due_at"); err != nil {
		return err
	}
	if err := optionalInteger(body, "estimated_duration_seconds", 0, 31*24*60*60); err != nil {
		return err
	}
	status, err := requiredString(body, "status", 1, 20)
	if err != nil {
		return err
	}
	if !contains([]string{"open", "completed", "cancelled"}, status) {
		return fieldError("status", "must be open, completed, or cancelled")
	}
	completedAt, err := optionalTimestamp(body, "completed_at")
	if err != nil {
		return err
	}
	if status == "completed" && completedAt == nil {
		return fieldError("completed_at", "is required when status is completed")
	}
	if status != "completed" && completedAt != nil {
		return fieldError("completed_at", "must be absent unless status is completed")
	}
	if err := optionalUUID(body, "recurrence_rule_id"); err != nil {
		return err
	}
	if err := optionalUUID(body, "recurrence_source_task_id"); err != nil {
		return err
	}
	if err := optionalDate(body, "occurrence_date"); err != nil {
		return err
	}
	if (body["recurrence_source_task_id"] == nil) != (body["occurrence_date"] == nil) {
		return fieldError("occurrence_date", "must be present together with recurrence_source_task_id")
	}
	return nil
}

func validateRecurrence(body map[string]any) error {
	if err := requiredUUID(body, "task_id"); err != nil {
		return err
	}
	frequency, err := requiredString(body, "frequency", 1, 20)
	if err != nil {
		return err
	}
	if !contains([]string{"daily", "weekly", "monthly"}, frequency) {
		return fieldError("frequency", "must be daily, weekly, or monthly")
	}
	if err := requiredInteger(body, "interval", 1, 365); err != nil {
		return err
	}
	if err := optionalIntegerArray(body, "days_of_week", 0, 6, 7); err != nil {
		return err
	}
	if err := optionalInteger(body, "day_of_month", 1, 31); err != nil {
		return err
	}
	if err := requiredDate(body, "starts_on"); err != nil {
		return err
	}
	if err := optionalDate(body, "ends_on"); err != nil {
		return err
	}
	if err := optionalInteger(body, "max_occurrences", 1, 100_000); err != nil {
		return err
	}
	if err := requiredTimeZone(body, "time_zone"); err != nil {
		return err
	}
	if frequency == "weekly" {
		values, present := body["days_of_week"]
		if !present || values == nil || len(values.([]int64)) == 0 {
			return fieldError("days_of_week", "is required for a weekly rule")
		}
	}
	if frequency == "monthly" {
		if _, present := body["day_of_month"]; !present {
			return fieldError("day_of_month", "is required for a monthly rule")
		}
	}
	return nil
}

func validateTag(body map[string]any) error {
	if _, err := requiredString(body, "name", 1, 80); err != nil {
		return err
	}
	return optionalColor(body, "color")
}

func validateTaskTag(body map[string]any) error {
	if err := requiredUUID(body, "task_id"); err != nil {
		return err
	}
	return requiredUUID(body, "tag_id")
}

func validatePlanBlock(body map[string]any) error {
	if err := optionalUUID(body, "task_id"); err != nil {
		return err
	}
	if err := optionalString(body, "title", 500); err != nil {
		return err
	}
	if body["task_id"] == nil {
		if _, err := requiredString(body, "title", 1, 500); err != nil {
			return fieldError("title", "is required when task_id is absent")
		}
	}
	startsAt, err := requiredTimestamp(body, "starts_at")
	if err != nil {
		return err
	}
	endsAt, err := requiredTimestamp(body, "ends_at")
	if err != nil {
		return err
	}
	if !endsAt.After(startsAt) {
		return fieldError("ends_at", "must be after starts_at")
	}
	if endsAt.Sub(startsAt) > 7*24*time.Hour {
		return fieldError("ends_at", "a plan block cannot span more than seven days")
	}
	if err := requiredTimeZone(body, "time_zone"); err != nil {
		return err
	}
	if err := requiredEnum(body, "status", "scheduled", "completed", "cancelled"); err != nil {
		return err
	}
	return optionalUUID(body, "original_plan_block_id")
}

func validateDayEntry(body map[string]any) error {
	if err := requiredDate(body, "local_date"); err != nil {
		return err
	}
	if err := optionalUUID(body, "task_id"); err != nil {
		return err
	}
	if err := optionalUUID(body, "plan_block_id"); err != nil {
		return err
	}
	if err := optionalString(body, "title", 500); err != nil {
		return err
	}
	if body["task_id"] == nil && body["plan_block_id"] == nil {
		if _, err := requiredString(body, "title", 1, 500); err != nil {
			return fieldError("title", "is required when no task or plan block is linked")
		}
	}
	if err := requiredEnum(body, "source", "planned", "manual"); err != nil {
		return err
	}
	if _, err := requiredString(body, "rank", 1, 100); err != nil {
		return err
	}
	if err := requiredEnum(body, "status", "pending", "completed", "deferred", "skipped"); err != nil {
		return err
	}
	return optionalDate(body, "deferred_from_date")
}

func validateFocusPolicy(body map[string]any) error {
	if _, err := requiredString(body, "name", 1, 120); err != nil {
		return err
	}
	if err := requiredEnum(body, "mode", "normal", "guard", "strict"); err != nil {
		return err
	}
	if err := requiredBool(body, "allow_pause"); err != nil {
		return err
	}
	if err := requiredEnum(body, "early_exit_mode", "allow", "reason", "countdown"); err != nil {
		return err
	}
	if err := optionalInteger(body, "early_exit_wait_seconds", 0, 300); err != nil {
		return err
	}
	if err := optionalInteger(body, "max_app_exits", 0, 1000); err != nil {
		return err
	}
	if err := optionalStringArray(body, "allowed_app_ids", 500, 300); err != nil {
		return err
	}
	if appIDs, ok := body["allowed_app_ids"].([]string); ok && len(appIDs) > 0 {
		return fieldError(
			"allowed_app_ids",
			"must be empty; application identifiers and project whitelists are device-local and must not be synchronized",
		)
	}
	if err := optionalStringArray(body, "emergency_app_categories", 30, 20); err != nil {
		return err
	}
	if err := requiredEnum(body, "notification_mode", "silent", "sound", "vibrate", "sound_and_vibrate"); err != nil {
		return err
	}
	if err := optionalBool(body, "sound_enabled"); err != nil {
		return err
	}
	return optionalBool(body, "vibration_enabled")
}

func validateFocusSession(existing, body map[string]any, isCreate bool) error {
	for _, field := range []string{"task_id", "plan_block_id", "focus_policy_id"} {
		if err := optionalUUID(body, field); err != nil {
			return err
		}
	}
	if err := requiredInteger(body, "planned_duration_seconds", 1, 7*24*60*60); err != nil {
		return err
	}
	startedAt, err := requiredTimestamp(body, "started_at")
	if err != nil {
		return err
	}
	endedAt, err := optionalTimestamp(body, "ended_at")
	if err != nil {
		return err
	}
	pauseStartedAt, err := optionalTimestamp(body, "pause_started_at")
	if err != nil {
		return err
	}
	for _, field := range []string{"paused_duration_seconds", "actual_duration_seconds", "app_exit_count", "interruption_count"} {
		if err := optionalInteger(body, field, 0, 365*24*60*60); err != nil {
			return err
		}
	}
	if err := requiredUUID(body, "started_device_id"); err != nil {
		return err
	}
	status, err := requiredString(body, "status", 1, 20)
	if err != nil {
		return err
	}
	if !contains([]string{"running", "paused", "completed", "abandoned", "interrupted"}, status) {
		return fieldError("status", "is not a supported focus state")
	}
	if !isCreate {
		oldStatus, _ := stringValue(existing, "status")
		if !validFocusTransition(oldStatus, status) {
			return fieldError("status", fmt.Sprintf("cannot transition from %s to %s", oldStatus, status))
		}
	}
	if isTerminalFocusStatus(status) {
		if endedAt == nil {
			return fieldError("ended_at", "is required for a terminal focus state")
		}
		if endedAt.Before(startedAt) {
			return fieldError("ended_at", "must not be before started_at")
		}
		if _, present := body["actual_duration_seconds"]; !present {
			return fieldError("actual_duration_seconds", "is required for a terminal focus state")
		}
		if body["pause_started_at"] != nil {
			return fieldError("pause_started_at", "must be absent for a terminal focus state")
		}
	} else if endedAt != nil {
		return fieldError("ended_at", "must be absent while focus is active")
	}
	if status == "paused" && body["pause_started_at"] == nil {
		return fieldError("pause_started_at", "is required while focus is paused")
	}
	if status == "running" && body["pause_started_at"] != nil {
		return fieldError("pause_started_at", "must be absent while focus is running")
	}
	if err := validatePauseIntervals(body, status, startedAt, endedAt, pauseStartedAt); err != nil {
		return err
	}
	if err := optionalString(body, "termination_reason", 1000); err != nil {
		return err
	}
	return requiredTimeZone(body, "time_zone")
}

func validatePauseIntervals(body map[string]any, status string, sessionStart time.Time, sessionEnd, pauseStartedAt *time.Time) error {
	value, exists := body["pause_intervals"]
	if !exists || value == nil {
		if status == "paused" {
			return fieldError("pause_intervals", "must contain the active pause while focus is paused")
		}
		if pausedSeconds, ok := integerValue(body["paused_duration_seconds"]); ok && pausedSeconds > 0 {
			return fieldError("pause_intervals", "is required when paused_duration_seconds is greater than zero")
		}
		return nil
	}
	items, ok := value.([]any)
	if !ok {
		return fieldError("pause_intervals", "must be an array")
	}
	if len(items) > 1000 {
		return fieldError("pause_intervals", "cannot contain more than 1000 intervals")
	}
	normalized := make([]map[string]any, 0, len(items))
	var previousEnd *time.Time
	var openStart *time.Time
	for index, item := range items {
		interval, ok := item.(map[string]any)
		if !ok {
			return fieldError("pause_intervals", "items must be objects")
		}
		for key := range interval {
			if key != "started_at" && key != "ended_at" {
				return fieldError("pause_intervals", "items may only contain started_at and ended_at")
			}
		}
		intervalStart, err := requiredTimestamp(interval, "started_at")
		if err != nil {
			return fieldError("pause_intervals", fmt.Sprintf("item %d has an invalid started_at", index))
		}
		if intervalStart.Before(sessionStart) {
			return fieldError("pause_intervals", "an interval starts before the focus session")
		}
		if previousEnd != nil && intervalStart.Before(*previousEnd) {
			return fieldError("pause_intervals", "intervals must be ordered and must not overlap")
		}
		intervalEnd, err := optionalTimestamp(interval, "ended_at")
		if err != nil {
			return fieldError("pause_intervals", fmt.Sprintf("item %d has an invalid ended_at", index))
		}
		if intervalEnd == nil {
			if index != len(items)-1 {
				return fieldError("pause_intervals", "only the final interval may be open")
			}
			openStart = &intervalStart
		} else {
			if intervalEnd.Before(intervalStart) {
				return fieldError("pause_intervals", "an interval ends before it starts")
			}
			if sessionEnd != nil && intervalEnd.After(*sessionEnd) {
				return fieldError("pause_intervals", "an interval ends after the focus session")
			}
			endCopy := *intervalEnd
			previousEnd = &endCopy
		}
		normalized = append(normalized, interval)
	}
	if status == "paused" {
		if openStart == nil || pauseStartedAt == nil || !openStart.Equal(*pauseStartedAt) {
			return fieldError("pause_intervals", "the open interval must match pause_started_at")
		}
	} else if openStart != nil {
		return fieldError("pause_intervals", "must not contain an open interval unless focus is paused")
	}
	body["pause_intervals"] = normalized
	return nil
}

func validateFocusInterruption(body map[string]any) error {
	if err := requiredUUID(body, "focus_session_id"); err != nil {
		return err
	}
	if err := requiredEnum(body, "kind", "app_exit", "phone", "unlock", "permission_disabled", "clock_change", "process_recovered", "manual"); err != nil {
		return err
	}
	if err := requiredEnum(body, "category", "emergency", "allowed", "restricted", "unknown"); err != nil {
		return err
	}
	startedAt, err := requiredTimestamp(body, "started_at")
	if err != nil {
		return err
	}
	endedAt, err := optionalTimestamp(body, "ended_at")
	if err != nil {
		return err
	}
	if endedAt != nil && endedAt.Before(startedAt) {
		return fieldError("ended_at", "must not be before started_at")
	}
	return optionalInteger(body, "duration_seconds", 0, 7*24*60*60)
}

func validateReminder(body map[string]any) error {
	if err := requiredEnum(body, "target_type", "task", "plan_block"); err != nil {
		return err
	}
	if err := requiredUUID(body, "target_id"); err != nil {
		return err
	}
	if _, err := requiredTimestamp(body, "trigger_at"); err != nil {
		return err
	}
	if err := requiredTimeZone(body, "time_zone"); err != nil {
		return err
	}
	if err := requiredEnum(body, "status", "scheduled", "fired", "dismissed", "cancelled"); err != nil {
		return err
	}
	return requiredEnum(body, "delivery_mode", "local")
}

func fields(names ...string) map[string]struct{} {
	result := make(map[string]struct{}, len(names))
	for _, name := range names {
		result[name] = struct{}{}
	}
	return result
}

func requiredString(body map[string]any, field string, minimum, maximum int) (string, error) {
	value, ok := stringValue(body, field)
	if !ok {
		return "", fieldError(field, "is required and must be a string")
	}
	length := utf8.RuneCountInString(strings.TrimSpace(value))
	if length < minimum || length > maximum {
		return "", fieldError(field, fmt.Sprintf("must contain between %d and %d characters", minimum, maximum))
	}
	body[field] = strings.TrimSpace(value)
	return body[field].(string), nil
}

func optionalString(body map[string]any, field string, maximum int) error {
	value, exists := body[field]
	if !exists || value == nil {
		return nil
	}
	text, ok := value.(string)
	if !ok {
		return fieldError(field, "must be a string")
	}
	if utf8.RuneCountInString(text) > maximum {
		return fieldError(field, fmt.Sprintf("must contain at most %d characters", maximum))
	}
	return nil
}

func stringValue(body map[string]any, field string) (string, bool) {
	value, exists := body[field]
	if !exists || value == nil {
		return "", false
	}
	text, ok := value.(string)
	return text, ok
}

func requiredEnum(body map[string]any, field string, allowed ...string) error {
	value, err := requiredString(body, field, 1, 100)
	if err != nil {
		return err
	}
	if !contains(allowed, value) {
		return fieldError(field, "must be one of: "+strings.Join(allowed, ", "))
	}
	return nil
}

func requiredBool(body map[string]any, field string) error {
	value, exists := body[field]
	if !exists {
		return fieldError(field, "is required")
	}
	if _, ok := value.(bool); !ok {
		return fieldError(field, "must be a boolean")
	}
	return nil
}

func optionalBool(body map[string]any, field string) error {
	value, exists := body[field]
	if !exists || value == nil {
		return nil
	}
	if _, ok := value.(bool); !ok {
		return fieldError(field, "must be a boolean")
	}
	return nil
}

func requiredUUID(body map[string]any, field string) error {
	value, err := requiredString(body, field, 1, 50)
	if err != nil {
		return err
	}
	if _, err := uuid.Parse(value); err != nil {
		return fieldError(field, "must be a UUID")
	}
	return nil
}

func optionalUUID(body map[string]any, field string) error {
	value, exists := body[field]
	if !exists || value == nil {
		return nil
	}
	text, ok := value.(string)
	if !ok {
		return fieldError(field, "must be a UUID or null")
	}
	if _, err := uuid.Parse(text); err != nil {
		return fieldError(field, "must be a UUID or null")
	}
	return nil
}

func requiredInteger(body map[string]any, field string, minimum, maximum int64) error {
	value, exists := body[field]
	if !exists || value == nil {
		return fieldError(field, "is required")
	}
	integer, ok := integerValue(value)
	if !ok || integer < minimum || integer > maximum {
		return fieldError(field, fmt.Sprintf("must be an integer between %d and %d", minimum, maximum))
	}
	body[field] = integer
	return nil
}

func optionalInteger(body map[string]any, field string, minimum, maximum int64) error {
	value, exists := body[field]
	if !exists || value == nil {
		return nil
	}
	integer, ok := integerValue(value)
	if !ok || integer < minimum || integer > maximum {
		return fieldError(field, fmt.Sprintf("must be an integer between %d and %d", minimum, maximum))
	}
	body[field] = integer
	return nil
}

func integerValue(value any) (int64, bool) {
	switch number := value.(type) {
	case json.Number:
		integer, err := number.Int64()
		return integer, err == nil
	case int:
		return int64(number), true
	case int64:
		return number, true
	case float64:
		if math.Trunc(number) != number || number > math.MaxInt64 || number < math.MinInt64 {
			return 0, false
		}
		return int64(number), true
	default:
		return 0, false
	}
}

func optionalIntegerArray(body map[string]any, field string, minimum, maximum int64, maxItems int) error {
	value, exists := body[field]
	if !exists || value == nil {
		return nil
	}
	items, ok := value.([]any)
	if !ok {
		if converted, already := value.([]int64); already {
			if len(converted) > maxItems {
				return fieldError(field, "contains too many items")
			}
			return nil
		}
		return fieldError(field, "must be an array of integers")
	}
	if len(items) > maxItems {
		return fieldError(field, "contains too many items")
	}
	result := make([]int64, 0, len(items))
	seen := map[int64]struct{}{}
	for _, item := range items {
		integer, valid := integerValue(item)
		if !valid || integer < minimum || integer > maximum {
			return fieldError(field, fmt.Sprintf("items must be integers between %d and %d", minimum, maximum))
		}
		if _, duplicate := seen[integer]; !duplicate {
			seen[integer] = struct{}{}
			result = append(result, integer)
		}
	}
	sort.Slice(result, func(i, j int) bool { return result[i] < result[j] })
	body[field] = result
	return nil
}

func optionalStringArray(body map[string]any, field string, maxLength, maxItems int) error {
	value, exists := body[field]
	if !exists || value == nil {
		return nil
	}
	items, ok := value.([]any)
	if !ok {
		return fieldError(field, "must be an array of strings")
	}
	if len(items) > maxItems {
		return fieldError(field, "contains too many items")
	}
	result := make([]string, 0, len(items))
	seen := map[string]struct{}{}
	for _, item := range items {
		text, ok := item.(string)
		if !ok || text == "" || utf8.RuneCountInString(text) > maxLength {
			return fieldError(field, fmt.Sprintf("items must be non-empty strings of at most %d characters", maxLength))
		}
		if _, duplicate := seen[text]; !duplicate {
			seen[text] = struct{}{}
			result = append(result, text)
		}
	}
	body[field] = result
	return nil
}

func requiredTimestamp(body map[string]any, field string) (time.Time, error) {
	value, err := requiredString(body, field, 1, 50)
	if err != nil {
		return time.Time{}, err
	}
	parsed, err := time.Parse(time.RFC3339Nano, value)
	if err != nil {
		return time.Time{}, fieldError(field, "must be an RFC 3339 timestamp")
	}
	parsed = parsed.UTC()
	body[field] = parsed.Format(time.RFC3339Nano)
	return parsed, nil
}

func optionalTimestamp(body map[string]any, field string) (*time.Time, error) {
	value, exists := body[field]
	if !exists || value == nil {
		return nil, nil
	}
	text, ok := value.(string)
	if !ok {
		return nil, fieldError(field, "must be an RFC 3339 timestamp or null")
	}
	parsed, err := time.Parse(time.RFC3339Nano, text)
	if err != nil {
		return nil, fieldError(field, "must be an RFC 3339 timestamp or null")
	}
	parsed = parsed.UTC()
	body[field] = parsed.Format(time.RFC3339Nano)
	return &parsed, nil
}

func requiredDate(body map[string]any, field string) error {
	value, err := requiredString(body, field, 10, 10)
	if err != nil {
		return err
	}
	parsed, err := time.Parse("2006-01-02", value)
	if err != nil || parsed.Format("2006-01-02") != value {
		return fieldError(field, "must be a calendar date in YYYY-MM-DD format")
	}
	return nil
}

func optionalDate(body map[string]any, field string) error {
	value, exists := body[field]
	if !exists || value == nil {
		return nil
	}
	text, ok := value.(string)
	if !ok {
		return fieldError(field, "must be a calendar date or null")
	}
	parsed, err := time.Parse("2006-01-02", text)
	if err != nil || parsed.Format("2006-01-02") != text {
		return fieldError(field, "must be a calendar date in YYYY-MM-DD format")
	}
	return nil
}

func requiredTimeZone(body map[string]any, field string) error {
	value, err := requiredString(body, field, 1, 100)
	if err != nil {
		return err
	}
	if _, err := time.LoadLocation(value); err != nil {
		return fieldError(field, "must be an IANA time zone")
	}
	return nil
}

func optionalColor(body map[string]any, field string) error {
	value, exists := body[field]
	if !exists || value == nil {
		return nil
	}
	text, ok := value.(string)
	if !ok || !colorPattern.MatchString(text) {
		return fieldError(field, "must be a hex color such as #3B82F6")
	}
	return nil
}

func validFocusTransition(from, to string) bool {
	if from == to {
		return true
	}
	switch from {
	case "running":
		return contains([]string{"paused", "completed", "abandoned", "interrupted"}, to)
	case "paused":
		return contains([]string{"running", "completed", "abandoned", "interrupted"}, to)
	default:
		return false
	}
}

func isTerminalFocusStatus(status string) bool {
	return status == "completed" || status == "abandoned" || status == "interrupted"
}

func contains(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

func fieldError(field, message string) error {
	return &ValidationError{Field: field, Message: message}
}

func validationDetails(err error) map[string]any {
	var validationErr *ValidationError
	if errors.As(err, &validationErr) && validationErr.Field != "" {
		return map[string]any{"field": validationErr.Field}
	}
	return nil
}

func ensureFieldsUnchanged(existing, body map[string]any, fields ...string) error {
	for _, field := range fields {
		if !reflect.DeepEqual(existing[field], body[field]) {
			return fieldError(field, "cannot be changed after creation")
		}
	}
	return nil
}
