// Package testpostgres provides isolated schemas for PostgreSQL integration tests.
package testpostgres

import (
	"context"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Fixture struct {
	Pool   *pgxpool.Pool
	Config *pgxpool.Config
	Ctx    context.Context
}

func New(t *testing.T) *Fixture {
	t.Helper()
	dsn := os.Getenv("PACTICK_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set PACTICK_TEST_DATABASE_URL to run PostgreSQL integration tests")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	t.Cleanup(cancel)
	config, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal("parse PACTICK_TEST_DATABASE_URL: invalid connection configuration")
	}
	admin, err := pgxpool.NewWithConfig(ctx, config.Copy())
	if err != nil {
		t.Fatalf("open PostgreSQL integration database: %v", err)
	}
	if err := admin.Ping(ctx); err != nil {
		admin.Close()
		t.Fatalf("connect PostgreSQL integration database: %v", err)
	}
	schema := "pactick_test_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	quotedSchema := pgx.Identifier{schema}.Sanitize()
	if _, err := admin.Exec(ctx, "CREATE SCHEMA "+quotedSchema); err != nil {
		admin.Close()
		t.Fatalf("create integration test schema: %v", err)
	}
	config.ConnConfig.RuntimeParams["search_path"] = schema
	config.ConnConfig.RuntimeParams["application_name"] = schema
	config.MaxConns = 8
	var pool *pgxpool.Pool
	t.Cleanup(func() {
		if pool != nil {
			pool.Close()
		}
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cleanupCancel()
		if _, err := admin.Exec(cleanupCtx, "DROP SCHEMA "+quotedSchema+" CASCADE"); err != nil {
			t.Errorf("drop integration test schema: %v", err)
		}
		admin.Close()
	})
	pool, err = pgxpool.NewWithConfig(ctx, config.Copy())
	if err != nil {
		t.Fatalf("open schema pool: %v", err)
	}
	return &Fixture{Pool: pool, Config: config, Ctx: ctx}
}

func (f *Fixture) TracedPool(t *testing.T, tracer pgx.QueryTracer, name string) *pgxpool.Pool {
	t.Helper()
	config := f.Config.Copy()
	config.ConnConfig.Tracer = tracer
	config.ConnConfig.RuntimeParams["application_name"] += "_" + name
	pool, err := pgxpool.NewWithConfig(f.Ctx, config)
	if err != nil {
		t.Fatalf("create traced pool: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func (f *Fixture) Account(t *testing.T) (userID, deviceID string) {
	t.Helper()
	userID, deviceID = uuid.NewString(), uuid.NewString()
	if _, err := f.Pool.Exec(f.Ctx, `
		INSERT INTO users (id, email, password_hash, display_name, time_zone)
		VALUES ($1, $2, 'test-only', 'Before', 'UTC')`, userID, userID+"@example.invalid",
	); err != nil {
		t.Fatal(err)
	}
	if _, err := f.Pool.Exec(f.Ctx, `
		INSERT INTO devices (id, user_id, name, platform) VALUES ($1, $2, 'Before', 'android')`, deviceID, userID,
	); err != nil {
		t.Fatal(err)
	}
	return userID, deviceID
}

// QueryGate pauses once after PostgreSQL executes a matching query. Other pools
// can commit writes while the paused transaction remains open.
type QueryGate struct {
	Match   string
	Entered chan struct{}
	Release chan struct{}
	once    sync.Once
}

type gateSQLKey struct{}

func NewQueryGate(match string) *QueryGate {
	return &QueryGate{Match: match, Entered: make(chan struct{}), Release: make(chan struct{})}
}

func (g *QueryGate) TraceQueryStart(ctx context.Context, _ *pgx.Conn, data pgx.TraceQueryStartData) context.Context {
	return context.WithValue(ctx, gateSQLKey{}, data.SQL)
}

func (g *QueryGate) TraceQueryEnd(ctx context.Context, _ *pgx.Conn, data pgx.TraceQueryEndData) {
	sql, _ := ctx.Value(gateSQLKey{}).(string)
	if data.Err != nil || !strings.Contains(sql, g.Match) {
		return
	}
	g.once.Do(func() {
		close(g.Entered)
		select {
		case <-g.Release:
		case <-ctx.Done():
		}
	})
}

func (g *QueryGate) Wait(t *testing.T, ctx context.Context) {
	t.Helper()
	select {
	case <-g.Entered:
	case <-ctx.Done():
		t.Fatalf("query gate %q was not reached: %v", g.Match, ctx.Err())
	}
}
