package httpapi

import (
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

type requestBucket struct {
	tokens        float64
	updated, seen time.Time
}
type requestLimiter struct {
	mu            sync.Mutex
	buckets       map[string]requestBucket
	nextCleanup   time.Time
	passwordSlots chan struct{}
}

func newRequestLimiter() *requestLimiter {
	return &requestLimiter{buckets: make(map[string]requestBucket), passwordSlots: make(chan struct{}, 4)}
}

func (l *requestLimiter) allow(key string, perMinute, burst float64, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if !now.Before(l.nextCleanup) {
		for key, bucket := range l.buckets {
			if now.Sub(bucket.seen) > 5*time.Minute {
				delete(l.buckets, key)
			}
		}
		l.nextCleanup = now.Add(time.Minute)
	}
	bucket, exists := l.buckets[key]
	if !exists {
		// Bound memory even if many different addresses connect.
		if len(l.buckets) >= 16384 {
			return false
		}
		bucket = requestBucket{tokens: burst, updated: now}
	}
	bucket.tokens = min(burst, bucket.tokens+now.Sub(bucket.updated).Seconds()*perMinute/60)
	bucket.updated, bucket.seen = now, now
	allowed := bucket.tokens >= 1
	if allowed {
		bucket.tokens--
	}
	l.buckets[key] = bucket
	return allowed
}

func (s *Server) trustedProxy(ip net.IP) bool {
	for _, network := range s.trustedProxies {
		if network.Contains(ip) {
			return true
		}
	}
	return false
}

func (s *Server) requestIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	peer := net.ParseIP(host)
	if peer == nil {
		return "unknown"
	}
	if !s.trustedProxy(peer) {
		return peer.String()
	}
	current := peer
	forwarded := strings.Split(r.Header.Get("X-Forwarded-For"), ",")
	for i := len(forwarded) - 1; i >= 0 && s.trustedProxy(current); i-- {
		next := net.ParseIP(strings.TrimSpace(forwarded[i]))
		if next == nil {
			return peer.String()
		}
		current = next
	}
	return current.String()
}

func (s *Server) rateLimit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			next.ServeHTTP(w, r)
			return
		}
		group, rate, burst := "api", float64(600), float64(120)
		if strings.HasPrefix(r.URL.Path, "/v1/auth/") {
			group, rate, burst = "auth", 20, 10
		}
		if r.URL.Path == "/v1/ws" {
			group, rate, burst = "ws", 30, 10
		}
		reject := func() {
			w.Header().Set("Retry-After", strconv.Itoa(3))
			writeError(w, r, http.StatusTooManyRequests, "rate_limited", "too many requests; retry later", nil)
		}
		if !s.limiter.allow(group+":"+s.requestIP(r), rate, burst, time.Now()) {
			reject()
			return
		}
		if r.URL.Path == "/v1/auth/login" || r.URL.Path == "/v1/auth/register" {
			select {
			case s.limiter.passwordSlots <- struct{}{}:
				defer func() { <-s.limiter.passwordSlots }()
			default:
				reject()
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}
