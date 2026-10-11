package manager

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestManagementSessionAndSecretIsolation(t *testing.T) {
	m, err := New(t.TempDir(), t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer m.Close()
	m.cfg.DatabaseURL = "postgres://user:test-sensitive-value@127.0.0.1/db"
	h := m.Handler("127.0.0.1:43991", "session-token")
	for _, tc := range []struct {
		name, host, origin, token string
		status                    int
	}{
		{"valid", "127.0.0.1:43991", "http://127.0.0.1:43991", "session-token", 200},
		{"no session", "127.0.0.1:43991", "", "", 401},
		{"forged session", "127.0.0.1:43991", "", "wrong", 401},
		{"dns rebinding", "attacker.example:43991", "", "session-token", 403},
		{"cross origin", "127.0.0.1:43991", "https://attacker.example", "session-token", 403},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest("GET", "http://"+tc.host+"/api/status", nil)
			r.Header.Set("Origin", tc.origin)
			r.Header.Set("X-Pactick-Manager-Token", tc.token)
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)
			if w.Code != tc.status {
				t.Fatalf("status %d: %s", w.Code, w.Body)
			}
			for _, secret := range []string{"test-sensitive-value", m.cfg.JWTSecret, m.cfg.PostgresPassword} {
				if strings.Contains(w.Body.String(), secret) {
					t.Fatal("response exposed a secret")
				}
			}
		})
	}
}

func TestConfigurationLockAndPersistentSecrets(t *testing.T) {
	dir := t.TempDir()
	m, err := New(t.TempDir(), dir)
	if err != nil {
		t.Fatal(err)
	}
	if second, err := New(t.TempDir(), dir); err == nil {
		second.Close()
		t.Fatal("two managers acquired same data directory")
	}
	before := m.cfg
	m.Close()
	m, err = New(t.TempDir(), dir)
	if err != nil {
		t.Fatal(err)
	}
	defer m.Close()
	if before.JWTSecret != m.cfg.JWTSecret || before.PostgresPassword != m.cfg.PostgresPassword || before.ProjectName != m.cfg.ProjectName {
		t.Fatal("restart changed deployment identity or credentials")
	}
}

func TestSettingsAndMigrationGuards(t *testing.T) {
	m, err := New(t.TempDir(), t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer m.Close()
	m.cfg.Mode = "native"
	m.cfg.DatabaseURL = "postgres://user:private@127.0.0.1:1/db"
	m.cfg.Initialized = true
	h := m.Handler("127.0.0.1:43992", "token")
	body := `{"mode":"docker","http_address":"127.0.0.1:43993","database_url":""}`
	r := httptest.NewRequest("POST", "http://127.0.0.1:43992/api/settings", strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("X-Pactick-Manager-Token", "token")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusConflict {
		t.Fatalf("mode switch: %d %s", w.Code, w.Body)
	}
	if err := os.WriteFile(filepath.Join(m.data, ".migration-pending"), []byte("started"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := m.Action(r.Context(), "start"); err == nil {
		t.Fatal("started after incomplete migration")
	}
	if _, err := m.Action(r.Context(), "deploy"); err == nil {
		t.Fatal("deploy bypassed incomplete migration guard")
	}
	if _, err := os.Stat(filepath.Join(m.data, "api.env")); err != nil {
		t.Fatal("native launcher configuration missing", err)
	}
}

func TestStrictRequests(t *testing.T) {
	m, err := New(t.TempDir(), t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer m.Close()
	h := m.Handler("127.0.0.1:43994", "token")
	for _, body := range []string{`{"action":"logs","unexpected":true}`, `{"action":"logs"} {}`, strings.Repeat("a", 20000)} {
		r := httptest.NewRequest("POST", "http://127.0.0.1:43994/api/action", strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		r.Header.Set("X-Pactick-Manager-Token", "token")
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != 400 {
			t.Fatalf("request accepted: %d", w.Code)
		}
		var out result
		if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
			t.Fatal(err)
		}
	}
}
