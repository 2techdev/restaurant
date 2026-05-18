package middleware

import (
	"bufio"
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"runtime/debug"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

// contextKey is a private type for context keys in this package.
type contextKey string

const (
	// ContextKeyRequestID is the context key for the request ID.
	ContextKeyRequestID contextKey = "request_id"
	// ContextKeyTenantID is the context key for the tenant / organization / brand ID from JWT.
	ContextKeyTenantID contextKey = "tenant_id"
	// ContextKeyDeviceID is the context key for the device ID from JWT.
	ContextKeyDeviceID contextKey = "device_id"
	// ContextKeyUserID is the context key for the user ID from JWT.
	ContextKeyUserID contextKey = "user_id"
	// ContextKeyStoreID is the context key for the store scope from JWT.
	ContextKeyStoreID contextKey = "store_id"
	// ContextKeyDeviceType is the context key for the device type from JWT (kds, kiosk, pos).
	ContextKeyDeviceType contextKey = "device_type"
	// ContextKeyRole is the context key for the role from JWT.
	ContextKeyRole contextKey = "role"
	// ContextKeyOrganizationID is the context key for the HQ organization id (014_hq_chain).
	ContextKeyOrganizationID contextKey = "organization_id"
	// ContextKeyOrgRole is the context key for the HQ chain role (HQ_ADMIN, HQ_MANAGER, ...).
	ContextKeyOrgRole contextKey = "org_role"
)

// Middleware is a function that wraps an http.Handler.
type Middleware func(http.Handler) http.Handler

// Chain applies a sequence of middleware to a handler.
// Middleware is applied in order: the first in the list is the outermost wrapper.
func Chain(handler http.Handler, middlewares ...Middleware) http.Handler {
	for i := len(middlewares) - 1; i >= 0; i-- {
		handler = middlewares[i](handler)
	}
	return handler
}

// RequestID adds a unique X-Request-ID header to each request.
func RequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-ID")
		if id == "" {
			b := make([]byte, 8)
			rand.Read(b)
			id = hex.EncodeToString(b)
		}
		w.Header().Set("X-Request-ID", id)
		ctx := context.WithValue(r.Context(), ContextKeyRequestID, id)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// statusWriter wraps http.ResponseWriter to capture the status code.
type statusWriter struct {
	http.ResponseWriter
	status int
	wrote  bool
}

func (sw *statusWriter) WriteHeader(code int) {
	if !sw.wrote {
		sw.status = code
		sw.wrote = true
	}
	sw.ResponseWriter.WriteHeader(code)
}

func (sw *statusWriter) Write(b []byte) (int, error) {
	if !sw.wrote {
		sw.status = http.StatusOK
		sw.wrote = true
	}
	return sw.ResponseWriter.Write(b)
}

// Hijack implements http.Hijacker so WebSocket upgrades work through the Logger middleware.
func (sw *statusWriter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	if hj, ok := sw.ResponseWriter.(http.Hijacker); ok {
		return hj.Hijack()
	}
	return nil, nil, fmt.Errorf("underlying ResponseWriter does not implement http.Hijacker")
}

// RequestRecorder is a callback invoked at the end of every request so a
// metrics package can register a counter/histogram observation without
// causing a middleware → metrics → middleware import cycle.
type RequestRecorder func(method string, status int, duration time.Duration)

// requestRecorder holds the optional observer; nil = no metrics.
var requestRecorder RequestRecorder

// SetRequestRecorder installs the per-request observer. Call once at
// startup before traffic begins.
func SetRequestRecorder(rec RequestRecorder) {
	requestRecorder = rec
}

// Logger logs each request with method, path, status, and duration, and
// fans out to the installed RequestRecorder when present.
func Logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}

		next.ServeHTTP(sw, r)

		dur := time.Since(start)
		slog.Info("http request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", sw.status,
			"duration_ms", dur.Milliseconds(),
			"request_id", r.Context().Value(ContextKeyRequestID),
		)
		if requestRecorder != nil {
			requestRecorder(r.Method, sw.status, dur)
		}
	})
}

// Recover recovers from panics and returns a 500 Internal Server Error.
func Recover(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				slog.Error("panic recovered",
					"error", fmt.Sprintf("%v", err),
					"stack", string(debug.Stack()),
					"request_id", r.Context().Value(ContextKeyRequestID),
				)
				response.Error(w, http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred")
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// allowedOrigins lists the permitted CORS origins for the GastroCore API.
// POS Flutter apps communicate directly (no CORS needed); these cover web dashboards
// and the online ordering widget.
// defaultAllowedOrigins is the fallback origin allow-list used when no CORS
// origins are provided via config (e.g. dev defaults).
var defaultAllowedOrigins = []string{
	"https://pos.2tech.ch",
	"https://www.pos.2tech.ch",
	"https://backoffice.gastrocore.ch",
	"http://localhost:3000",
	"http://localhost:8080",
	"http://localhost:5173",
	"http://192.168.1.134:8080",
	"http://192.168.1.134:8090",
}

// CORSConfig controls CORS behavior for the CORS middleware.
type CORSConfig struct {
	// AllowedOrigins is the list of origins permitted for cross-origin requests.
	// If empty, a conservative built-in dev/prod list is used.
	AllowedOrigins []string
}

// CORS returns a Middleware that adds CORS headers, allowing only the configured
// origins. Unlisted origins are served without Access-Control-Allow-Origin so
// browsers will block cross-origin fetches from unknown sources.
//
// Native app origins (Android WebView, iOS WKWebView, Flutter) are always
// allowed: they don't set an Origin header (or set "null"/"file://") and aren't
// subject to browser CORS enforcement anyway, so echoing back the origin is
// safe and avoids false rejections during preflight.
func CORS(cfg CORSConfig) Middleware {
	origins := cfg.AllowedOrigins
	if len(origins) == 0 {
		origins = defaultAllowedOrigins
	}
	allowed := make(map[string]bool, len(origins))
	for _, o := range origins {
		o = strings.TrimSpace(o)
		if o != "" {
			allowed[o] = true
		}
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")
			switch {
			case origin == "":
				// No Origin — typical of native HTTP clients (Flutter/Android APK).
				// Do not set ACAO; request is served normally (not a browser).
			case allowed[origin]:
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Set("Vary", "Origin")
			case isNativeAppOrigin(origin):
				// Android WebView / iOS WKWebView / file://… — echo back so preflight passes.
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Set("Vary", "Origin")
			}
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Request-ID, X-Device-ID")
			w.Header().Set("Access-Control-Max-Age", "86400")

			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}

// isNativeAppOrigin recognises Origin values sent by mobile WebView / native
// HTTP stacks that don't map to a real browser origin.
func isNativeAppOrigin(origin string) bool {
	if origin == "null" {
		return true
	}
	nativePrefixes := []string{
		"file://",
		"capacitor://",
		"ionic://",
		"http://localhost",
		"https://localhost",
	}
	for _, p := range nativePrefixes {
		if strings.HasPrefix(origin, p) {
			return true
		}
	}
	return false
}

// SecurityHeaders returns a Middleware that sets conservative security response
// headers. When production is true, HSTS is emitted.
func SecurityHeaders(production bool) Middleware {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			h := w.Header()
			h.Set("X-Content-Type-Options", "nosniff")
			h.Set("X-Frame-Options", "DENY")
			h.Set("Referrer-Policy", "strict-origin-when-cross-origin")
			h.Set("Permissions-Policy", "geolocation=(), microphone=(), camera=()")
			if production {
				h.Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
			}
			next.ServeHTTP(w, r)
		})
	}
}

// RequestTimeout caps the request context to the given duration unless the
// path matches a WebSocket / streaming route. The cap is below the HTTP
// server's WriteTimeout so handlers see context.Done before the connection
// is forcibly closed and can return a 504 rather than a generic 500.
//
// WebSocket upgrade paths must not be capped — they run for the lifetime
// of the connection. Excluded paths: /api/v1/*/ws, /api/v1/sync/ws,
// /api/v1/kds/ws, /api/v1/pos/ws, /api/v1/online/ws, /api/v1/manager/realtime.
func RequestTimeout(d time.Duration) Middleware {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if isStreamingPath(r.URL.Path) {
				next.ServeHTTP(w, r)
				return
			}
			ctx, cancel := context.WithTimeout(r.Context(), d)
			defer cancel()
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func isStreamingPath(p string) bool {
	if strings.HasSuffix(p, "/ws") {
		return true
	}
	switch {
	case strings.Contains(p, "/realtime"),
		strings.Contains(p, "/stream"),
		strings.HasPrefix(p, "/api/v1/osd/") && strings.HasSuffix(p, "/realtime"):
		return true
	}
	return false
}

// maxBodyBytes is the default request-body size limit (10 MiB) applied by
// MaxBodySize. Keeps misbehaving or malicious clients from exhausting memory.
const maxBodyBytes = 10 << 20

// MaxBodySize caps request body size to a safe default to prevent abuse.
func MaxBodySize(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Body != nil {
			r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
		}
		next.ServeHTTP(w, r)
	})
}

// AuthRequired validates a JWT Bearer token and extracts claims into context.
// It expects the JWT validation to be handled by the auth module's ValidateToken func.
// For now, it extracts the token and stores the raw value; full validation
// will be wired when the auth module provides a validator function.
func AuthRequired(validateToken func(token string) (claims map[string]string, err error)) Middleware {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Missing Authorization header")
				return
			}

			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
				response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Invalid Authorization header format")
				return
			}

			claims, err := validateToken(parts[1])
			if err != nil {
				response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Invalid or expired token")
				return
			}

			ctx := r.Context()
			if v, ok := claims["tenant_id"]; ok {
				ctx = context.WithValue(ctx, ContextKeyTenantID, v)
			}
			if v, ok := claims["device_id"]; ok {
				ctx = context.WithValue(ctx, ContextKeyDeviceID, v)
			}
			if v, ok := claims["user_id"]; ok {
				ctx = context.WithValue(ctx, ContextKeyUserID, v)
			}
			if v, ok := claims["store_id"]; ok {
				ctx = context.WithValue(ctx, ContextKeyStoreID, v)
			}
			if v, ok := claims["device_type"]; ok {
				ctx = context.WithValue(ctx, ContextKeyDeviceType, v)
			}
			if v, ok := claims["role"]; ok {
				ctx = context.WithValue(ctx, ContextKeyRole, v)
			}
			if v, ok := claims["organization_id"]; ok {
				ctx = context.WithValue(ctx, ContextKeyOrganizationID, v)
			}
			if v, ok := claims["org_role"]; ok {
				ctx = context.WithValue(ctx, ContextKeyOrgRole, v)
				// HQ admins/managers can scope tenant-aware queries to a
				// specific restaurant in their org by sending X-Tenant-ID.
				// Restaurant-scoped users keep the JWT-stamped tenant_id.
				if v == "HQ_ADMIN" || v == "HQ_MANAGER" {
					if tid := r.Header.Get("X-Tenant-ID"); tid != "" {
						ctx = context.WithValue(ctx, ContextKeyTenantID, tid)
					}
				}
			}

			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// TenantRequired ensures that a tenant_id is present in the request context.
// Must be used after AuthRequired.
func TenantRequired(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tenantID := r.Context().Value(ContextKeyTenantID)
		if tenantID == nil || tenantID.(string) == "" {
			response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// GetRequestID extracts the request ID from context.
func GetRequestID(ctx context.Context) string {
	if v, ok := ctx.Value(ContextKeyRequestID).(string); ok {
		return v
	}
	return ""
}

// GetTenantID extracts the tenant ID from context.
func GetTenantID(ctx context.Context) string {
	if v, ok := ctx.Value(ContextKeyTenantID).(string); ok {
		return v
	}
	return ""
}

// GetDeviceID extracts the device ID from context.
func GetDeviceID(ctx context.Context) string {
	if v, ok := ctx.Value(ContextKeyDeviceID).(string); ok {
		return v
	}
	return ""
}

// GetUserID extracts the user ID from context.
func GetUserID(ctx context.Context) string {
	if v, ok := ctx.Value(ContextKeyUserID).(string); ok {
		return v
	}
	return ""
}

// GetRole extracts the role from context.
func GetRole(ctx context.Context) string {
	if v, ok := ctx.Value(ContextKeyRole).(string); ok {
		return v
	}
	return ""
}

// GetOrganizationID extracts the HQ organization id from context.
// Returns "" when the user is not bound to an HQ organization.
func GetOrganizationID(ctx context.Context) string {
	if v, ok := ctx.Value(ContextKeyOrganizationID).(string); ok {
		return v
	}
	return ""
}

// GetOrgRole extracts the HQ chain role from context.
// Returns "" when the user has no HQ role.
func GetOrgRole(ctx context.Context) string {
	if v, ok := ctx.Value(ContextKeyOrgRole).(string); ok {
		return v
	}
	return ""
}

// GetStoreID extracts the store ID from context.
func GetStoreID(ctx context.Context) string {
	if v, ok := ctx.Value(ContextKeyStoreID).(string); ok {
		return v
	}
	return ""
}

// GetDeviceType extracts the device type from context.
func GetDeviceType(ctx context.Context) string {
	if v, ok := ctx.Value(ContextKeyDeviceType).(string); ok {
		return v
	}
	return ""
}

// RoleRequired returns a middleware that checks the caller has one of the allowed roles.
func RoleRequired(allowed ...string) Middleware {
	set := make(map[string]bool, len(allowed))
	for _, r := range allowed {
		set[r] = true
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			role := GetRole(r.Context())
			if !set[role] {
				response.Error(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
