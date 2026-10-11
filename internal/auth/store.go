package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Store interface {
	CreateAccount(context.Context, User, string, Device, RefreshRecord) error
	FindUserByEmail(context.Context, string) (User, string, error)
	CreateSession(context.Context, string, Device, RefreshRecord) error
	RotateRefreshToken(context.Context, []byte, RefreshRecord) (User, Device, error)
	RevokeRefreshToken(context.Context, []byte) error
	GetUser(context.Context, string) (User, error)
	UpdateUser(context.Context, string, ProfileUpdate) (User, error)
	ListDevices(context.Context, string) ([]DeviceInfo, error)
	RevokeDevice(context.Context, string, string) error
	IsDeviceActive(context.Context, string, string) (bool, error)
	GetPasswordHash(context.Context, string) (string, error)
	DeleteAccount(context.Context, string) error
}

type PostgresStore struct {
	pool *pgxpool.Pool
}

func NewPostgresStore(pool *pgxpool.Pool) *PostgresStore {
	return &PostgresStore{pool: pool}
}

func (s *PostgresStore) CreateAccount(ctx context.Context, user User, passwordHash string, device Device, refresh RefreshRecord) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if err := insertUser(ctx, tx, user, passwordHash); err != nil {
		return err
	}
	if err := insertDevice(ctx, tx, user.ID, device); err != nil {
		return err
	}
	if err := insertRefresh(ctx, tx, refresh); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *PostgresStore) CreateLocalAccount(ctx context.Context, user User, passwordHash string) error {
	return insertUser(ctx, s.pool, user, passwordHash)
}

func (s *PostgresStore) FindUserByEmail(ctx context.Context, email string) (User, string, error) {
	var user User
	var passwordHash string
	err := s.pool.QueryRow(ctx, `
		SELECT id, email, display_name, time_zone, locale, week_starts_on, created_at, password_hash
		FROM users
		WHERE lower(email) = lower($1) AND deleted_at IS NULL`, email,
	).Scan(&user.ID, &user.Email, &user.DisplayName, &user.TimeZone, &user.Locale, &user.WeekStartsOn, &user.CreatedAt, &passwordHash)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, "", ErrInvalidCredentials
	}
	if err != nil {
		return User{}, "", fmt.Errorf("find user: %w", err)
	}
	return user, passwordHash, nil
}

func (s *PostgresStore) CreateSession(ctx context.Context, userID string, device Device, refresh RefreshRecord) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	command, err := tx.Exec(ctx, `
		INSERT INTO devices (id, user_id, name, platform, app_version, last_seen_at)
		VALUES ($1, $2, $3, $4, $5, now())
		ON CONFLICT (id) DO UPDATE SET
			name = EXCLUDED.name,
			platform = EXCLUDED.platform,
			app_version = EXCLUDED.app_version,
			last_seen_at = now(),
			revoked_at = NULL
		WHERE devices.user_id = EXCLUDED.user_id`,
		device.ID, userID, device.Name, device.Platform, device.AppVersion,
	)
	if err != nil {
		return fmt.Errorf("upsert device: %w", err)
	}
	if command.RowsAffected() == 0 {
		return ErrDeviceConflict
	}
	if err := insertRefresh(ctx, tx, refresh); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *PostgresStore) RotateRefreshToken(ctx context.Context, oldHash []byte, replacement RefreshRecord) (User, Device, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return User{}, Device{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var user User
	var device Device
	var tokenID, familyID string
	var expiresAt time.Time
	var revokedAt *time.Time
	err = tx.QueryRow(ctx, `
		SELECT rt.id, rt.family_id, rt.expires_at, rt.revoked_at,
		       u.id, u.email, u.display_name, u.time_zone, u.locale, u.week_starts_on, u.created_at,
		       d.id, d.name, d.platform, d.app_version
		FROM refresh_tokens rt
		JOIN users u ON u.id = rt.user_id AND u.deleted_at IS NULL
		JOIN devices d ON d.id = rt.device_id AND d.revoked_at IS NULL
		WHERE rt.token_hash = $1
		FOR UPDATE OF rt`, oldHash,
	).Scan(
		&tokenID, &familyID, &expiresAt, &revokedAt,
		&user.ID, &user.Email, &user.DisplayName, &user.TimeZone, &user.Locale, &user.WeekStartsOn, &user.CreatedAt,
		&device.ID, &device.Name, &device.Platform, &device.AppVersion,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, Device{}, ErrInvalidToken
	}
	if err != nil {
		return User{}, Device{}, fmt.Errorf("find refresh token: %w", err)
	}
	if revokedAt != nil {
		if _, updateErr := tx.Exec(ctx,
			"UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, now()) WHERE family_id = $1", familyID,
		); updateErr != nil {
			return User{}, Device{}, fmt.Errorf("revoke reused token family: %w", updateErr)
		}
		if err := tx.Commit(ctx); err != nil {
			return User{}, Device{}, err
		}
		return User{}, Device{}, ErrTokenReuse
	}
	if !expiresAt.After(time.Now().UTC()) {
		_, _ = tx.Exec(ctx, "UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1", tokenID)
		_ = tx.Commit(ctx)
		return User{}, Device{}, ErrInvalidToken
	}

	replacement.FamilyID = familyID
	replacement.UserID = user.ID
	replacement.DeviceID = device.ID
	if err := insertRefresh(ctx, tx, replacement); err != nil {
		return User{}, Device{}, err
	}
	if _, err := tx.Exec(ctx,
		"UPDATE refresh_tokens SET revoked_at = now(), replaced_by = $2 WHERE id = $1",
		tokenID, replacement.ID,
	); err != nil {
		return User{}, Device{}, fmt.Errorf("rotate refresh token: %w", err)
	}
	if _, err := tx.Exec(ctx, "UPDATE devices SET last_seen_at = now() WHERE id = $1", device.ID); err != nil {
		return User{}, Device{}, fmt.Errorf("touch device: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return User{}, Device{}, err
	}
	return user, device, nil
}

func (s *PostgresStore) RevokeRefreshToken(ctx context.Context, tokenHash []byte) error {
	_, err := s.pool.Exec(ctx,
		"UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, now()) WHERE token_hash = $1", tokenHash,
	)
	if err != nil {
		return fmt.Errorf("revoke refresh token: %w", err)
	}
	return nil
}

func (s *PostgresStore) GetUser(ctx context.Context, userID string) (User, error) {
	var user User
	err := s.pool.QueryRow(ctx, `
		SELECT id, email, display_name, time_zone, locale, week_starts_on, created_at
		FROM users WHERE id = $1 AND deleted_at IS NULL`, userID,
	).Scan(&user.ID, &user.Email, &user.DisplayName, &user.TimeZone, &user.Locale, &user.WeekStartsOn, &user.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrInvalidToken
	}
	if err != nil {
		return User{}, fmt.Errorf("get user: %w", err)
	}
	return user, nil
}

func (s *PostgresStore) UpdateUser(ctx context.Context, userID string, update ProfileUpdate) (User, error) {
	var user User
	err := s.pool.QueryRow(ctx, `
		UPDATE users SET
			display_name = COALESCE($2, display_name),
			time_zone = COALESCE($3, time_zone),
			locale = COALESCE($4, locale),
			week_starts_on = COALESCE($5, week_starts_on),
			updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL
		RETURNING id, email, display_name, time_zone, locale, week_starts_on, created_at`,
		userID, update.DisplayName, update.TimeZone, update.Locale, update.WeekStartsOn,
	).Scan(&user.ID, &user.Email, &user.DisplayName, &user.TimeZone, &user.Locale, &user.WeekStartsOn, &user.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrInvalidToken
	}
	if err != nil {
		return User{}, fmt.Errorf("update user: %w", err)
	}
	return user, nil
}

func (s *PostgresStore) ListDevices(ctx context.Context, userID string) ([]DeviceInfo, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, name, platform, app_version, created_at, last_seen_at, revoked_at
		FROM devices WHERE user_id = $1 ORDER BY last_seen_at DESC, id`, userID)
	if err != nil {
		return nil, fmt.Errorf("list devices: %w", err)
	}
	defer rows.Close()
	devices := make([]DeviceInfo, 0)
	for rows.Next() {
		var device DeviceInfo
		if err := rows.Scan(
			&device.ID, &device.Name, &device.Platform, &device.AppVersion,
			&device.CreatedAt, &device.LastSeenAt, &device.RevokedAt,
		); err != nil {
			return nil, fmt.Errorf("scan device: %w", err)
		}
		devices = append(devices, device)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate devices: %w", err)
	}
	return devices, nil
}

func (s *PostgresStore) RevokeDevice(ctx context.Context, userID, deviceID string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	command, err := tx.Exec(ctx, `
		UPDATE devices SET revoked_at = COALESCE(revoked_at, now())
		WHERE id = $1 AND user_id = $2`, deviceID, userID)
	if err != nil {
		return fmt.Errorf("revoke device: %w", err)
	}
	if command.RowsAffected() == 0 {
		return ErrDeviceNotFound
	}
	if _, err := tx.Exec(ctx, `
		UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, now())
		WHERE user_id = $1 AND device_id = $2`, userID, deviceID); err != nil {
		return fmt.Errorf("revoke device sessions: %w", err)
	}
	return tx.Commit(ctx)
}

func (s *PostgresStore) IsDeviceActive(ctx context.Context, userID, deviceID string) (bool, error) {
	var active bool
	err := s.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM devices d
			JOIN users u ON u.id = d.user_id
			WHERE d.id = $1 AND d.user_id = $2
			  AND d.revoked_at IS NULL AND u.deleted_at IS NULL
		)`, deviceID, userID,
	).Scan(&active)
	if err != nil {
		return false, fmt.Errorf("validate device: %w", err)
	}
	return active, nil
}

func (s *PostgresStore) GetPasswordHash(ctx context.Context, userID string) (string, error) {
	var passwordHash string
	err := s.pool.QueryRow(ctx,
		"SELECT password_hash FROM users WHERE id = $1 AND deleted_at IS NULL", userID,
	).Scan(&passwordHash)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrInvalidCredentials
	}
	if err != nil {
		return "", fmt.Errorf("get password hash: %w", err)
	}
	return passwordHash, nil
}

func (s *PostgresStore) DeleteAccount(ctx context.Context, userID string) error {
	command, err := s.pool.Exec(ctx, "DELETE FROM users WHERE id = $1", userID)
	if err != nil {
		return fmt.Errorf("delete account: %w", err)
	}
	if command.RowsAffected() == 0 {
		return ErrInvalidToken
	}
	return nil
}

type accountExecutor interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
}

func insertUser(ctx context.Context, executor accountExecutor, user User, passwordHash string) error {
	_, err := executor.Exec(ctx, `
		INSERT INTO users (id, email, password_hash, display_name, time_zone, locale, week_starts_on, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)`,
		user.ID, user.Email, passwordHash, user.DisplayName, user.TimeZone, user.Locale, user.WeekStartsOn, user.CreatedAt,
	)
	if err != nil {
		if isUniqueViolation(err) {
			return ErrEmailTaken
		}
		return fmt.Errorf("insert user: %w", err)
	}
	return nil
}

func insertDevice(ctx context.Context, tx pgx.Tx, userID string, device Device) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO devices (id, user_id, name, platform, app_version)
		VALUES ($1, $2, $3, $4, $5)`,
		device.ID, userID, device.Name, device.Platform, device.AppVersion,
	)
	if err != nil {
		if isUniqueViolation(err) {
			return ErrDeviceConflict
		}
		return fmt.Errorf("insert device: %w", err)
	}
	return nil
}

func insertRefresh(ctx context.Context, tx pgx.Tx, refresh RefreshRecord) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO refresh_tokens (id, family_id, user_id, device_id, token_hash, expires_at, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		refresh.ID, refresh.FamilyID, refresh.UserID, refresh.DeviceID,
		refresh.TokenHash, refresh.ExpiresAt, refresh.CreatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert refresh token: %w", err)
	}
	return nil
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
