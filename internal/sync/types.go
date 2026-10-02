package sync

import (
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

const (
	ActionUpsert = "upsert"
	ActionDelete = "delete"
)

var (
	ErrUnknownEntity       = errors.New("unknown entity type")
	ErrEntityNotFound      = errors.New("entity not found")
	ErrEntityExists        = errors.New("entity already exists")
	ErrEntityTombstoned    = errors.New("entity has been deleted")
	ErrFutureBaseVersion   = errors.New("base version is newer than server version")
	ErrActiveFocusExists   = errors.New("another focus session is active")
	ErrFocusSessionOverlap = errors.New("focus session overlaps another device session")
	ErrDuplicateRelation   = errors.New("an equivalent record already exists")
	ErrInvalidOperation    = errors.New("invalid sync operation")
	ErrDeviceUnauthorized  = errors.New("device is not active")
)

type Operation struct {
	OperationID     string          `json:"operation_id"`
	EntityType      string          `json:"entity_type"`
	EntityID        string          `json:"entity_id"`
	Action          string          `json:"action"`
	BaseVersion     int64           `json:"base_version"`
	ChangedFields   []string        `json:"changed_fields"`
	Patch           json.RawMessage `json:"patch,omitempty"`
	ClientChangedAt *time.Time      `json:"client_changed_at,omitempty"`
}

type Snapshot struct {
	EntityType string         `json:"entity_type"`
	EntityID   string         `json:"entity_id"`
	Version    int64          `json:"version"`
	Body       map[string]any `json:"body"`
	Deleted    bool           `json:"deleted"`
	UpdatedAt  time.Time      `json:"updated_at"`
	Cursor     int64          `json:"cursor"`
}

type OperationResult struct {
	OperationID    string    `json:"operation_id"`
	Status         string    `json:"status"`
	Snapshot       *Snapshot `json:"snapshot,omitempty"`
	ConflictFields []string  `json:"conflict_fields,omitempty"`
	Resolution     string    `json:"resolution,omitempty"`
	Error          *APIError `json:"error,omitempty"`
}

type PushResponse struct {
	Results       []OperationResult `json:"results"`
	CurrentCursor int64             `json:"current_cursor"`
}

type Change struct {
	Cursor          int64          `json:"cursor"`
	ChangeID        string         `json:"change_id"`
	EntityType      string         `json:"entity_type"`
	EntityID        string         `json:"entity_id"`
	Action          string         `json:"action"`
	Version         int64          `json:"version"`
	Body            map[string]any `json:"body"`
	ChangedFields   []string       `json:"changed_fields"`
	DeviceID        string         `json:"device_id"`
	ClientChangedAt *time.Time     `json:"client_changed_at,omitempty"`
	ChangedAt       time.Time      `json:"changed_at"`
}

type PullResponse struct {
	Changes       []Change `json:"changes"`
	NextCursor    int64    `json:"next_cursor"`
	CurrentCursor int64    `json:"current_cursor"`
	HasMore       bool     `json:"has_more"`
}

type APIError struct {
	Code    string         `json:"code"`
	Message string         `json:"message"`
	Details map[string]any `json:"details,omitempty"`
}

func (e *APIError) Error() string {
	return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

type ValidationError struct {
	Field   string
	Message string
}

func (e *ValidationError) Error() string {
	if e.Field == "" {
		return e.Message
	}
	return e.Field + ": " + e.Message
}
