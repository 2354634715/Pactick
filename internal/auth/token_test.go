package auth

import (
	"strings"
	"testing"
	"time"
)

func TestAccessTokenRoundTrip(t *testing.T) {
	issuer := NewAccessTokenIssuer(strings.Repeat("s", 32), 15*time.Minute)
	userID := "d89f2a7c-23c3-4e9a-b10d-62548765455c"
	deviceID := "7b87bbcb-dcb6-4d88-8a94-b115899b8307"
	raw, expiresAt, err := issuer.Issue(userID, deviceID)
	if err != nil {
		t.Fatalf("Issue() error = %v", err)
	}
	if !expiresAt.After(time.Now()) {
		t.Fatal("Issue() returned an expired token")
	}
	principal, err := issuer.Parse(raw)
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}
	if principal.UserID != userID || principal.DeviceID != deviceID {
		t.Fatalf("Parse() principal = %#v", principal)
	}
	if _, err := issuer.Parse(raw + "tampered"); err == nil {
		t.Fatal("Parse() accepted a tampered token")
	}
}

func TestRefreshSecretIsHashed(t *testing.T) {
	raw, hash, err := newRefreshSecret()
	if err != nil {
		t.Fatalf("newRefreshSecret() error = %v", err)
	}
	if raw == "" || len(hash) != 32 {
		t.Fatalf("newRefreshSecret() returned invalid values")
	}
	actual := hashRefreshSecret(raw)
	if string(actual) != string(hash) {
		t.Fatal("hashRefreshSecret() does not reproduce the stored hash")
	}
}
