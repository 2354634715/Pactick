package httpapi

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"pactick/server/internal/clientupdate"
)

func TestClientUpdateCheckReturnsConfiguredUpdateWithoutAuthentication(t *testing.T) {
	server := newClientUpdateTestServer(t)
	request := httptest.NewRequest(http.MethodGet, "/v1/client-updates/check?platform=android&channel=stable&current_version=0.1.0&build_number=2", nil)
	response := httptest.NewRecorder()

	server.Handler().ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	var result clientUpdateCheckResponse
	if err := json.Unmarshal(response.Body.Bytes(), &result); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if result.Status != clientUpdateStatusAvailable || !result.UpdateAvailable || !result.Required {
		t.Fatalf("response = %#v", result)
	}
	if result.Version == nil || *result.Version != "0.2.0" || result.BuildNumber == nil || *result.BuildNumber != 3 {
		t.Fatalf("release metadata = %#v", result)
	}
	if result.DownloadURL == nil || *result.DownloadURL != "https://downloads.example.com/pactick.apk" {
		t.Fatalf("download_url = %v", result.DownloadURL)
	}
}

func TestClientUpdateCheckClearsRequiredWhenAlreadyCurrent(t *testing.T) {
	server := newClientUpdateTestServer(t)
	request := httptest.NewRequest(http.MethodGet, "/v1/client-updates/check?platform=android&channel=stable&current_version=0.2.0&build_number=3", nil)
	response := httptest.NewRecorder()

	server.Handler().ServeHTTP(response, request)

	var result clientUpdateCheckResponse
	if err := json.Unmarshal(response.Body.Bytes(), &result); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if response.Code != http.StatusOK || result.Status != clientUpdateStatusCurrent || result.UpdateAvailable || result.Required {
		t.Fatalf("status = %d, response = %#v", response.Code, result)
	}
}

func TestClientUpdateCheckUsesBuildNumberWhenVersionsMatch(t *testing.T) {
	server := newClientUpdateTestServer(t)
	request := httptest.NewRequest(http.MethodGet, "/v1/client-updates/check?platform=android&channel=stable&current_version=0.2.0&build_number=2", nil)
	response := httptest.NewRecorder()

	server.Handler().ServeHTTP(response, request)

	var result clientUpdateCheckResponse
	if err := json.Unmarshal(response.Body.Bytes(), &result); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if response.Code != http.StatusOK || result.Status != clientUpdateStatusAvailable || !result.UpdateAvailable || !result.Required {
		t.Fatalf("status = %d, response = %#v", response.Code, result)
	}
}

func TestClientUpdateCheckMakesMissingConfigurationExplicit(t *testing.T) {
	server := newClientUpdateTestServer(t)
	request := httptest.NewRequest(http.MethodGet, "/v1/client-updates/check?platform=linux&channel=beta&current_version=0.1.0&build_number=2", nil)
	response := httptest.NewRecorder()

	server.Handler().ServeHTTP(response, request)

	var result clientUpdateCheckResponse
	if err := json.Unmarshal(response.Body.Bytes(), &result); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if response.Code != http.StatusOK || result.Status != clientUpdateStatusNotConfigured || result.UpdateAvailable || result.Required {
		t.Fatalf("status = %d, response = %#v", response.Code, result)
	}
	if result.Version != nil || result.BuildNumber != nil || result.DownloadURL != nil || result.SHA256 != nil || result.SizeBytes != nil || result.ReleaseNotes != nil || result.PublishedAt != nil {
		t.Fatalf("unconfigured response leaked release metadata: %#v", result)
	}
}

func TestClientUpdateCheckRejectsInvalidQueries(t *testing.T) {
	server := newClientUpdateTestServer(t)
	tests := map[string]string{
		"missing":          "platform=android&channel=stable&current_version=0.1.0",
		"duplicate":        "platform=android&platform=linux&channel=stable&current_version=0.1.0&build_number=2",
		"unknown":          "platform=android&channel=stable&current_version=0.1.0&build_number=2&download_url=https%3A%2F%2Fevil.example",
		"platform":         "platform=ios&channel=stable&current_version=0.1.0&build_number=2",
		"channel":          "platform=android&channel=nightly&current_version=0.1.0&build_number=2",
		"version":          "platform=android&channel=stable&current_version=1.0&build_number=2",
		"version metadata": "platform=android&channel=stable&current_version=1.0.0%2B2&build_number=2",
		"zero build":       "platform=android&channel=stable&current_version=0.1.0&build_number=0",
		"leading zero":     "platform=android&channel=stable&current_version=0.1.0&build_number=02",
		"signed build":     "platform=android&channel=stable&current_version=0.1.0&build_number=%2B2",
		"malformed":        "platform=android;channel=stable&current_version=0.1.0&build_number=2",
		"too long":         "platform=android&channel=stable&current_version=0.1.0&build_number=2&" + strings.Repeat("x", 512),
	}
	for name, query := range tests {
		t.Run(name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodGet, "/v1/client-updates/check?"+query, nil)
			response := httptest.NewRecorder()
			server.Handler().ServeHTTP(response, request)
			if response.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
			}
			var envelope errorEnvelope
			if err := json.Unmarshal(response.Body.Bytes(), &envelope); err != nil {
				t.Fatalf("decode response: %v", err)
			}
			if envelope.Error.Code != "invalid_client_update_query" {
				t.Fatalf("error code = %q", envelope.Error.Code)
			}
		})
	}
}

func newClientUpdateTestServer(t *testing.T) *Server {
	t.Helper()
	manifest := `{"releases":[{"platform":"android","channel":"stable","version":"0.2.0","build_number":3,"required":true,"download_url":"https://downloads.example.com/pactick.apk","sha256":"` + strings.Repeat("a", 64) + `","size_bytes":123456,"release_notes":"Changes","published_at":"2026-09-19T00:00:00Z"}]}`
	catalog, err := clientupdate.ParseManifest(manifest)
	if err != nil {
		t.Fatalf("ParseManifest() error = %v", err)
	}
	server := &Server{
		logger:        slog.New(slog.NewTextHandler(io.Discard, nil)),
		clientUpdates: catalog,
		mux:           http.NewServeMux(),
	}
	server.routes()
	return server
}
