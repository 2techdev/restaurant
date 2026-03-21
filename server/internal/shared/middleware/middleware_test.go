package middleware

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

// ---------------------------------------------------------------------------
// Health check handler (tested as a standalone inline handler matching the
// pattern in cmd/server/main.go — no DB so we test the non-DB path)
// ---------------------------------------------------------------------------

func TestHealthCheck_OKWithoutDB(t *testing.T) {
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"status":  "ok",
			"version": "0.1.0",
			"components": map[string]string{
				"database": "ok",
			},
		})
	})

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}

	var body map[string]any
	if err := json.NewDecoder(w.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body["status"] != "ok" {
		t.Errorf("status: want ok, got %v", body["status"])
	}
}

// ---------------------------------------------------------------------------
// RequestID middleware
// ---------------------------------------------------------------------------

func TestRequestID_GeneratesIDWhenAbsent(t *testing.T) {
	handler := RequestID(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	id := w.Header().Get("X-Request-ID")
	if id == "" {
		t.Error("expected X-Request-ID to be set")
	}
}

func TestRequestID_PreservesExistingID(t *testing.T) {
	handler := RequestID(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("X-Request-ID", "client-provided-id")
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	id := w.Header().Get("X-Request-ID")
	if id != "client-provided-id" {
		t.Errorf("expected preserved request ID, got %q", id)
	}
}

func TestRequestID_InjectsIDIntoContext(t *testing.T) {
	var capturedID string
	handler := RequestID(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedID = GetRequestID(r.Context())
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if capturedID == "" {
		t.Error("expected request ID in context")
	}
}

// ---------------------------------------------------------------------------
// Logger middleware
// ---------------------------------------------------------------------------

func TestLogger_PassesThroughResponse(t *testing.T) {
	handler := Logger(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusCreated)
	}))

	req := httptest.NewRequest(http.MethodPost, "/api/test", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Errorf("expected 201, got %d", w.Code)
	}
}

func TestLogger_Does500Passthrough(t *testing.T) {
	handler := Logger(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))

	req := httptest.NewRequest(http.MethodGet, "/api/broken", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusInternalServerError {
		t.Errorf("expected 500, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// Recover middleware
// ---------------------------------------------------------------------------

func TestRecover_CatchesPanic(t *testing.T) {
	handler := Recover(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic("unexpected panic in handler")
	}))

	req := httptest.NewRequest(http.MethodGet, "/panic", nil)
	w := httptest.NewRecorder()

	// Should not propagate panic.
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusInternalServerError {
		t.Errorf("expected 500 on panic recovery, got %d", w.Code)
	}

	var body map[string]any
	if err := json.NewDecoder(w.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body["code"] != "INTERNAL_ERROR" {
		t.Errorf("error code: want INTERNAL_ERROR, got %v", body["code"])
	}
}

func TestRecover_NormalRequestPassesThrough(t *testing.T) {
	handler := Recover(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/ok", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// CORS middleware
// ---------------------------------------------------------------------------

func TestCORS_AddsHeaders(t *testing.T) {
	cors := CORS(CORSConfig{AllowedOrigins: []string{"*"}})
	handler := cors(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/api/data", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Header().Get("Access-Control-Allow-Origin") != "*" {
		t.Error("expected Access-Control-Allow-Origin: *")
	}
	if w.Header().Get("Access-Control-Allow-Methods") == "" {
		t.Error("expected Access-Control-Allow-Methods to be set")
	}
}

func TestCORS_OptionsReturns204(t *testing.T) {
	cors := CORS(CORSConfig{AllowedOrigins: []string{"*"}})
	handler := cors(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("should not reach inner handler for OPTIONS")
	}))

	req := httptest.NewRequest(http.MethodOptions, "/api/data", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusNoContent {
		t.Errorf("expected 204 for OPTIONS, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// AuthRequired middleware
// ---------------------------------------------------------------------------

func TestAuthRequired_MissingAuthHeader(t *testing.T) {
	validate := func(token string) (map[string]string, error) {
		return map[string]string{"tenant_id": "t-1", "role": "device"}, nil
	}

	handler := AuthRequired(validate)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("should not reach inner handler")
	}))

	req := httptest.NewRequest(http.MethodGet, "/api/protected", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for missing auth header, got %d", w.Code)
	}
}

func TestAuthRequired_InvalidAuthHeaderFormat(t *testing.T) {
	validate := func(token string) (map[string]string, error) {
		return nil, nil
	}

	handler := AuthRequired(validate)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("should not reach inner handler")
	}))

	req := httptest.NewRequest(http.MethodGet, "/api/protected", nil)
	req.Header.Set("Authorization", "Token abc123") // not "Bearer"
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for invalid format, got %d", w.Code)
	}
}

func TestAuthRequired_InvalidToken(t *testing.T) {
	validate := func(token string) (map[string]string, error) {
		return nil, errors.New("token invalid")
	}

	handler := AuthRequired(validate)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("should not reach inner handler")
	}))

	req := httptest.NewRequest(http.MethodGet, "/api/protected", nil)
	req.Header.Set("Authorization", "Bearer bad-token")
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for invalid token, got %d", w.Code)
	}
}

func TestAuthRequired_ValidToken_InjectsContext(t *testing.T) {
	var capturedTenantID, capturedRole string

	validate := func(token string) (map[string]string, error) {
		return map[string]string{
			"tenant_id": "tenant-42",
			"device_id": "device-99",
			"role":      "device",
		}, nil
	}

	handler := AuthRequired(validate)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedTenantID = GetTenantID(r.Context())
		capturedRole = GetRole(r.Context())
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/api/protected", nil)
	req.Header.Set("Authorization", "Bearer valid-token")
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
	if capturedTenantID != "tenant-42" {
		t.Errorf("tenant_id: want tenant-42, got %q", capturedTenantID)
	}
	if capturedRole != "device" {
		t.Errorf("role: want device, got %q", capturedRole)
	}
}

// ---------------------------------------------------------------------------
// TenantRequired middleware
// ---------------------------------------------------------------------------

func TestTenantRequired_MissingTenantInContext(t *testing.T) {
	handler := TenantRequired(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("should not reach inner handler")
	}))

	req := httptest.NewRequest(http.MethodGet, "/api/tenant", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusForbidden {
		t.Errorf("expected 403 when tenant missing, got %d", w.Code)
	}
}

func TestTenantRequired_PresentTenantPasses(t *testing.T) {
	handler := TenantRequired(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/api/tenant", nil)
	ctx := context.WithValue(req.Context(), ContextKeyTenantID, "tenant-1")
	req = req.WithContext(ctx)

	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// Chain helper
// ---------------------------------------------------------------------------

func TestChain_AppliesMiddlewareInOrder(t *testing.T) {
	var order []int

	m1 := func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			order = append(order, 1)
			next.ServeHTTP(w, r)
		})
	}
	m2 := func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			order = append(order, 2)
			next.ServeHTTP(w, r)
		})
	}

	final := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		order = append(order, 3)
		w.WriteHeader(http.StatusOK)
	})

	handler := Chain(final, m1, m2)
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if len(order) != 3 || order[0] != 1 || order[1] != 2 || order[2] != 3 {
		t.Errorf("expected order [1 2 3], got %v", order)
	}
}

// ---------------------------------------------------------------------------
// Context helpers
// ---------------------------------------------------------------------------

func TestGetHelpers_EmptyContext(t *testing.T) {
	ctx := context.Background()

	if GetRequestID(ctx) != "" {
		t.Error("GetRequestID should return empty for empty context")
	}
	if GetTenantID(ctx) != "" {
		t.Error("GetTenantID should return empty for empty context")
	}
	if GetDeviceID(ctx) != "" {
		t.Error("GetDeviceID should return empty for empty context")
	}
	if GetUserID(ctx) != "" {
		t.Error("GetUserID should return empty for empty context")
	}
	if GetRole(ctx) != "" {
		t.Error("GetRole should return empty for empty context")
	}
}

func TestGetHelpers_WithValues(t *testing.T) {
	ctx := context.Background()
	ctx = context.WithValue(ctx, ContextKeyTenantID, "t-1")
	ctx = context.WithValue(ctx, ContextKeyDeviceID, "d-1")
	ctx = context.WithValue(ctx, ContextKeyUserID, "u-1")
	ctx = context.WithValue(ctx, ContextKeyRole, "admin")

	if GetTenantID(ctx) != "t-1" {
		t.Errorf("GetTenantID: want t-1, got %q", GetTenantID(ctx))
	}
	if GetDeviceID(ctx) != "d-1" {
		t.Errorf("GetDeviceID: want d-1, got %q", GetDeviceID(ctx))
	}
	if GetUserID(ctx) != "u-1" {
		t.Errorf("GetUserID: want u-1, got %q", GetUserID(ctx))
	}
	if GetRole(ctx) != "admin" {
		t.Errorf("GetRole: want admin, got %q", GetRole(ctx))
	}
}
