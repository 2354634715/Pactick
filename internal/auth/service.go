package auth

import (
	"context"
	"errors"
	"fmt"
	"net/mail"
	"strings"
	"time"

	"github.com/google/uuid"
)

type Service struct {
	store      Store
	hasher     PasswordHasher
	issuer     *AccessTokenIssuer
	refreshTTL time.Duration
	now        func() time.Time
	dummyHash  string
}

type RegisterInput struct {
	Email        string
	Password     string
	DisplayName  string
	TimeZone     string
	Locale       string
	WeekStartsOn int
	Device       Device
}

type LoginInput struct {
	Email    string
	Password string
	Device   Device
}

func NewService(store Store, issuer *AccessTokenIssuer, refreshTTL time.Duration) *Service {
	hasher := DefaultPasswordHasher()
	dummyHash, _ := hasher.Hash("dummy-password-used-for-login-timing")
	return &Service{
		store:      store,
		hasher:     hasher,
		issuer:     issuer,
		refreshTTL: refreshTTL,
		now:        time.Now,
		dummyHash:  dummyHash,
	}
}

func (s *Service) Register(ctx context.Context, input RegisterInput) (Session, error) {
	email, err := normalizeEmail(input.Email)
	if err != nil {
		return Session{}, &InputError{Message: err.Error()}
	}
	if len(input.Password) < 10 || len(input.Password) > 1024 {
		return Session{}, &InputError{Message: "password must contain between 10 and 1024 characters"}
	}
	input.DisplayName = strings.TrimSpace(input.DisplayName)
	input.TimeZone = strings.TrimSpace(input.TimeZone)
	input.Locale = strings.TrimSpace(input.Locale)
	if input.Locale == "" {
		input.Locale = "zh-CN"
	}
	if err := validateProfile(input.DisplayName, input.TimeZone, input.Locale, input.WeekStartsOn); err != nil {
		return Session{}, &InputError{Message: err.Error()}
	}
	if err := validateDevice(input.Device); err != nil {
		return Session{}, &InputError{Message: err.Error()}
	}
	input.Device.Name = strings.TrimSpace(input.Device.Name)
	passwordHash, err := s.hasher.Hash(input.Password)
	if err != nil {
		return Session{}, err
	}
	now := s.now().UTC()
	user := User{
		ID:           uuid.NewString(),
		Email:        email,
		DisplayName:  input.DisplayName,
		TimeZone:     input.TimeZone,
		Locale:       input.Locale,
		WeekStartsOn: input.WeekStartsOn,
		CreatedAt:    now,
	}
	refresh, rawRefresh, err := s.newRefresh(user.ID, input.Device.ID, uuid.NewString(), now)
	if err != nil {
		return Session{}, err
	}
	if err := s.store.CreateAccount(ctx, user, passwordHash, input.Device, refresh); err != nil {
		return Session{}, err
	}
	tokens, err := s.issuePair(user.ID, input.Device.ID, rawRefresh, refresh.ExpiresAt)
	if err != nil {
		return Session{}, err
	}
	return Session{User: user, Device: input.Device, Tokens: tokens}, nil
}

func (s *Service) Login(ctx context.Context, input LoginInput) (Session, error) {
	email, err := normalizeEmail(input.Email)
	if err != nil {
		return Session{}, ErrInvalidCredentials
	}
	if err := validateDevice(input.Device); err != nil {
		return Session{}, &InputError{Message: err.Error()}
	}
	input.Device.Name = strings.TrimSpace(input.Device.Name)
	user, passwordHash, err := s.store.FindUserByEmail(ctx, email)
	if err != nil {
		if errors.Is(err, ErrInvalidCredentials) && s.dummyHash != "" {
			_, _ = s.hasher.Verify(input.Password, s.dummyHash)
		}
		return Session{}, err
	}
	valid, verifyErr := s.hasher.Verify(input.Password, passwordHash)
	if verifyErr != nil || !valid {
		return Session{}, ErrInvalidCredentials
	}
	now := s.now().UTC()
	refresh, rawRefresh, err := s.newRefresh(user.ID, input.Device.ID, uuid.NewString(), now)
	if err != nil {
		return Session{}, err
	}
	if err := s.store.CreateSession(ctx, user.ID, input.Device, refresh); err != nil {
		return Session{}, err
	}
	tokens, err := s.issuePair(user.ID, input.Device.ID, rawRefresh, refresh.ExpiresAt)
	if err != nil {
		return Session{}, err
	}
	return Session{User: user, Device: input.Device, Tokens: tokens}, nil
}

func (s *Service) Refresh(ctx context.Context, rawToken string) (Session, error) {
	if strings.TrimSpace(rawToken) == "" {
		return Session{}, ErrInvalidToken
	}
	now := s.now().UTC()
	replacement, rawReplacement, err := s.newRefresh("", "", "", now)
	if err != nil {
		return Session{}, err
	}
	user, device, err := s.store.RotateRefreshToken(ctx, hashRefreshSecret(rawToken), replacement)
	if err != nil {
		return Session{}, err
	}
	tokens, err := s.issuePair(user.ID, device.ID, rawReplacement, replacement.ExpiresAt)
	if err != nil {
		return Session{}, err
	}
	return Session{User: user, Device: device, Tokens: tokens}, nil
}

func (s *Service) Logout(ctx context.Context, rawRefresh string) error {
	if strings.TrimSpace(rawRefresh) == "" {
		return nil
	}
	return s.store.RevokeRefreshToken(ctx, hashRefreshSecret(rawRefresh))
}

func (s *Service) ParseAccessToken(raw string) (Principal, error) {
	return s.issuer.Parse(raw)
}

func (s *Service) ValidatePrincipal(ctx context.Context, principal Principal) (bool, error) {
	return s.store.IsDeviceActive(ctx, principal.UserID, principal.DeviceID)
}

func (s *Service) Me(ctx context.Context, userID string) (User, error) {
	return s.store.GetUser(ctx, userID)
}

func (s *Service) UpdateProfile(ctx context.Context, userID string, update ProfileUpdate) (User, error) {
	if update.DisplayName == nil && update.TimeZone == nil && update.Locale == nil && update.WeekStartsOn == nil {
		return User{}, &InputError{Message: "at least one profile field is required"}
	}
	current, err := s.store.GetUser(ctx, userID)
	if err != nil {
		return User{}, err
	}
	displayName := current.DisplayName
	timeZone := current.TimeZone
	locale := current.Locale
	weekStartsOn := current.WeekStartsOn
	if update.DisplayName != nil {
		displayName = strings.TrimSpace(*update.DisplayName)
		update.DisplayName = &displayName
	}
	if update.TimeZone != nil {
		timeZone = strings.TrimSpace(*update.TimeZone)
		update.TimeZone = &timeZone
	}
	if update.Locale != nil {
		locale = strings.TrimSpace(*update.Locale)
		update.Locale = &locale
		if strings.TrimSpace(locale) == "" {
			return User{}, &InputError{Message: "locale must not be empty"}
		}
	}
	if update.WeekStartsOn != nil {
		weekStartsOn = *update.WeekStartsOn
	}
	if err := validateProfile(displayName, timeZone, locale, weekStartsOn); err != nil {
		return User{}, &InputError{Message: err.Error()}
	}
	return s.store.UpdateUser(ctx, userID, update)
}

func (s *Service) Devices(ctx context.Context, userID string) ([]DeviceInfo, error) {
	return s.store.ListDevices(ctx, userID)
}

func (s *Service) RevokeDevice(ctx context.Context, userID, deviceID string) error {
	if _, err := uuid.Parse(deviceID); err != nil {
		return &InputError{Message: "device_id must be a UUID"}
	}
	return s.store.RevokeDevice(ctx, userID, deviceID)
}

func (s *Service) DeleteAccount(ctx context.Context, userID, password string) error {
	passwordHash, err := s.store.GetPasswordHash(ctx, userID)
	if err != nil {
		return err
	}
	valid, err := s.hasher.Verify(password, passwordHash)
	if err != nil || !valid {
		return ErrInvalidCredentials
	}
	return s.store.DeleteAccount(ctx, userID)
}

func (s *Service) newRefresh(userID, deviceID, familyID string, now time.Time) (RefreshRecord, string, error) {
	raw, hash, err := newRefreshSecret()
	if err != nil {
		return RefreshRecord{}, "", err
	}
	if familyID == "" {
		familyID = uuid.NewString()
	}
	return RefreshRecord{
		ID:        uuid.NewString(),
		FamilyID:  familyID,
		UserID:    userID,
		DeviceID:  deviceID,
		TokenHash: hash,
		ExpiresAt: now.Add(s.refreshTTL),
		CreatedAt: now,
	}, raw, nil
}

func (s *Service) issuePair(userID, deviceID, rawRefresh string, refreshExpiresAt time.Time) (TokenPair, error) {
	access, accessExpiresAt, err := s.issuer.Issue(userID, deviceID)
	if err != nil {
		return TokenPair{}, err
	}
	return TokenPair{
		AccessToken:      access,
		AccessExpiresAt:  accessExpiresAt,
		RefreshToken:     rawRefresh,
		RefreshExpiresAt: refreshExpiresAt,
		TokenType:        "Bearer",
	}, nil
}

func normalizeEmail(value string) (string, error) {
	value = strings.ToLower(strings.TrimSpace(value))
	parsed, err := mail.ParseAddress(value)
	if err != nil || parsed.Address != value || len(value) > 320 {
		return "", errors.New("email is invalid")
	}
	return value, nil
}

func validateProfile(displayName, timeZone, locale string, weekStartsOn int) error {
	if nameLength := len([]rune(strings.TrimSpace(displayName))); nameLength < 1 || nameLength > 80 {
		return errors.New("display_name must contain between 1 and 80 characters")
	}
	if _, err := time.LoadLocation(timeZone); err != nil {
		return fmt.Errorf("time_zone is invalid: %w", err)
	}
	if len(locale) > 35 {
		return errors.New("locale is too long")
	}
	if weekStartsOn < 0 || weekStartsOn > 6 {
		return errors.New("week_starts_on must be between 0 and 6")
	}
	return nil
}

func validateDevice(device Device) error {
	if _, err := uuid.Parse(device.ID); err != nil {
		return errors.New("device.id must be a UUID")
	}
	if nameLength := len([]rune(strings.TrimSpace(device.Name))); nameLength < 1 || nameLength > 120 {
		return errors.New("device.name must contain between 1 and 120 characters")
	}
	switch device.Platform {
	case "android", "windows", "linux":
	default:
		return errors.New("device.platform is unsupported")
	}
	if len(device.AppVersion) > 40 {
		return errors.New("device.app_version is too long")
	}
	return nil
}
