package auth

import (
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"

	"pactick/server/internal/database"
	"pactick/server/internal/testpostgres"
)

func TestPostgresProvisionedAccountCanLoginWithoutSyntheticSession(t *testing.T) {
	f := testpostgres.New(t)
	if err := database.Migrate(f.Ctx, f.Pool); err != nil {
		t.Fatal(err)
	}
	store := NewPostgresStore(f.Pool)
	input := validAccountInput()
	provisioner := NewProvisioner(store)
	user, err := provisioner.Create(f.Ctx, input)
	if err != nil {
		t.Fatal(err)
	}
	assertAccountCounts := func(users, devices, tokens int) {
		t.Helper()
		var actualUsers, actualDevices, actualTokens int
		if err := f.Pool.QueryRow(f.Ctx, `SELECT
			(SELECT count(*) FROM users),
			(SELECT count(*) FROM devices),
			(SELECT count(*) FROM refresh_tokens)`).Scan(&actualUsers, &actualDevices, &actualTokens); err != nil {
			t.Fatal(err)
		}
		if actualUsers != users || actualDevices != devices || actualTokens != tokens {
			t.Fatalf("users/devices/tokens = %d/%d/%d, want %d/%d/%d", actualUsers, actualDevices, actualTokens, users, devices, tokens)
		}
	}
	assertAccountCounts(1, 0, 0)
	if _, err := provisioner.Create(f.Ctx, input); !errors.Is(err, ErrEmailTaken) {
		t.Fatalf("duplicate provision = %v", err)
	}
	assertAccountCounts(1, 0, 0)
	service := NewService(store, NewAccessTokenIssuer("test-only-secret-at-least-32-characters", 15*time.Minute), time.Hour)
	device := Device{ID: uuid.NewString(), Name: "Android", Platform: "android", AppVersion: "0.1.0"}
	session, err := service.Login(f.Ctx, LoginInput{Email: input.Email, Password: input.Password, Device: device})
	if err != nil || session.User.ID != user.ID || session.Tokens.AccessToken == "" || session.Tokens.RefreshToken == "" {
		t.Fatalf("provisioned account login failed: error=%v", err)
	}
	assertAccountCounts(1, 1, 1)
	if _, err := service.Login(f.Ctx, LoginInput{Email: input.Email, Password: "incorrect-password", Device: device}); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("wrong password login = %v", err)
	}
	assertAccountCounts(1, 1, 1)
	_, err = service.Register(f.Ctx, RegisterInput{
		Email: "public@example.invalid", Password: input.Password, DisplayName: "Public",
		TimeZone: "UTC", WeekStartsOn: 1,
		Device: Device{ID: uuid.NewString(), Name: "Windows", Platform: "windows"},
	})
	if err != nil {
		t.Fatalf("public registration failed after sharing account creation: %v", err)
	}
	assertAccountCounts(2, 2, 2)
}
