package httpapi

import (
	"errors"
	"net/http"

	"pactick/server/internal/auth"
)

type deleteAccountRequest struct {
	Password     string `json:"password"`
	Confirmation string `json:"confirmation"`
}

func (s *Server) exportAccount(w http.ResponseWriter, r *http.Request) {
	principal := principalFrom(r.Context())
	export, err := s.account.Build(r.Context(), principal.UserID)
	if err != nil {
		if errors.Is(err, auth.ErrInvalidToken) {
			s.authError(w, r, err)
			return
		}
		s.logger.Error("account export failed", "error", err, "request_id", requestIDFrom(r.Context()))
		writeError(w, r, http.StatusInternalServerError, "export_failed", "account data could not be exported", nil)
		return
	}
	w.Header().Set("Content-Disposition", `attachment; filename="pactick-export.json"`)
	writeJSON(w, http.StatusOK, export)
}

func (s *Server) deleteAccount(w http.ResponseWriter, r *http.Request) {
	var request deleteAccountRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_json", err.Error(), nil)
		return
	}
	if request.Confirmation != "DELETE" {
		writeError(w, r, http.StatusUnprocessableEntity, "confirmation_required", "confirmation must equal DELETE", nil)
		return
	}
	principal := principalFrom(r.Context())
	if err := s.auth.DeleteAccount(r.Context(), principal.UserID, request.Password); err != nil {
		s.authError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
