package auth

import (
	"errors"
	"time"
)

var (
	ErrEmailTaken         = errors.New("email is already registered")
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrInvalidToken       = errors.New("invalid token")
	ErrTokenReuse         = errors.New("refresh token reuse detected")
	ErrDeviceConflict     = errors.New("device belongs to another account")
	ErrDeviceNotFound     = errors.New("device was not found")
)

type User struct {
	ID           string    `json:"id"`
	Email        string    `json:"email"`
	DisplayName  string    `json:"display_name"`
	TimeZone     string    `json:"time_zone"`
	Locale       string    `json:"locale"`
	WeekStartsOn int       `json:"week_starts_on"`
	CreatedAt    time.Time `json:"created_at"`
}

type Device struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Platform   string `json:"platform"`
	AppVersion string `json:"app_version"`
}

type DeviceInfo struct {
	Device
	CreatedAt  time.Time  `json:"created_at"`
	LastSeenAt time.Time  `json:"last_seen_at"`
	RevokedAt  *time.Time `json:"revoked_at,omitempty"`
}

type ProfileUpdate struct {
	DisplayName  *string
	TimeZone     *string
	Locale       *string
	WeekStartsOn *int
}

type Principal struct {
	UserID   string
	DeviceID string
}

type TokenPair struct {
	AccessToken      string    `json:"access_token"`
	AccessExpiresAt  time.Time `json:"access_expires_at"`
	RefreshToken     string    `json:"refresh_token"`
	RefreshExpiresAt time.Time `json:"refresh_expires_at"`
	TokenType        string    `json:"token_type"`
}

type Session struct {
	User   User      `json:"user"`
	Device Device    `json:"device"`
	Tokens TokenPair `json:"tokens"`
}

type RefreshRecord struct {
	ID        string
	FamilyID  string
	UserID    string
	DeviceID  string
	TokenHash []byte
	ExpiresAt time.Time
	CreatedAt time.Time
}

type InputError struct {
	Message string
}

func (e *InputError) Error() string {
	return e.Message
}
