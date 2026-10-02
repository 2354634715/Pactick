package main

import (
	"context"
	"log/slog"
	"os"
	"time"

	"pactick/server/internal/config"
	"pactick/server/internal/database"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg, err := config.Load()
	if err != nil {
		logger.Error("configuration is invalid", "error", err)
		os.Exit(1)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	pool, err := database.Open(ctx, cfg.DatabaseURL, cfg.DBMaxConns)
	if err != nil {
		logger.Error("database startup failed", "error", err)
		os.Exit(1)
	}
	defer pool.Close()
	if err := database.Migrate(ctx, pool); err != nil {
		logger.Error("database migration failed", "error", err)
		os.Exit(1)
	}
	logger.Info("database migrations are current")
}
