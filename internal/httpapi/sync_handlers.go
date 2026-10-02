package httpapi

import (
	"errors"
	"net/http"
	"strconv"

	syncservice "pactick/server/internal/sync"
)

type pushRequest struct {
	Operations []syncservice.Operation `json:"operations"`
}

func (s *Server) push(w http.ResponseWriter, r *http.Request) {
	var request pushRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_json", err.Error(), nil)
		return
	}
	principal := principalFrom(r.Context())
	response, err := s.sync.Push(r.Context(), principal.UserID, principal.DeviceID, request.Operations)
	if err != nil {
		if errors.Is(err, syncservice.ErrDeviceUnauthorized) {
			writeError(w, r, http.StatusUnauthorized, "device_revoked", "device is no longer active", nil)
			return
		}
		var apiErr *syncservice.APIError
		if errors.As(err, &apiErr) {
			writeError(w, r, http.StatusUnprocessableEntity, apiErr.Code, apiErr.Message, apiErr.Details)
			return
		}
		s.logger.Error("sync push failed", "error", err, "request_id", requestIDFrom(r.Context()))
		writeError(w, r, http.StatusInternalServerError, "sync_failed", "sync operation could not be completed", nil)
		return
	}
	writeJSON(w, http.StatusOK, response)
}

func (s *Server) pull(w http.ResponseWriter, r *http.Request) {
	after, err := parseIntQuery(r, "cursor", 0)
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_cursor", err.Error(), nil)
		return
	}
	limit64, err := parseIntQuery(r, "limit", 500)
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_limit", err.Error(), nil)
		return
	}
	principal := principalFrom(r.Context())
	response, err := s.sync.Pull(r.Context(), principal.UserID, after, int(limit64))
	if err != nil {
		var apiErr *syncservice.APIError
		if errors.As(err, &apiErr) {
			writeError(w, r, http.StatusBadRequest, apiErr.Code, apiErr.Message, apiErr.Details)
			return
		}
		s.logger.Error("sync pull failed", "error", err, "request_id", requestIDFrom(r.Context()))
		writeError(w, r, http.StatusInternalServerError, "sync_failed", "changes could not be loaded", nil)
		return
	}
	writeJSON(w, http.StatusOK, response)
}

func parseIntQuery(r *http.Request, name string, fallback int64) (int64, error) {
	value := r.URL.Query().Get(name)
	if value == "" {
		return fallback, nil
	}
	return strconv.ParseInt(value, 10, 64)
}
