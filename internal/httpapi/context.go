package httpapi

import (
	"context"

	"pactick/server/internal/auth"
)

type contextKey string

const (
	principalKey contextKey = "principal"
	requestIDKey contextKey = "request_id"
)

func withPrincipal(ctx context.Context, principal auth.Principal) context.Context {
	return context.WithValue(ctx, principalKey, principal)
}

func principalFrom(ctx context.Context) auth.Principal {
	principal, _ := ctx.Value(principalKey).(auth.Principal)
	return principal
}

func requestIDFrom(ctx context.Context) string {
	value, _ := ctx.Value(requestIDKey).(string)
	return value
}
