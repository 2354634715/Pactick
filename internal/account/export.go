package account

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"pactick/server/internal/auth"
)

type Service struct {
	pool *pgxpool.Pool
	now  func() time.Time
}

type DeviceExport struct {
	ID         string     `json:"id"`
	Name       string     `json:"name"`
	Platform   string     `json:"platform"`
	AppVersion string     `json:"app_version"`
	CreatedAt  time.Time  `json:"created_at"`
	LastSeenAt time.Time  `json:"last_seen_at"`
	RevokedAt  *time.Time `json:"revoked_at,omitempty"`
}

type EntityExport struct {
	EntityType string         `json:"entity_type"`
	ID         string         `json:"id"`
	Version    int64          `json:"version"`
	Body       map[string]any `json:"body"`
	Deleted    bool           `json:"deleted"`
	CreatedAt  time.Time      `json:"created_at"`
	UpdatedAt  time.Time      `json:"updated_at"`
}

type Export struct {
	FormatVersion int            `json:"format_version"`
	ExportedAt    time.Time      `json:"exported_at"`
	User          auth.User      `json:"user"`
	Devices       []DeviceExport `json:"devices"`
	Entities      []EntityExport `json:"entities"`
}

type entityTable struct {
	entityType string
	table      string
}

var exportTables = []entityTable{
	{"project", "projects"},
	{"task", "tasks"},
	{"task_recurrence_rule", "task_recurrence_rules"},
	{"tag", "tags"},
	{"task_tag", "task_tags"},
	{"plan_block", "plan_blocks"},
	{"day_entry", "day_plan_entries"},
	{"focus_policy", "focus_policies"},
	{"focus_session", "focus_sessions"},
	{"focus_interruption", "focus_interruptions"},
	{"reminder", "reminders"},
}

func NewService(pool *pgxpool.Pool) *Service {
	return &Service{pool: pool, now: time.Now}
}

func (s *Service) Build(ctx context.Context, userID string) (Export, error) {
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return Export{}, fmt.Errorf("begin account export: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var user auth.User
	err = tx.QueryRow(ctx, `
		SELECT id, email, display_name, time_zone, locale, week_starts_on, created_at
		FROM users WHERE id = $1 AND deleted_at IS NULL`, userID,
	).Scan(&user.ID, &user.Email, &user.DisplayName, &user.TimeZone, &user.Locale, &user.WeekStartsOn, &user.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Export{}, auth.ErrInvalidToken
	}
	if err != nil {
		return Export{}, fmt.Errorf("export user: %w", err)
	}
	result := Export{
		FormatVersion: 1,
		ExportedAt:    s.now().UTC(),
		User:          user,
		Devices:       make([]DeviceExport, 0),
		Entities:      make([]EntityExport, 0),
	}
	rows, err := tx.Query(ctx, `
		SELECT id, name, platform, app_version, created_at, last_seen_at, revoked_at
		FROM devices WHERE user_id = $1 ORDER BY created_at, id`, user.ID)
	if err != nil {
		return Export{}, fmt.Errorf("export devices: %w", err)
	}
	for rows.Next() {
		var device DeviceExport
		if err := rows.Scan(
			&device.ID, &device.Name, &device.Platform, &device.AppVersion,
			&device.CreatedAt, &device.LastSeenAt, &device.RevokedAt,
		); err != nil {
			rows.Close()
			return Export{}, fmt.Errorf("scan export device: %w", err)
		}
		result.Devices = append(result.Devices, device)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return Export{}, err
	}
	rows.Close()

	for _, item := range exportTables {
		query := fmt.Sprintf(`
			SELECT id, version, body, deleted_at IS NOT NULL, created_at, updated_at
			FROM %s WHERE user_id = $1 ORDER BY created_at, id`, item.table)
		rows, err := tx.Query(ctx, query, user.ID)
		if err != nil {
			return Export{}, fmt.Errorf("export %s: %w", item.entityType, err)
		}
		for rows.Next() {
			var entity EntityExport
			var raw []byte
			entity.EntityType = item.entityType
			if err := rows.Scan(
				&entity.ID, &entity.Version, &raw, &entity.Deleted, &entity.CreatedAt, &entity.UpdatedAt,
			); err != nil {
				rows.Close()
				return Export{}, fmt.Errorf("scan export %s: %w", item.entityType, err)
			}
			if err := json.Unmarshal(raw, &entity.Body); err != nil {
				rows.Close()
				return Export{}, fmt.Errorf("decode export %s: %w", item.entityType, err)
			}
			result.Entities = append(result.Entities, entity)
		}
		if err := rows.Err(); err != nil {
			rows.Close()
			return Export{}, err
		}
		rows.Close()
	}
	if err := tx.Commit(ctx); err != nil {
		return Export{}, fmt.Errorf("commit account export: %w", err)
	}
	return result, nil
}
