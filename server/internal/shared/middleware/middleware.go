package middleware

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log/slog"
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

// Logger logs each request with method, path, status, and duration.
func Logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}

		next.ServeHTTP(sw, r)

		slog.Info("http request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", sw.status,
			"duration_ms", time.Since(start).Milliseconds(),
			"request_id", r.Context().Value(ContextKeyRequestID),
		)
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
var allowedOrigins = map[string]bool{
	"https://pos.2tech.ch":        true,
	"https://www.pos.2tech.ch":    true,
	"http://localhost:3000":        true,
	"http://localhost:8080":        true,
	"http://localhost:5173":        true,
	"http://192.168.1.134:8080":   true,
	"http://192.168.1.134:8090":   true,
}

// CORS adds CORS headers, allowing only known origins.
// Requests from unlisted origins are served without Access-Control-Allow-Origin,
// so browsers will block cross-origin fetches from unknown sources.
func CORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && allowedOrigins[origin] {
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
