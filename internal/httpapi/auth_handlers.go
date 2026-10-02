package httpapi

import (
	"net/http"
	"strings"

	"pactick/server/internal/auth"
)

type registerRequest struct {
	Email        string      `json:"email"`
	Password     string      `json:"password"`
	DisplayName  string      `json:"display_name"`
	TimeZone     string      `json:"time_zone"`
	Locale       string      `json:"locale"`
	WeekStartsOn *int        `json:"week_starts_on"`
	Device       auth.Device `json:"device"`
}

type loginRequest struct {
	Email    string      `json:"email"`
	Password string      `json:"password"`
	Device   auth.Device `json:"device"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type updateProfileRequest struct {
	DisplayName  *string `json:"display_name"`
	TimeZone     *string `json:"time_zone"`
	Locale       *string `json:"locale"`
	WeekStartsOn *int    `json:"week_starts_on"`
}

func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	if !s.registrationEnabled {
		writeError(w, r, http.StatusForbidden, "registration_disabled", "new account registration is disabled", nil)
		return
	}
	var request registerRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_json", err.Error(), nil)
		return
	}
	weekStartsOn := 1
	if request.WeekStartsOn != nil {
		weekStartsOn = *request.WeekStartsOn
	}
	session, err := s.auth.Register(r.Context(), auth.RegisterInput{
		Email:        request.Email,
		Password:     request.Password,
		DisplayName:  request.DisplayName,
		TimeZone:     request.TimeZone,
		Locale:       request.Locale,
		WeekStartsOn: weekStartsOn,
		Device:       request.Device,
	})
	if err != nil {
		s.authError(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, session)
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var request loginRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_json", err.Error(), nil)
		return
	}
	session, err := s.auth.Login(r.Context(), auth.LoginInput{
		Email: request.Email, Password: request.Password, Device: request.Device,
	})
	if err != nil {
		s.authError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, session)
}

func (s *Server) refresh(w http.ResponseWriter, r *http.Request) {
	var request refreshRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_json", err.Error(), nil)
		return
	}
	session, err := s.auth.Refresh(r.Context(), request.RefreshToken)
	if err != nil {
		s.authError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, session)
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	var request refreshRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_json", err.Error(), nil)
		return
	}
	if err := s.auth.Logout(r.Context(), strings.TrimSpace(request.RefreshToken)); err != nil {
		s.authError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	principal := principalFrom(r.Context())
	user, err := s.auth.Me(r.Context(), principal.UserID)
	if err != nil {
		s.authError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, user)
}

func (s *Server) updateProfile(w http.ResponseWriter, r *http.Request) {
	var request updateProfileRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_json", err.Error(), nil)
		return
	}
	principal := principalFrom(r.Context())
	user, err := s.auth.UpdateProfile(r.Context(), principal.UserID, auth.ProfileUpdate{
		DisplayName: request.DisplayName, TimeZone: request.TimeZone,
		Locale: request.Locale, WeekStartsOn: request.WeekStartsOn,
	})
	if err != nil {
		s.authError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, user)
}

func (s *Server) devices(w http.ResponseWriter, r *http.Request) {
	principal := principalFrom(r.Context())
	devices, err := s.auth.Devices(r.Context(), principal.UserID)
	if err != nil {
		s.authError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"devices": devices})
}

func (s *Server) revokeDevice(w http.ResponseWriter, r *http.Request) {
	principal := principalFrom(r.Context())
	if err := s.auth.RevokeDevice(r.Context(), principal.UserID, r.PathValue("device_id")); err != nil {
		s.authError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
