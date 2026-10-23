package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestRateLimiterRefillsAndBoundsMemory(t *testing.T) {
	l := newRequestLimiter()
	now := time.Unix(1700000000, 0)
	if !l.allow("auth:client", 20, 2, now) || !l.allow("auth:client", 20, 2, now) || l.allow("auth:client", 20, 2, now) {
		t.Fatal("burst limit not enforced")
	}
	if !l.allow("auth:client", 20, 2, now.Add(3*time.Second)) {
		t.Fatal("tokens did not refill")
	}
	for i := 0; i < 16384; i++ {
		l.buckets[string(rune(i))+":flood"] = requestBucket{updated: now, seen: now}
	}
	if l.allow("unknown", 20, 2, now) {
		t.Fatal("unbounded limiter state")
	}
	if !l.allow("unknown", 20, 2, now.Add(6*time.Minute)) {
		t.Fatal("expired limiter state not removed")
	}
}

func TestForwardedClientAddressRequiresExplicitTrustedPeer(t *testing.T) {
	s := &Server{}
	WithTrustedProxies([]string{"127.0.0.1/32", "10.1.0.0/16"})(s)
	for _, tc := range []struct{ peer, forwarded, want string }{
		{"198.51.100.1:9000", "203.0.113.9", "198.51.100.1"},
		{"127.0.0.1:9000", "203.0.113.9, 10.1.2.3", "203.0.113.9"},
		{"127.0.0.1:9000", "spoofed, 198.51.100.8", "198.51.100.8"},
		{"127.0.0.1:9000", "invalid", "127.0.0.1"},
	} {
		r := httptest.NewRequest("GET", "http://api.example/v1/me", nil)
		r.RemoteAddr = tc.peer
		r.Header.Set("X-Forwarded-For", tc.forwarded)
		if got := s.requestIP(r); got != tc.want {
			t.Errorf("peer %s forwarded %s => %s, want %s", tc.peer, tc.forwarded, got, tc.want)
		}
	}
}

func TestRateLimitedRequestHasRetryAfterAndRejectsCrossOrigin(t *testing.T) {
	s := &Server{limiter: newRequestLimiter(), allowedOrigins: []string{"https://ui.example"}}
	h := s.cors(s.rateLimit(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) })))
	for i := 0; i < 11; i++ {
		r := httptest.NewRequest("POST", "http://api.example/v1/auth/login", strings.NewReader("{}"))
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if i == 10 && (w.Code != 429 || w.Header().Get("Retry-After") == "") {
			t.Fatalf("limit response = %d %s", w.Code, w.Body)
		}
	}
	r := httptest.NewRequest("POST", "http://api.example/v1/me", nil)
	r.Header.Set("Origin", "https://other.example")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 403 {
		t.Fatalf("unexpected cross-origin status %d", w.Code)
	}
}
