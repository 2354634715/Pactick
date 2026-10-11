package auth

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"
)

// AccountInput describes an account without creating a device or a login session.
type AccountInput struct {
	Email        string
	Password     string
	DisplayName  string
	TimeZone     string
	Locale       string
	WeekStartsOn int
}

type AccountProvisionStore interface {
	CreateLocalAccount(context.Context, User, string) error
}

// Provisioner creates accounts through a trusted local database connection.
// It does not depend on the public registration setting and does not issue tokens.
type Provisioner struct {
	store  AccountProvisionStore
	hasher PasswordHasher
	now    func() time.Time
}

func NewProvisioner(store AccountProvisionStore) *Provisioner {
	return &Provisioner{store: store, hasher: DefaultPasswordHasher(), now: time.Now}
}

// NormalizeAccountInput applies the same rules as public registration.
func NormalizeAccountInput(input AccountInput) (AccountInput, error) {
	email, err := normalizeEmail(input.Email)
	if err != nil {
		return AccountInput{}, &InputError{Message: err.Error()}
	}
	if len(input.Password) < 10 || len(input.Password) > 1024 {
		return AccountInput{}, &InputError{Message: "password must contain between 10 and 1024 characters"}
	}
	input.Email = email
	input.DisplayName = strings.TrimSpace(input.DisplayName)
	input.TimeZone = strings.TrimSpace(input.TimeZone)
	input.Locale = strings.TrimSpace(input.Locale)
	if input.Locale == "" {
		input.Locale = "zh-CN"
	}
	if err := validateProfile(input.DisplayName, input.TimeZone, input.Locale, input.WeekStartsOn); err != nil {
		return AccountInput{}, &InputError{Message: err.Error()}
	}
	return input, nil
}

func accountUser(input AccountInput, now time.Time) User {
	return User{
		ID:           uuid.NewString(),
		Email:        input.Email,
		DisplayName:  input.DisplayName,
		TimeZone:     input.TimeZone,
		Locale:       input.Locale,
		WeekStartsOn: input.WeekStartsOn,
		CreatedAt:    now.UTC(),
	}
}

func (p *Provisioner) Create(ctx context.Context, input AccountInput) (User, error) {
	input, err := NormalizeAccountInput(input)
	if err != nil {
		return User{}, err
	}
	if err := ctx.Err(); err != nil {
		return User{}, err
	}
	passwordHash, err := p.hasher.Hash(input.Password)
	if err != nil {
		return User{}, err
	}
	user := accountUser(input, p.now())
	if err := p.store.CreateLocalAccount(ctx, user, passwordHash); err != nil {
		return User{}, err
	}
	return user, nil
}
