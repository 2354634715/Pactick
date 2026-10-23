package manager

import (
	"crypto/sha256"
	"fmt"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRestoreRejectsTraversalAndCorruptionBeforeStartingPrograms(t *testing.T) {
	m, err := New(t.TempDir(), t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer m.Close()
	name := "pactick-20261017-120000-1234abcd.dump"
	dir := filepath.Join(m.data, "backups")
	os.MkdirAll(dir, 0700)
	data := []byte("trusted-test-archive")
	if err := os.WriteFile(filepath.Join(dir, name), data, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, name+".sha256"), []byte(fmt.Sprintf("%x  %s\n", sha256.Sum256(data), name)), 0600); err != nil {
		t.Fatal(err)
	}
	f, err := m.verifiedBackup(name)
	if err != nil {
		t.Fatal(err)
	}
	f.Close()
	if _, err := m.verifiedBackup("../" + name); err == nil {
		t.Fatal("accepted traversal")
	}
	if err := os.WriteFile(filepath.Join(dir, name), []byte("changed"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := m.RestoreCheck(t.Context(), name); err == nil || !strings.Contains(err.Error(), "SHA-256") {
		t.Fatalf("corrupted backup accepted: %v", err)
	}
}

func TestManagementMutationNeedsIndependentCSRFAndOrigin(t *testing.T) {
	m, err := New(t.TempDir(), t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer m.Close()
	h := m.Handler("127.0.0.1:43995", "session")
	for _, tc := range []struct{ origin, csrf string }{{"", ""}, {"http://127.0.0.1:43995", ""}, {"http://127.0.0.1:43995", "session"}} {
		r := httptest.NewRequest("POST", "http://127.0.0.1:43995/api/action", strings.NewReader(`{"action":"logs"}`))
		r.Header.Set("X-Pactick-Manager-Token", "session")
		r.Header.Set("Origin", tc.origin)
		r.Header.Set("X-Pactick-CSRF-Token", tc.csrf)
		r.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != 403 {
			t.Fatalf("csrf accepted: %d %s", w.Code, w.Body)
		}
	}
}

func TestPostgresChildArgumentsNeverNeedPassword(t *testing.T) {
	env, err := postgresEnvironment("postgres://alice:private%21@127.0.0.1/prod?sslmode=require", "pactick_restore_test")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(env[0], "private") || !strings.Contains(env[0], "/pactick_restore_test") || env[1] != "PGPASSWORD=private!" {
		t.Fatalf("unsafe child connection environment: %v", env)
	}
}
