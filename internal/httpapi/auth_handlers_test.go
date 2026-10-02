package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRegisterReturnsForbiddenWhenRegistrationIsDisabled(t *testing.T) {
	server := &Server{registrationEnabled: false}
	request := httptest.NewRequest(http.MethodPost, "/v1/auth/register", nil)
	response := httptest.NewRecorder()

	server.register(response, request)

	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusForbidden)
	}
	var envelope errorEnvelope
	if err := json.Unmarshal(response.Body.Bytes(), &envelope); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if envelope.Error.Code != "registration_disabled" {
		t.Fatalf("error code = %q", envelope.Error.Code)
	}
}
