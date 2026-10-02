package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"pactick/server/internal/clientupdate"
)

type Config struct {
	Environment         string
	HTTPAddress         string
	DatabaseURL         string
	JWTSecret           string
	AccessTokenTTL      time.Duration
	RefreshTokenTTL     time.Duration
	ShutdownTimeout     time.Duration
	AllowedOrigins      []string
	AutoMigrate         bool
	RegistrationEnabled bool
	DBMaxConns          int32
	ClientUpdates       *clientupdate.Catalog
}

func Load() (Config, error) {
	environment := strings.ToLower(envOr("APP_ENV", "development"))
	localDefaults := environment == "development" || environment == "test"
	cfg := Config{
		Environment:         environment,
		HTTPAddress:         envOr("HTTP_ADDRESS", ":8080"),
		DatabaseURL:         strings.TrimSpace(os.Getenv("DATABASE_URL")),
		JWTSecret:           os.Getenv("AUTH_JWT_SECRET"),
		AccessTokenTTL:      15 * time.Minute,
		RefreshTokenTTL:     30 * 24 * time.Hour,
		ShutdownTimeout:     10 * time.Second,
		AllowedOrigins:      splitCSV(os.Getenv("ALLOWED_ORIGINS")),
		AutoMigrate:         localDefaults,
		RegistrationEnabled: localDefaults,
		DBMaxConns:          10,
	}
	clientUpdates, err := clientupdate.ParseManifest(os.Getenv("CLIENT_UPDATE_MANIFEST_JSON"))
	if err != nil {
		return Config{}, fmt.Errorf("parse CLIENT_UPDATE_MANIFEST_JSON: %w", err)
	}
	cfg.ClientUpdates = clientUpdates

	if cfg.AccessTokenTTL, err = durationEnv("ACCESS_TOKEN_TTL", cfg.AccessTokenTTL); err != nil {
		return Config{}, err
	}
	if cfg.RefreshTokenTTL, err = durationEnv("REFRESH_TOKEN_TTL", cfg.RefreshTokenTTL); err != nil {
		return Config{}, err
	}
	if cfg.ShutdownTimeout, err = durationEnv("SHUTDOWN_TIMEOUT", cfg.ShutdownTimeout); err != nil {
		return Config{}, err
	}
	if cfg.AutoMigrate, err = boolEnv("AUTO_MIGRATE", cfg.AutoMigrate); err != nil {
		return Config{}, err
	}
	if cfg.RegistrationEnabled, err = boolEnv("REGISTRATION_ENABLED", cfg.RegistrationEnabled); err != nil {
		return Config{}, err
	}
	if cfg.DBMaxConns, err = int32Env("DB_MAX_CONNS", cfg.DBMaxConns); err != nil {
		return Config{}, err
	}

	if cfg.DatabaseURL == "" {
		return Config{}, errors.New("DATABASE_URL is required")
	}
	if len(cfg.JWTSecret) < 32 {
		return Config{}, errors.New("AUTH_JWT_SECRET must contain at least 32 characters")
	}
	if cfg.AccessTokenTTL <= 0 || cfg.RefreshTokenTTL <= 0 || cfg.ShutdownTimeout <= 0 {
		return Config{}, errors.New("token and shutdown durations must be positive")
	}
	if cfg.DBMaxConns < 1 {
		return Config{}, errors.New("DB_MAX_CONNS must be positive")
	}
	return cfg, nil
}

func envOr(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

func durationEnv(name string, fallback time.Duration) (time.Duration, error) {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback, nil
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return 0, fmt.Errorf("parse %s: %w", name, err)
	}
	return parsed, nil
}

func boolEnv(name string, fallback bool) (bool, error) {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback, nil
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return false, fmt.Errorf("parse %s: %w", name, err)
	}
	return parsed, nil
}

func int32Env(name string, fallback int32) (int32, error) {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback, nil
	}
	parsed, err := strconv.ParseInt(value, 10, 32)
	if err != nil {
		return 0, fmt.Errorf("parse %s: %w", name, err)
	}
	return int32(parsed), nil
}

func splitCSV(value string) []string {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	result := make([]string, 0, len(parts))
	for _, part := range parts {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			result = append(result, trimmed)
		}
	}
	return result
}
