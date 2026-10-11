package auth

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

type provisionStore struct {
	user User
	hash string
	err  error
	call bool
}

func (s *provisionStore) CreateLocalAccount(_ context.Context, user User, hash string) error {
	s.call = true
	s.user, s.hash = user, hash
	return s.err
}

func validAccountInput() AccountInput {
	return AccountInput{
		Email: "  Alice@Example.invalid  ", Password: "new-account-password",
		DisplayName: " Alice ", TimeZone: " Asia/Shanghai ", WeekStartsOn: 1,
	}
}

func TestProvisionerNormalizesAndStoresArgon2Password(t *testing.T) {
	store := &provisionStore{}
	provisioner := NewProvisioner(store)
	now := time.Date(2026, 10, 11, 12, 30, 0, 0, time.FixedZone("UTC+8", 8*60*60))
	provisioner.now = func() time.Time { return now }
	input := validAccountInput()
	user, err := provisioner.Create(context.Background(), input)
	if err != nil {
		t.Fatal(err)
	}
	if user.Email != "alice@example.invalid" || user.DisplayName != "Alice" || user.TimeZone != "Asia/Shanghai" || user.Locale != "zh-CN" {
		t.Fatalf("unexpected account: %+v", user)
	}
	if _, err := uuid.Parse(user.ID); err != nil || !user.CreatedAt.Equal(now) || user.CreatedAt.Location() != time.UTC {
		t.Fatalf("unexpected generated ID or timestamp: %+v", user)
	}
	if store.user != user || !strings.HasPrefix(store.hash, "$argon2id$") || strings.Contains(store.hash, input.Password) {
		t.Fatal("account was not stored with an Argon2id hash")
	}
	valid, err := DefaultPasswordHasher().Verify(input.Password, store.hash)
	if err != nil || !valid {
		t.Fatal("provisioned password is not compatible with login verification")
	}
}

func TestProvisionerRejectsInvalidInputBeforeStorage(t *testing.T) {
	for _, test := range []struct {
		name   string
		change func(*AccountInput)
	}{
		{"email", func(in *AccountInput) { in.Email = "not-an-email" }},
		{"short password", func(in *AccountInput) { in.Password = "short" }},
		{"long password", func(in *AccountInput) { in.Password = strings.Repeat("x", 1025) }},
		{"display name", func(in *AccountInput) { in.DisplayName = " " }},
		{"time zone", func(in *AccountInput) { in.TimeZone = "missing/location" }},
		{"locale", func(in *AccountInput) { in.Locale = strings.Repeat("x", 36) }},
		{"week start", func(in *AccountInput) { in.WeekStartsOn = 7 }},
	} {
		t.Run(test.name, func(t *testing.T) {
			store := &provisionStore{}
			input := validAccountInput()
			test.change(&input)
			_, err := NewProvisioner(store).Create(context.Background(), input)
			var inputErr *InputError
			if !errors.As(err, &inputErr) || store.call {
				t.Fatalf("invalid input reached storage: error=%v called=%v", err, store.call)
			}
		})
	}
}

func TestProvisionerPreservesDuplicateError(t *testing.T) {
	store := &provisionStore{err: ErrEmailTaken}
	user, err := NewProvisioner(store).Create(context.Background(), validAccountInput())
	if !errors.Is(err, ErrEmailTaken) || user != (User{}) {
		t.Fatalf("Create() = %+v, %v", user, err)
	}
}

func TestProvisionerDoesNotWriteAfterCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	store := &provisionStore{}
	_, err := NewProvisioner(store).Create(ctx, validAccountInput())
	if !errors.Is(err, context.Canceled) || store.call {
		t.Fatalf("cancelled request reached storage: error=%v called=%v", err, store.call)
	}
}
