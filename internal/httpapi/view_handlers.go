package httpapi

import (
	"net/http"
	"time"
)

func (s *Server) today(w http.ResponseWriter, r *http.Request) {
	principal := principalFrom(r.Context())
	date := r.URL.Query().Get("date")
	timeZone := r.URL.Query().Get("time_zone")
	if date == "" || timeZone == "" {
		user, err := s.auth.Me(r.Context(), principal.UserID)
		if err != nil {
			s.authError(w, r, err)
			return
		}
		if timeZone == "" {
			timeZone = user.TimeZone
		}
		if date == "" {
			location, err := time.LoadLocation(timeZone)
			if err != nil {
				writeError(w, r, http.StatusBadRequest, "invalid_time_zone", "time_zone must be an IANA time zone", nil)
				return
			}
			date = time.Now().In(location).Format("2006-01-02")
		}
	}
	view, err := s.views.Today(r.Context(), principal.UserID, date, timeZone)
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_today_query", err.Error(), nil)
		return
	}
	writeJSON(w, http.StatusOK, view)
}

func (s *Server) calendar(w http.ResponseWriter, r *http.Request) {
	startsAt, err := time.Parse(time.RFC3339Nano, r.URL.Query().Get("starts_at"))
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_starts_at", "starts_at must be an RFC 3339 timestamp", nil)
		return
	}
	endsAt, err := time.Parse(time.RFC3339Nano, r.URL.Query().Get("ends_at"))
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_ends_at", "ends_at must be an RFC 3339 timestamp", nil)
		return
	}
	principal := principalFrom(r.Context())
	view, err := s.views.Calendar(r.Context(), principal.UserID, startsAt, endsAt)
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_calendar_query", err.Error(), nil)
		return
	}
	writeJSON(w, http.StatusOK, view)
}

func (s *Server) summary(w http.ResponseWriter, r *http.Request) {
	principal := principalFrom(r.Context())
	startsOn := r.URL.Query().Get("starts_on")
	endsOn := r.URL.Query().Get("ends_on")
	timeZone := r.URL.Query().Get("time_zone")
	user, err := s.auth.Me(r.Context(), principal.UserID)
	if err != nil {
		s.authError(w, r, err)
		return
	}
	if timeZone == "" {
		timeZone = user.TimeZone
	}
	location, err := time.LoadLocation(timeZone)
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_time_zone", "time_zone must be an IANA time zone", nil)
		return
	}
	if endsOn == "" {
		endsOn = time.Now().In(location).Format("2006-01-02")
	}
	if startsOn == "" {
		end, parseErr := time.ParseInLocation("2006-01-02", endsOn, location)
		if parseErr != nil {
			writeError(w, r, http.StatusBadRequest, "invalid_ends_on", "ends_on must use YYYY-MM-DD format", nil)
			return
		}
		startsOn = end.AddDate(0, 0, -6).Format("2006-01-02")
	}
	result, err := s.views.Summary(r.Context(), principal.UserID, startsOn, endsOn, timeZone)
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_statistics_query", err.Error(), nil)
		return
	}
	writeJSON(w, http.StatusOK, result)
}
