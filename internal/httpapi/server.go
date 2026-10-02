package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"pactick/server/internal/account"
	"pactick/server/internal/auth"
	"pactick/server/internal/clientupdate"
	"pactick/server/internal/realtime"
	syncservice "pactick/server/internal/sync"
	"pactick/server/internal/views"
)

type Server struct {
	logger              *slog.Logger
	pool                *pgxpool.Pool
	account             *account.Service
	auth                *auth.Service
	sync                *syncservice.Service
	views               *views.Store
	hub                 *realtime.Hub
	clientUpdates       *clientupdate.Catalog
	allowedOrigins      []string
	registrationEnabled bool
	mux                 *http.ServeMux
}

func New(
	logger *slog.Logger,
	pool *pgxpool.Pool,
	accountService *account.Service,
	authService *auth.Service,
	syncService *syncservice.Service,
	viewStore *views.Store,
	hub *realtime.Hub,
	clientUpdates *clientupdate.Catalog,
	allowedOrigins []string,
	registrationEnabled bool,
) *Server {
	server := &Server{
		logger:              logger,
		pool:                pool,
		account:             accountService,
		auth:                authService,
		sync:                syncService,
		views:               viewStore,
		hub:                 hub,
		clientUpdates:       clientUpdates,
		allowedOrigins:      allowedOrigins,
		registrationEnabled: registrationEnabled,
		mux:                 http.NewServeMux(),
	}
	server.routes()
	return server
}

func (s *Server) Handler() http.Handler {
	return s.middleware(s.mux)
}

func (s *Server) routes() {
	s.mux.HandleFunc("GET /healthz", s.health)
	s.mux.HandleFunc("GET /readyz", s.ready)
	s.mux.HandleFunc("GET /v1/client-updates/check", s.checkClientUpdate)
	s.mux.HandleFunc("POST /v1/auth/register", s.register)
	s.mux.HandleFunc("POST /v1/auth/login", s.login)
	s.mux.HandleFunc("POST /v1/auth/refresh", s.refresh)
	s.mux.HandleFunc("POST /v1/auth/logout", s.logout)
	s.mux.Handle("GET /v1/me", s.requireAuth(http.HandlerFunc(s.me)))
	s.mux.Handle("PATCH /v1/me", s.requireAuth(http.HandlerFunc(s.updateProfile)))
	s.mux.Handle("GET /v1/devices", s.requireAuth(http.HandlerFunc(s.devices)))
	s.mux.Handle("DELETE /v1/devices/{device_id}", s.requireAuth(http.HandlerFunc(s.revokeDevice)))
	s.mux.Handle("GET /v1/account/export", s.requireAuth(http.HandlerFunc(s.exportAccount)))
	s.mux.Handle("DELETE /v1/account", s.requireAuth(http.HandlerFunc(s.deleteAccount)))
	s.mux.Handle("POST /v1/sync/push", s.requireAuth(http.HandlerFunc(s.push)))
	s.mux.Handle("GET /v1/sync/pull", s.requireAuth(http.HandlerFunc(s.pull)))
	s.mux.Handle("GET /v1/views/today", s.requireAuth(http.HandlerFunc(s.today)))
	s.mux.Handle("GET /v1/views/calendar", s.requireAuth(http.HandlerFunc(s.calendar)))
	s.mux.Handle("GET /v1/stats/summary", s.requireAuth(http.HandlerFunc(s.summary)))
	s.mux.Handle("GET /v1/ws", s.requireAuth(http.HandlerFunc(s.websocket)))
}

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.pool.Ping(ctx); err != nil {
		writeError(w, r, http.StatusServiceUnavailable, "not_ready", "database is unavailable", nil)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (s *Server) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := strings.TrimSpace(r.Header.Get("Authorization"))
		scheme, raw, found := strings.Cut(header, " ")
		if !found || !strings.EqualFold(scheme, "Bearer") || strings.TrimSpace(raw) == "" {
			writeError(w, r, http.StatusUnauthorized, "authentication_required", "a bearer access token is required", nil)
			return
		}
		principal, err := s.auth.ParseAccessToken(strings.TrimSpace(raw))
		if err != nil {
			writeError(w, r, http.StatusUnauthorized, "invalid_access_token", "access token is invalid or expired", nil)
			return
		}
		active, err := s.auth.ValidatePrincipal(r.Context(), principal)
		if err != nil {
			s.logger.Error("principal validation failed", "error", err, "request_id", requestIDFrom(r.Context()))
			writeError(w, r, http.StatusServiceUnavailable, "authentication_unavailable", "authentication state could not be verified", nil)
			return
		}
		if !active {
			writeError(w, r, http.StatusUnauthorized, "device_revoked", "device is no longer active", nil)
			return
		}
		next.ServeHTTP(w, r.WithContext(withPrincipal(r.Context(), principal)))
	})
}

func (s *Server) authError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, auth.ErrEmailTaken):
		writeError(w, r, http.StatusConflict, "email_taken", err.Error(), nil)
	case errors.Is(err, auth.ErrInvalidCredentials):
		writeError(w, r, http.StatusUnauthorized, "invalid_credentials", "email or password is incorrect", nil)
	case errors.Is(err, auth.ErrInvalidToken):
		writeError(w, r, http.StatusUnauthorized, "invalid_refresh_token", "refresh token is invalid or expired", nil)
	case errors.Is(err, auth.ErrTokenReuse):
		writeError(w, r, http.StatusUnauthorized, "refresh_token_reuse", "the refresh token family has been revoked", nil)
	case errors.Is(err, auth.ErrDeviceConflict):
		writeError(w, r, http.StatusConflict, "device_conflict", err.Error(), nil)
	case errors.Is(err, auth.ErrDeviceNotFound):
		writeError(w, r, http.StatusNotFound, "device_not_found", err.Error(), nil)
	default:
		var inputErr *auth.InputError
		if errors.As(err, &inputErr) {
			writeError(w, r, http.StatusUnprocessableEntity, "validation_error", err.Error(), nil)
			return
		}
		s.logger.Error("authentication request failed", "error", err, "request_id", requestIDFrom(r.Context()))
		writeError(w, r, http.StatusInternalServerError, "internal_error", "an internal error occurred", nil)
	}
}
