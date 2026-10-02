package database

import (
	"strings"
	"testing"
)

func TestEmbeddedMigrationsLoad(t *testing.T) {
	migrations, err := loadMigrations()
	if err != nil {
		t.Fatalf("loadMigrations() error = %v", err)
	}
	if len(migrations) == 0 {
		t.Fatal("loadMigrations() returned no migrations")
	}
	if migrations[0].version != 1 || migrations[0].checksum == "" || !strings.Contains(migrations[0].sql, "CREATE TABLE sync_changes") {
		t.Fatalf("unexpected initial migration: %#v", migrations[0])
	}
	if len(migrations) < 2 || migrations[1].version != 2 ||
		!strings.Contains(migrations[1].sql, "body - 'allowed_app_ids'") ||
		!strings.Contains(migrations[1].sql, "INSERT INTO sync_changes") {
		t.Fatalf("privacy migration is missing or incomplete: %#v", migrations)
	}
}
