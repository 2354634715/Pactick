package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

const tokenIssuer = "pactick-server"

type AccessTokenIssuer struct {
	secret []byte
	ttl    time.Duration
	now    func() time.Time
}

type accessClaims struct {
	DeviceID string `json:"device_id"`
	jwt.RegisteredClaims
}

func NewAccessTokenIssuer(secret string, ttl time.Duration) *AccessTokenIssuer {
	return &AccessTokenIssuer{secret: []byte(secret), ttl: ttl, now: time.Now}
}

func (i *AccessTokenIssuer) Issue(userID, deviceID string) (string, time.Time, error) {
	now := i.now().UTC()
	expiresAt := now.Add(i.ttl)
	claims := accessClaims{
		DeviceID: deviceID,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    tokenIssuer,
			Subject:   userID,
			ExpiresAt: jwt.NewNumericDate(expiresAt),
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now.Add(-5 * time.Second)),
			ID:        uuid.NewString(),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString(i.secret)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("sign access token: %w", err)
	}
	return signed, expiresAt, nil
}

func (i *AccessTokenIssuer) Parse(raw string) (Principal, error) {
	claims := new(accessClaims)
	token, err := jwt.ParseWithClaims(raw, claims, func(token *jwt.Token) (any, error) {
		if token.Method != jwt.SigningMethodHS256 {
			return nil, errors.New("unexpected signing method")
		}
		return i.secret, nil
	}, jwt.WithIssuer(tokenIssuer), jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}))
	if err != nil || !token.Valid || claims.Subject == "" || claims.DeviceID == "" {
		return Principal{}, ErrInvalidToken
	}
	if _, err := uuid.Parse(claims.Subject); err != nil {
		return Principal{}, ErrInvalidToken
	}
	if _, err := uuid.Parse(claims.DeviceID); err != nil {
		return Principal{}, ErrInvalidToken
	}
	return Principal{UserID: claims.Subject, DeviceID: claims.DeviceID}, nil
}

func newRefreshSecret() (string, []byte, error) {
	random := make([]byte, 32)
	if _, err := rand.Read(random); err != nil {
		return "", nil, fmt.Errorf("generate refresh token: %w", err)
	}
	raw := base64.RawURLEncoding.EncodeToString(random)
	hash := sha256.Sum256([]byte(raw))
	return raw, hash[:], nil
}

func hashRefreshSecret(raw string) []byte {
	hash := sha256.Sum256([]byte(raw))
	return hash[:]
}
