package auth

import (
	"context"
	"testing"
	"time"
)

type profileStore struct {
	Store
	user       User
	lastUpdate ProfileUpdate
	active     bool
}

func (s *profileStore) GetUser(_ context.Context, _ string) (User, error) {
	return s.user, nil
}

func (s *profileStore) UpdateUser(_ context.Context, _ string, update ProfileUpdate) (User, error) {
	s.lastUpdate = update
	if update.DisplayName != nil {
		s.user.DisplayName = *update.DisplayName
	}
	if update.TimeZone != nil {
		s.user.TimeZone = *update.TimeZone
	}
	if update.Locale != nil {
		s.user.Locale = *update.Locale
	}
	if update.WeekStartsOn != nil {
		s.user.WeekStartsOn = *update.WeekStartsOn
	}
	return s.user, nil
}

func (s *profileStore) IsDeviceActive(_ context.Context, _, _ string) (bool, error) {
	return s.active, nil
}

func TestUpdateProfileNormalizesValues(t *testing.T) {
	store := &profileStore{user: User{
		ID: "d89f2a7c-23c3-4e9a-b10d-62548765455c", DisplayName: "Old",
		TimeZone: "UTC", Locale: "en", WeekStartsOn: 1, CreatedAt: time.Now(),
	}}
	service := &Service{store: store}
	displayName := "  New Name  "
	timeZone := " Asia/Shanghai "
	locale := " zh-CN "
	updated, err := service.UpdateProfile(context.Background(), store.user.ID, ProfileUpdate{
		DisplayName: &displayName, TimeZone: &timeZone, Locale: &locale,
	})
	if err != nil {
		t.Fatalf("UpdateProfile() error = %v", err)
	}
	if updated.DisplayName != "New Name" || updated.TimeZone != "Asia/Shanghai" || updated.Locale != "zh-CN" {
		t.Fatalf("UpdateProfile() = %#v", updated)
	}
}

func TestValidatePrincipalUsesCurrentDeviceState(t *testing.T) {
	store := &profileStore{active: true}
	service := &Service{store: store}
	active, err := service.ValidatePrincipal(context.Background(), Principal{UserID: "user", DeviceID: "device"})
	if err != nil || !active {
		t.Fatalf("ValidatePrincipal() = %v, %v", active, err)
	}
}
