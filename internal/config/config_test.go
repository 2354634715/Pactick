package config

import (
	"strings"
	"testing"
)

func TestLoadRejectsShortJWTSecret(t *testing.T) {
	t.Setenv("APP_ENV", "development")
	t.Setenv("DATABASE_URL", "postgres://localhost/test")
	t.Setenv("AUTH_JWT_SECRET", "short")
	if _, err := Load(); err == nil {
		t.Fatal("Load() accepted a short JWT secret")
	}
}

func TestLoadParsesSettings(t *testing.T) {
	t.Setenv("APP_ENV", "development")
	t.Setenv("DATABASE_URL", "postgres://localhost/test")
	t.Setenv("AUTH_JWT_SECRET", "12345678901234567890123456789012")
	t.Setenv("AUTO_MIGRATE", "false")
	t.Setenv("REGISTRATION_ENABLED", "false")
	t.Setenv("DB_MAX_CONNS", "7")
	t.Setenv("ALLOWED_ORIGINS", "https://one.example, https://two.example")
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.AutoMigrate || cfg.RegistrationEnabled || cfg.DBMaxConns != 7 || len(cfg.AllowedOrigins) != 2 {
		t.Fatalf("Load() = %#v", cfg)
	}
}

func TestProductionDefaultsDisableMigrationsAndRegistration(t *testing.T) {
	t.Setenv("APP_ENV", "production")
	t.Setenv("DATABASE_URL", "postgres://localhost/test")
	t.Setenv("AUTH_JWT_SECRET", "12345678901234567890123456789012")
	t.Setenv("AUTO_MIGRATE", "")
	t.Setenv("REGISTRATION_ENABLED", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.AutoMigrate || cfg.RegistrationEnabled {
		t.Fatalf("production defaults are unsafe: %#v", cfg)
	}
}

func TestProductionAllowsExplicitRegistrationWindow(t *testing.T) {
	t.Setenv("APP_ENV", "production")
	t.Setenv("DATABASE_URL", "postgres://localhost/test")
	t.Setenv("AUTH_JWT_SECRET", "12345678901234567890123456789012")
	t.Setenv("REGISTRATION_ENABLED", "true")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if !cfg.RegistrationEnabled {
		t.Fatal("explicit registration window was ignored")
	}
}

func TestLoadParsesClientUpdateManifest(t *testing.T) {
	t.Setenv("APP_ENV", "production")
	t.Setenv("DATABASE_URL", "postgres://localhost/test")
	t.Setenv("AUTH_JWT_SECRET", "12345678901234567890123456789012")
	t.Setenv("CLIENT_UPDATE_MANIFEST_JSON", `{"releases":[{"platform":"android","channel":"stable","version":"0.2.0","build_number":3,"required":false,"download_url":"https://downloads.example.com/pactick.apk","sha256":"`+strings.Repeat("a", 64)+`","size_bytes":123,"release_notes":"Changes","published_at":"2026-09-19T00:00:00Z"}]}`)

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	release, ok := cfg.ClientUpdates.Lookup("android", "stable")
	if !ok || release.Version != "0.2.0" || release.BuildNumber != 3 {
		t.Fatalf("client update release = %#v, found = %t", release, ok)
	}
}

func TestLoadRejectsInvalidClientUpdateManifest(t *testing.T) {
	t.Setenv("APP_ENV", "production")
	t.Setenv("DATABASE_URL", "postgres://localhost/test")
	t.Setenv("AUTH_JWT_SECRET", "12345678901234567890123456789012")
	t.Setenv("CLIENT_UPDATE_MANIFEST_JSON", `{"releases":[{"platform":"android","channel":"stable","version":"0.2.0","build_number":3,"required":false,"download_url":"file:///tmp/app.apk","sha256":"`+strings.Repeat("a", 64)+`","size_bytes":123,"release_notes":"Changes","published_at":"2026-09-19T00:00:00Z"}]}`)

	if _, err := Load(); err == nil || !strings.Contains(err.Error(), "CLIENT_UPDATE_MANIFEST_JSON") {
		t.Fatalf("Load() error = %v, want manifest validation error", err)
	}
}
