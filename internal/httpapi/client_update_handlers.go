package httpapi

import (
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"pactick/server/internal/clientupdate"
)

const (
	clientUpdateStatusAvailable     = "update_available"
	clientUpdateStatusCurrent       = "up_to_date"
	clientUpdateStatusNotConfigured = "not_configured"
)

var clientUpdateQueryParameters = map[string]struct{}{
	"build_number":    {},
	"channel":         {},
	"current_version": {},
	"platform":        {},
}

const maxClientUpdateQueryBytes = 512

type clientUpdateCheckResponse struct {
	Status          string     `json:"status"`
	UpdateAvailable bool       `json:"update_available"`
	Required        bool       `json:"required"`
	Version         *string    `json:"version"`
	BuildNumber     *int64     `json:"build_number"`
	DownloadURL     *string    `json:"download_url"`
	SHA256          *string    `json:"sha256"`
	SizeBytes       *int64     `json:"size_bytes"`
	ReleaseNotes    *string    `json:"release_notes"`
	PublishedAt     *time.Time `json:"published_at"`
}

type updateQueryError struct {
	parameter string
	message   string
}

func (e *updateQueryError) Error() string {
	if e.parameter == "query" {
		return e.message
	}
	return fmt.Sprintf("%s %s", e.parameter, e.message)
}

func (s *Server) checkClientUpdate(w http.ResponseWriter, r *http.Request) {
	platform, channel, currentVersion, buildNumber, err := parseClientUpdateQuery(r.URL.RawQuery)
	if err != nil {
		var queryError *updateQueryError
		if !errors.As(err, &queryError) {
			queryError = &updateQueryError{parameter: "query", message: "query parameters are invalid"}
		}
		writeError(
			w,
			r,
			http.StatusBadRequest,
			"invalid_client_update_query",
			queryError.Error(),
			map[string]any{"parameter": queryError.parameter},
		)
		return
	}

	release, configured := s.clientUpdates.Lookup(platform, channel)
	if !configured {
		writeJSON(w, http.StatusOK, clientUpdateCheckResponse{
			Status: clientUpdateStatusNotConfigured,
		})
		return
	}

	versionComparison, err := clientupdate.CompareVersions(release.Version, currentVersion)
	if err != nil {
		// Release versions are validated at startup, and currentVersion was
		// validated above. Reaching this branch would indicate a programming
		// error rather than invalid client input.
		s.logger.Error("client update version comparison failed", "error", err, "request_id", requestIDFrom(r.Context()))
		writeError(w, r, http.StatusInternalServerError, "internal_error", "an internal error occurred", nil)
		return
	}
	updateAvailable := versionComparison > 0 || (versionComparison == 0 && release.BuildNumber > buildNumber)
	status := clientUpdateStatusCurrent
	if updateAvailable {
		status = clientUpdateStatusAvailable
	}

	writeJSON(w, http.StatusOK, responseForRelease(status, updateAvailable, release))
}

func parseClientUpdateQuery(rawQuery string) (platform, channel, currentVersion string, buildNumber int64, err error) {
	if len(rawQuery) > maxClientUpdateQueryBytes {
		return "", "", "", 0, &updateQueryError{parameter: "query", message: "query string is too long"}
	}
	query, parseErr := url.ParseQuery(rawQuery)
	if parseErr != nil {
		return "", "", "", 0, &updateQueryError{parameter: "query", message: "query string is malformed"}
	}
	for name := range query {
		if _, allowed := clientUpdateQueryParameters[name]; !allowed {
			return "", "", "", 0, &updateQueryError{parameter: name, message: "is not allowed"}
		}
	}

	platform, err = singleQueryValue(query, "platform")
	if err != nil {
		return "", "", "", 0, err
	}
	if validationErr := clientupdate.ValidatePlatform(platform); validationErr != nil {
		return "", "", "", 0, &updateQueryError{parameter: "platform", message: validationErr.Error()}
	}

	channel, err = singleQueryValue(query, "channel")
	if err != nil {
		return "", "", "", 0, err
	}
	if validationErr := clientupdate.ValidateChannel(channel); validationErr != nil {
		return "", "", "", 0, &updateQueryError{parameter: "channel", message: validationErr.Error()}
	}

	currentVersion, err = singleQueryValue(query, "current_version")
	if err != nil {
		return "", "", "", 0, err
	}
	if validationErr := clientupdate.ValidateVersion(currentVersion); validationErr != nil {
		return "", "", "", 0, &updateQueryError{parameter: "current_version", message: "must be a semantic version without build metadata"}
	}

	rawBuildNumber, err := singleQueryValue(query, "build_number")
	if err != nil {
		return "", "", "", 0, err
	}
	for index := range len(rawBuildNumber) {
		if rawBuildNumber[index] < '0' || rawBuildNumber[index] > '9' {
			return "", "", "", 0, &updateQueryError{parameter: "build_number", message: "must be a positive base-10 integer"}
		}
	}
	if len(rawBuildNumber) > 1 && rawBuildNumber[0] == '0' {
		return "", "", "", 0, &updateQueryError{parameter: "build_number", message: "must be a positive base-10 integer without leading zeroes"}
	}
	buildNumber, parseErr = strconv.ParseInt(rawBuildNumber, 10, 64)
	if parseErr != nil || buildNumber < 1 {
		return "", "", "", 0, &updateQueryError{parameter: "build_number", message: "must be a positive base-10 integer"}
	}
	return platform, channel, currentVersion, buildNumber, nil
}

func singleQueryValue(query url.Values, name string) (string, error) {
	values, exists := query[name]
	if !exists || len(values) == 0 || values[0] == "" {
		return "", &updateQueryError{parameter: name, message: "is required"}
	}
	if len(values) != 1 {
		return "", &updateQueryError{parameter: name, message: "must be supplied exactly once"}
	}
	return values[0], nil
}

func responseForRelease(status string, updateAvailable bool, release clientupdate.Release) clientUpdateCheckResponse {
	return clientUpdateCheckResponse{
		Status:          status,
		UpdateAvailable: updateAvailable,
		Required:        updateAvailable && release.Required,
		Version:         &release.Version,
		BuildNumber:     &release.BuildNumber,
		DownloadURL:     &release.DownloadURL,
		SHA256:          &release.SHA256,
		SizeBytes:       &release.SizeBytes,
		ReleaseNotes:    &release.ReleaseNotes,
		PublishedAt:     &release.PublishedAt,
	}
}
