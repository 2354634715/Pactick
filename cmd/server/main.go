package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
	_ "time/tzdata"

	"pactick/server/internal/account"
	"pactick/server/internal/auth"
	"pactick/server/internal/config"
	"pactick/server/internal/database"
	"pactick/server/internal/httpapi"
	"pactick/server/internal/realtime"
	syncservice "pactick/server/internal/sync"
	"pactick/server/internal/views"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg, err := config.Load()
	if err != nil {
		logger.Error("configuration is invalid", "error", err)
		os.Exit(1)
	}

	startupContext, cancelStartup := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancelStartup()
	pool, err := database.Open(startupContext, cfg.DatabaseURL, cfg.DBMaxConns)
	if err != nil {
		logger.Error("database startup failed", "error", err)
		os.Exit(1)
	}
	defer pool.Close()
	if cfg.AutoMigrate {
		if err := database.Migrate(startupContext, pool); err != nil {
			logger.Error("database migration failed", "error", err)
			os.Exit(1)
		}
	}
	if err := database.VerifyMigrations(startupContext, pool); err != nil {
		logger.Error("database schema verification failed", "error", err)
		os.Exit(1)
	}

	hub := realtime.NewHub()
	accountService := account.NewService(pool)
	authStore := auth.NewPostgresStore(pool)
	issuer := auth.NewAccessTokenIssuer(cfg.JWTSecret, cfg.AccessTokenTTL)
	authService := auth.NewService(authStore, issuer, cfg.RefreshTokenTTL)
	syncStore := syncservice.NewPostgresStore(pool)
	syncService := syncservice.NewService(syncStore, hub)
	viewStore := views.NewStore(pool)
	api := httpapi.New(
		logger,
		pool,
		accountService,
		authService,
		syncService,
		viewStore,
		hub,
		cfg.ClientUpdates,
		cfg.AllowedOrigins,
		cfg.RegistrationEnabled,
	)

	httpServer := &http.Server{
		Addr:              cfg.HTTPAddress,
		Handler:           api.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       90 * time.Second,
	}
	serverErrors := make(chan error, 1)
	go func() {
		logger.Info(
			"server listening",
			"address", cfg.HTTPAddress,
			"environment", cfg.Environment,
			"auto_migrate", cfg.AutoMigrate,
			"registration_enabled", cfg.RegistrationEnabled,
			"client_update_releases", cfg.ClientUpdates.Len(),
		)
		serverErrors <- httpServer.ListenAndServe()
	}()

	signalContext, stopSignals := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stopSignals()
	select {
	case <-signalContext.Done():
		logger.Info("shutdown requested")
	case err := <-serverErrors:
		if !errors.Is(err, http.ErrServerClosed) {
			logger.Error("http server stopped", "error", err)
			os.Exit(1)
		}
		return
	}

	shutdownContext, cancelShutdown := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancelShutdown()
	if err := httpServer.Shutdown(shutdownContext); err != nil {
		logger.Error("graceful shutdown failed", "error", err)
		_ = httpServer.Close()
	}
}
