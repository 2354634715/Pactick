package database

import (
	"context"
	"crypto/sha256"
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"sort"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed migrations/*.up.sql
var migrationFiles embed.FS

const migrationLockID int64 = 824_517_039

type migration struct {
	version  int64
	name     string
	sql      string
	checksum string
}

func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	conn, err := pool.Acquire(ctx)
	if err != nil {
		return fmt.Errorf("acquire migration connection: %w", err)
	}
	defer conn.Release()

	if _, err := conn.Exec(ctx, "SELECT pg_advisory_lock($1)", migrationLockID); err != nil {
		return fmt.Errorf("lock migrations: %w", err)
	}
	defer func() {
		_, _ = conn.Exec(context.Background(), "SELECT pg_advisory_unlock($1)", migrationLockID)
	}()

	if _, err := conn.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version bigint PRIMARY KEY,
			name text NOT NULL,
			checksum text NOT NULL,
			applied_at timestamptz NOT NULL DEFAULT now()
		)`); err != nil {
		return fmt.Errorf("create migration ledger: %w", err)
	}
	if _, err := conn.Exec(ctx, "ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS checksum text"); err != nil {
		return fmt.Errorf("upgrade migration ledger: %w", err)
	}

	migrations, err := loadMigrations()
	if err != nil {
		return err
	}
	for _, item := range migrations {
		var appliedName string
		var appliedChecksum *string
		err := conn.QueryRow(ctx,
			"SELECT name, checksum FROM schema_migrations WHERE version = $1",
			item.version,
		).Scan(&appliedName, &appliedChecksum)
		if err == nil {
			if appliedName != item.name {
				return fmt.Errorf("migration version %d is recorded as %q, not %q", item.version, appliedName, item.name)
			}
			if appliedChecksum == nil {
				if _, err := conn.Exec(ctx,
					"UPDATE schema_migrations SET checksum = $2 WHERE version = $1",
					item.version, item.checksum,
				); err != nil {
					return fmt.Errorf("baseline migration checksum %s: %w", item.name, err)
				}
			} else if *appliedChecksum != item.checksum {
				return fmt.Errorf("migration %s differs from the applied checksum", item.name)
			}
			continue
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return fmt.Errorf("read migration ledger: %w", err)
		}

		tx, err := conn.Begin(ctx)
		if err != nil {
			return fmt.Errorf("begin migration %s: %w", item.name, err)
		}
		// Migrations can write sync_changes (including previously published SQL).
		// Exclude application writers before any migration allocates a cursor.
		if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock($1)", syncWriteBarrierID); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("lock sync writes for migration %s: %w", item.name, err)
		}
		if _, err := tx.Exec(ctx, item.sql); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("apply migration %s: %w", item.name, err)
		}
		if _, err := tx.Exec(ctx,
			"INSERT INTO schema_migrations (version, name, checksum) VALUES ($1, $2, $3)",
			item.version, item.name, item.checksum,
		); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("record migration %s: %w", item.name, err)
		}
		if err := tx.Commit(ctx); err != nil {
			return fmt.Errorf("commit migration %s: %w", item.name, err)
		}
	}
	return nil
}

func VerifyMigrations(ctx context.Context, pool *pgxpool.Pool) error {
	migrations, err := loadMigrations()
	if err != nil {
		return err
	}
	for _, item := range migrations {
		var name string
		var checksum *string
		err := pool.QueryRow(ctx,
			"SELECT name, checksum FROM schema_migrations WHERE version = $1",
			item.version,
		).Scan(&name, &checksum)
		if errors.Is(err, pgx.ErrNoRows) {
			return fmt.Errorf("migration %s has not been applied", item.name)
		}
		if err != nil {
			return fmt.Errorf("verify migration %s: %w", item.name, err)
		}
		if name != item.name || checksum == nil || *checksum != item.checksum {
			return fmt.Errorf("migration %s does not match the migration ledger", item.name)
		}
	}
	return nil
}

func loadMigrations() ([]migration, error) {
	entries, err := fs.ReadDir(migrationFiles, "migrations")
	if err != nil {
		return nil, fmt.Errorf("read embedded migrations: %w", err)
	}
	items := make([]migration, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".up.sql") {
			continue
		}
		prefix, _, ok := strings.Cut(entry.Name(), "_")
		if !ok {
			return nil, fmt.Errorf("migration %q has no numeric prefix", entry.Name())
		}
		version, err := strconv.ParseInt(prefix, 10, 64)
		if err != nil {
			return nil, fmt.Errorf("parse migration %q: %w", entry.Name(), err)
		}
		contents, err := migrationFiles.ReadFile("migrations/" + entry.Name())
		if err != nil {
			return nil, fmt.Errorf("read migration %q: %w", entry.Name(), err)
		}
		checksum := sha256.Sum256(contents)
		items = append(items, migration{
			version:  version,
			name:     entry.Name(),
			sql:      string(contents),
			checksum: fmt.Sprintf("%x", checksum[:]),
		})
	}
	sort.Slice(items, func(i, j int) bool { return items[i].version < items[j].version })
	return items, nil
}
