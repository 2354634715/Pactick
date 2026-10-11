package admin

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"pactick/server/internal/auth"
)

type recordingStore struct {
	user auth.User
	hash string
	err  error
}

func (s *recordingStore) CreateLocalAccount(_ context.Context, user auth.User, hash string) error {
	s.user, s.hash = user, hash
	return s.err
}

func TestDecodeCreateAccountRequestRejectsMalformedInputWithoutEcho(t *testing.T) {
	const secret = "sensitive-password-marker"
	for _, value := range []string{
		"", "null", "[]", `{"email":"a@example.invalid","password":"` + secret + `","unknown":true}`,
		`{"email":"a@example.invalid","password":"` + secret + `","week_starts_on":"wrong"}`,
		`{"email":"a@example.invalid"} {"password":"` + secret + `"}`,
		`{"password":"` + secret + `"`, `{"email":"a@example.invalid"}` + strings.Repeat(" ", maxRequestBytes),
		string([]byte{'{', 0xff, '}'}),
	} {
		_, err := DecodeCreateAccountRequest(strings.NewReader(value))
		var adminError *Error
		if !errors.As(err, &adminError) || adminError.Code != "invalid_json" || strings.Contains(err.Error(), secret) {
			t.Fatalf("invalid JSON did not produce a safe error: %v", err)
		}
	}
}

func TestGeneratedPasswordAndProfileDefaults(t *testing.T) {
	input, password, err := prepareAccount(CreateAccountRequest{Email: "alice@example.invalid"})
	if err != nil {
		t.Fatal(err)
	}
	if len(password) != 32 || input.Password != password || input.DisplayName != "alice" || input.TimeZone != "UTC" || input.Locale != "zh-CN" || input.WeekStartsOn != 1 {
		t.Fatal("unexpected password or default profile")
	}
	_, anotherPassword, err := prepareAccount(CreateAccountRequest{Email: "alice@example.invalid"})
	if err != nil || password == anotherPassword {
		t.Fatal("generated passwords are not independently random")
	}
	store := &recordingStore{}
	result, err := provisionAccount(context.Background(), store, input, password)
	if err != nil || result.GeneratedPassword != password || result.User != store.user {
		t.Fatalf("generated account creation failed: %v", err)
	}
	valid, err := auth.DefaultPasswordHasher().Verify(result.GeneratedPassword, store.hash)
	if err != nil || !valid {
		t.Fatal("generated password cannot verify the stored hash")
	}
}

func TestSuppliedPasswordIsNeverReturned(t *testing.T) {
	const password = "supplied-sensitive-password"
	input, generated, err := prepareAccount(CreateAccountRequest{Email: "alice@example.invalid", Password: password})
	if err != nil || generated != "" {
		t.Fatalf("prepare supplied password: %v", err)
	}
	result, err := provisionAccount(context.Background(), &recordingStore{}, input, generated)
	if err != nil {
		t.Fatal(err)
	}
	encoded, err := json.Marshal(result)
	if err != nil || strings.Contains(string(encoded), password) || strings.Contains(string(encoded), "generated_password") {
		t.Fatal("supplied password was returned")
	}
}

func TestCreateAccountValidatesBeforeOpeningDatabase(t *testing.T) {
	_, err := CreateAccount(context.Background(), "database-password-marker", CreateAccountRequest{Email: "invalid", Password: "short"})
	var adminError *Error
	if !errors.As(err, &adminError) || adminError.Code != "invalid_input" || strings.Contains(err.Error(), "database-password-marker") {
		t.Fatalf("input validation did not precede database access: %v", err)
	}
	_, err = CreateAccount(context.Background(), "", CreateAccountRequest{Email: "alice@example.invalid"})
	if !errors.As(err, &adminError) || adminError.Code != "configuration_required" {
		t.Fatalf("missing database URL = %v", err)
	}
}

func TestProvisionFailureDoesNotReturnGeneratedPassword(t *testing.T) {
	input, password, err := prepareAccount(CreateAccountRequest{Email: "alice@example.invalid"})
	if err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		err  error
		code string
	}{
		{auth.ErrEmailTaken, "email_taken"},
		{context.Canceled, "operation_cancelled"},
		{context.DeadlineExceeded, "operation_timeout"},
		{errors.New("database-password-marker"), "account_creation_failed"},
	} {
		result, err := provisionAccount(context.Background(), &recordingStore{err: test.err}, input, password)
		var adminError *Error
		if !errors.As(err, &adminError) || adminError.Code != test.code || result != (CreateAccountResult{}) || strings.Contains(err.Error(), "database-password-marker") {
			t.Fatalf("provision failure returned unsafe result: code=%s error=%v", test.code, err)
		}
	}
}
