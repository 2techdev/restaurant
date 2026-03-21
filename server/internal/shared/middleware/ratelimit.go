package middleware

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

// ---------------------------------------------------------------------------
// Sliding-window per-IP rate limiter
// ---------------------------------------------------------------------------

type ipWindow struct {
	requests []time.Time
}

type rateLimiter struct {
	mu      sync.Mutex
	windows map[string]*ipWindow
	rate    int           // max requests allowed
	window  time.Duration // per this window
}

func newRateLimiter(rate int, window time.Duration) *rateLimiter {
	rl := &rateLimiter{
		windows: make(map[string]*ipWindow),
		rate:    rate,
		window:  window,
	}
	go rl.sweepLoop()
	return rl
}

// allow returns true if the request from ip should be permitted.
func (rl *rateLimiter) allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	cutoff := now.Add(-rl.window)

	w, ok := rl.windows[ip]
	if !ok {
		w = &ipWindow{}
		rl.windows[ip] = w
	}

	// Evict expired timestamps.
	valid := w.requests[:0]
	for _, t := range w.requests {
		if t.After(cutoff) {
			valid = append(valid, t)
		}
	}
	w.requests = valid

	if len(w.requests) >= rl.rate {
		return false
	}
	w.requests = append(w.requests, now)
	return true
}

// sweepLoop removes idle IP entries periodically to bound memory growth.
func (rl *rateLimiter) sweepLoop() {
	ticker := time.NewTicker(rl.window * 2)
	defer ticker.Stop()
	for range ticker.C {
		rl.mu.Lock()
		cutoff := time.Now().Add(-rl.window)
		for ip, w := range rl.windows {
			valid := w.requests[:0]
			for _, t := range w.requests {
				if t.After(cutoff) {
					valid = append(valid, t)
				}
			}
			if len(valid) == 0 {
				delete(rl.windows, ip)
			} else {
				w.requests = valid
			}
		}
		rl.mu.Unlock()
	}
}

// RateLimit returns a middleware that limits each client IP to at most
// rate requests per window.  Excess requests receive 429 Too Many Requests.
func RateLimit(rate int, window time.Duration) Middleware {
	rl := newRateLimiter(rate, window)
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip := clientIP(r)
			if !rl.allow(ip) {
				w.Header().Set("Retry-After", "60")
				response.Error(w, http.StatusTooManyRequests, "RATE_LIMITED", "Too many requests, please slow down")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// clientIP extracts the real client IP from common proxy headers.
func clientIP(r *http.Request) string {
	if ip := r.Header.Get("X-Real-IP"); ip != "" {
		return strings.TrimSpace(ip)
	}
	if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
		// Take the leftmost (original client) address.
		if i := strings.Index(forwarded, ","); i >= 0 {
			return strings.TrimSpace(forwarded[:i])
		}
		return strings.TrimSpace(forwarded)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
