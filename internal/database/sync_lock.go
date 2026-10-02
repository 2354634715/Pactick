package database

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
)

const syncWriteBarrierID int64 = 824_517_040

// LockSyncWrites must precede entity reads and cursor allocation in every
// transaction that writes sync_changes. Account writers hold this lock until
// commit, so a higher account cursor cannot commit ahead of a lower one.
func LockSyncWrites(ctx context.Context, tx pgx.Tx, userID string) error {
	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock_shared($1)", syncWriteBarrierID); err != nil {
		return fmt.Errorf("lock sync migration barrier: %w", err)
	}
	if _, err := tx.Exec(ctx,
		"SELECT pg_advisory_xact_lock(hashtextextended($1, 2))", "sync:user:"+userID,
	); err != nil {
		return fmt.Errorf("lock account sync writes: %w", err)
	}
	return nil
}
