package admin

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"pactick/server/internal/auth"
	"pactick/server/internal/database"
	"pactick/server/internal/httpapi"
	"pactick/server/internal/testpostgres"
)

func TestCreateAccountRequiresMigrationsAndReturnsSafeDuplicateError(t *testing.T) {
	f := testpostgres.New(t)
	databaseURL := isolatedDatabaseURL(t, f)
	request := CreateAccountRequest{Email: "operator@example.invalid"}
	_, err := CreateAccount(f.Ctx, databaseURL, request)
	var adminError *Error
	if !errors.As(err, &adminError) || adminError.Code != "schema_not_ready" {
		t.Fatalf("unmigrated account creation = %v", err)
	}
	if err := database.Migrate(f.Ctx, f.Pool); err != nil {
		t.Fatal(err)
	}
	result, err := CreateAccount(f.Ctx, databaseURL, request)
	if err != nil || result.User.Email != request.Email || len(result.GeneratedPassword) != 32 {
		t.Fatalf("migrated account creation failed: error=%v", err)
	}
	result, err = CreateAccount(f.Ctx, databaseURL, request)
	if !errors.As(err, &adminError) || adminError.Code != "email_taken" || result != (CreateAccountResult{}) {
		t.Fatalf("duplicate account creation = %v", err)
	}
}

func TestLocalCreationWorksWhenPublicRegistrationIsDisabled(t *testing.T) {
	f := testpostgres.New(t)
	if err := database.Migrate(f.Ctx, f.Pool); err != nil {
		t.Fatal(err)
	}
	authService := auth.NewService(auth.NewPostgresStore(f.Pool),
		auth.NewAccessTokenIssuer("local-only-test-secret-at-least-32-characters", time.Minute), time.Hour)
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	handler := httpapi.New(logger, f.Pool, nil, authService, nil, nil, nil, nil, nil, false).Handler()
	registration := httptest.NewRecorder()
	handler.ServeHTTP(registration, httptest.NewRequest(http.MethodPost, "/v1/auth/register", nil))
	if registration.Code != http.StatusForbidden {
		t.Fatalf("closed public registration status = %d", registration.Code)
	}
	account, err := CreateAccount(f.Ctx, isolatedDatabaseURL(t, f), CreateAccountRequest{Email: "local-only@example.invalid"})
	if err != nil {
		t.Fatal(err)
	}
	body, err := json.Marshal(map[string]any{
		"email": account.User.Email, "password": account.GeneratedPassword,
		"device": auth.Device{ID: uuid.NewString(), Name: "Android", Platform: "android"},
	})
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/v1/auth/login", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	login := httptest.NewRecorder()
	handler.ServeHTTP(login, request)
	if login.Code != http.StatusOK {
		t.Fatalf("locally created account login status = %d", login.Code)
	}
	var session auth.Session
	if err := json.Unmarshal(login.Body.Bytes(), &session); err != nil {
		t.Fatal(err)
	}
	if session.User.ID != account.User.ID || session.Tokens.AccessToken == "" || session.Tokens.RefreshToken == "" {
		t.Fatal("closed-registration login did not return the provisioned account and tokens")
	}
}

func isolatedDatabaseURL(t *testing.T, f *testpostgres.Fixture) string {
	t.Helper()
	dsn := f.Config.ConnString()
	schema := f.Config.ConnConfig.RuntimeParams["search_path"]
	if strings.HasPrefix(dsn, "postgres://") || strings.HasPrefix(dsn, "postgresql://") {
		parsed, err := url.Parse(dsn)
		if err != nil {
			t.Fatal("invalid test database URL")
		}
		params := parsed.Query()
		params.Set("search_path", schema)
		parsed.RawQuery = params.Encode()
		return parsed.String()
	}
	return dsn + " search_path=" + schema
}
