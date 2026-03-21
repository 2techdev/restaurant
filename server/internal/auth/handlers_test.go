package auth

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gastrocore/server/internal/shared/config"
)

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

func testConfig() *config.Config {
	return &config.Config{
		JWTSecret: "test-secret-key-for-unit-tests-only",
		JWTExpiry: 24 * time.Hour,
	}
}

// newTestAuthModule creates a Module with a real JWTService but no DB (nil).
// Tests that require DB access must supply a *sql.DB directly.
func newTestAuthModule(db *sql.DB) *Module {
	cfg := testConfig()
	return &Module{
		db:  db,
		cfg: cfg,
		jwt: NewJWTService(cfg.JWTSecret, cfg.JWTExpiry),
	}
}

// postJSON is a convenience helper for POST requests with JSON body.
func postJSON(t *testing.T, path string, body any, handler func(http.ResponseWriter, *http.Request)) *httptest.ResponseRecorder {
	t.Helper()
	b, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	handler(w, req)
	return w
}

// assertErrorCode checks that the JSON response body contains the expected error code.
func assertErrorCode(t *testing.T, w *httptest.ResponseRecorder, code string) {
	t.Helper()
	var body map[string]any
	if err := json.NewDecoder(w.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body["code"] != code {
		t.Errorf("expected error code %q, got %v", code, body["code"])
	}
}

// ---------------------------------------------------------------------------
// JWTService tests
// ---------------------------------------------------------------------------

func TestJWT_GenerateAndValidate(t *testing.T) {
	svc := NewJWTService("my-secret", 24*time.Hour)

	claims := Claims{
		TenantID: "tenant-1",
		DeviceID: "device-1",
		Role:     "device",
	}

	token, err := svc.GenerateToken(claims)
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}
	if token == "" {
		t.Fatal("expected non-empty token")
	}

	parsed, err := svc.ValidateToken(token)
	if err != nil {
		t.Fatalf("ValidateToken: %v", err)
	}

	if parsed["tenant_id"] != "tenant-1" {
		t.Errorf("tenant_id: want %q, got %q", "tenant-1", parsed["tenant_id"])
	}
	if parsed["device_id"] != "device-1" {
		t.Errorf("device_id: want %q, got %q", "device-1", parsed["device_id"])
	}
	if parsed["role"] != "device" {
		t.Errorf("role: want %q, got %q", "device", parsed["role"])
	}
}

func TestJWT_ExpiredTokenIsRejected(t *testing.T) {
	// Use a negative expiry to produce an already-expired token.
	svc := NewJWTService("my-secret", -1*time.Second)
	token, err := svc.GenerateToken(Claims{TenantID: "t", Role: "device"})
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}

	_, err = svc.ValidateToken(token)
	if err == nil {
		t.Error("expected error for expired token, got nil")
	}
}

func TestJWT_TamperedSignatureIsRejected(t *testing.T) {
	svc := NewJWTService("my-secret", 24*time.Hour)

	token, _ := svc.GenerateToken(Claims{TenantID: "t", Role: "device"})
	// Flip one character in the signature (last segment).

	last := token[len(token)-1]
	var tampered string
	if last == 'A' {
		tampered = token[:len(token)-1] + "B"
	} else {
		tampered = token[:len(token)-1] + "A"
	}

	_, err := svc.ValidateToken(tampered)
	if err == nil {
		t.Error("expected error for tampered token, got nil")
	}
}

func TestJWT_InvalidFormat(t *testing.T) {
	svc := NewJWTService("my-secret", 24*time.Hour)

	cases := []string{
		"not.a.token.at.all",
		"only.two",
		"",
		"just-one-segment",
	}
	for _, tc := range cases {
		_, err := svc.ValidateToken(tc)
		if err == nil {
			t.Errorf("expected error for invalid token %q, got nil", tc)
		}
	}
}

func TestJWT_DifferentSecretIsRejected(t *testing.T) {
	svc1 := NewJWTService("secret-A", 24*time.Hour)
	svc2 := NewJWTService("secret-B", 24*time.Hour)

	token, _ := svc1.GenerateToken(Claims{TenantID: "t", Role: "admin"})
	_, err := svc2.ValidateToken(token)
	if err == nil {
		t.Error("token signed with different secret should be rejected")
	}
}

func TestJWT_UserIDToken(t *testing.T) {
	svc := NewJWTService("secret", 1*time.Hour)

	token, err := svc.GenerateToken(Claims{
		TenantID: "org-1",
		UserID:   "user-42",
		Role:     "admin",
	})
	if err != nil {
		t.Fatal(err)
	}

	claims, err := svc.ValidateToken(token)
	if err != nil {
		t.Fatal(err)
	}
	if claims["user_id"] != "user-42" {
		t.Errorf("user_id: want user-42, got %q", claims["user_id"])
	}
}

func TestJWT_RefreshRoleStripping(t *testing.T) {
	// Simulate the token refresh flow: generate a refresh token,
	// then verify the _refresh suffix logic works.
	cfg := testConfig()
	refreshJWT := NewJWTService(cfg.JWTSecret, 30*24*time.Hour)

	refreshToken, err := refreshJWT.GenerateToken(Claims{
		TenantID: "tenant-1",
		DeviceID: "dev-1",
		Role:     "device_refresh",
	})
	if err != nil {
		t.Fatal(err)
	}

	claims, err := refreshJWT.ValidateToken(refreshToken)
	if err != nil {
		t.Fatal(err)
	}

	role := claims["role"]
	const suffix = "_refresh"
	if len(role) > len(suffix) && role[len(role)-len(suffix):] == suffix {
		role = role[:len(role)-len(suffix)]
	}

	if role != "device" {
		t.Errorf("expected stripped role %q, got %q", "device", role)
	}
}

// ---------------------------------------------------------------------------
// handleDeviceRegister tests
// ---------------------------------------------------------------------------

func TestHandleDeviceRegister_MissingTenantID(t *testing.T) {
	mod := newTestAuthModule(nil)
	w := postJSON(t, "/api/v1/auth/device/register",
		map[string]string{"device_name": "Main POS", "license_key": "lic-123"},
		mod.handleDeviceRegister,
	)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for missing tenant_id, got %d", w.Code)
	}
	assertErrorCode(t, w, "VALIDATION_ERROR")
}

func TestHandleDeviceRegister_MissingDeviceName(t *testing.T) {
	mod := newTestAuthModule(nil)
	w := postJSON(t, "/api/v1/auth/device/register",
		map[string]string{"tenant_id": "t-1", "license_key": "lic-123"},
		mod.handleDeviceRegister,
	)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for missing device_name, got %d", w.Code)
	}
}

func TestHandleDeviceRegister_MissingLicenseKey(t *testing.T) {
	mod := newTestAuthModule(nil)
	w := postJSON(t, "/api/v1/auth/device/register",
		map[string]string{"tenant_id": "t-1", "device_name": "POS-1"},
		mod.handleDeviceRegister,
	)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestHandleDeviceRegister_InvalidBody(t *testing.T) {
	mod := newTestAuthModule(nil)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/device/register",
		bytes.NewReader([]byte("not json {{{")))
	w := httptest.NewRecorder()
	mod.handleDeviceRegister(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for invalid JSON, got %d", w.Code)
	}
	assertErrorCode(t, w, "INVALID_BODY")
}

// ---------------------------------------------------------------------------
// handleDeviceToken tests
// ---------------------------------------------------------------------------

func TestHandleDeviceToken_MissingDeviceID(t *testing.T) {
	mod := newTestAuthModule(nil)
	w := postJSON(t, "/api/v1/auth/device/token",
		map[string]string{"device_token": "some-token"},
		mod.handleDeviceToken,
	)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
	assertErrorCode(t, w, "VALIDATION_ERROR")
}

func TestHandleDeviceToken_MissingDeviceToken(t *testing.T) {
	mod := newTestAuthModule(nil)
	w := postJSON(t, "/api/v1/auth/device/token",
		map[string]string{"device_id": "dev-1"},
		mod.handleDeviceToken,
	)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestHandleDeviceToken_InvalidBody(t *testing.T) {
	mod := newTestAuthModule(nil)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/device/token",
		bytes.NewReader([]byte(`{bad json`)),
	)
	w := httptest.NewRecorder()
	mod.handleDeviceToken(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// handleAdminLogin tests
// ---------------------------------------------------------------------------

func TestHandleAdminLogin_MissingEmail(t *testing.T) {
	mod := newTestAuthModule(nil)
	w := postJSON(t, "/api/v1/auth/admin/login",
		map[string]string{"password": "secret"},
		mod.handleAdminLogin,
	)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for missing email, got %d", w.Code)
	}
	assertErrorCode(t, w, "VALIDATION_ERROR")
}

func TestHandleAdminLogin_MissingPassword(t *testing.T) {
	mod := newTestAuthModule(nil)
	w := postJSON(t, "/api/v1/auth/admin/login",
		map[string]string{"email": "admin@example.com"},
		mod.handleAdminLogin,
	)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestHandleAdminLogin_InvalidBody(t *testing.T) {
	mod := newTestAuthModule(nil)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/admin/login",
		bytes.NewReader([]byte(`not-json`)),
	)
	w := httptest.NewRecorder()
	mod.handleAdminLogin(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
	assertErrorCode(t, w, "INVALID_BODY")
}

// ---------------------------------------------------------------------------
// handleTokenRefresh tests
// ---------------------------------------------------------------------------

func TestHandleTokenRefresh_MissingToken(t *testing.T) {
	mod := newTestAuthModule(nil)
	w := postJSON(t, "/api/v1/auth/token/refresh",
		map[string]string{},
		mod.handleTokenRefresh,
	)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for missing refresh_token, got %d", w.Code)
	}
	assertErrorCode(t, w, "VALIDATION_ERROR")
}

func TestHandleTokenRefresh_InvalidToken(t *testing.T) {
	mod := newTestAuthModule(nil)
	w := postJSON(t, "/api/v1/auth/token/refresh",
		map[string]string{"refresh_token": "this.is.garbage"},
		mod.handleTokenRefresh,
	)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for invalid refresh token, got %d", w.Code)
	}
	assertErrorCode(t, w, "INVALID_TOKEN")
}

func TestHandleTokenRefresh_ExpiredToken(t *testing.T) {
	cfg := testConfig()
	mod := &Module{cfg: cfg, jwt: NewJWTService(cfg.JWTSecret, cfg.JWTExpiry)}

	// Generate an expired refresh token.
	expiredJWT := NewJWTService(cfg.JWTSecret, -1*time.Second)
	expiredToken, _ := expiredJWT.GenerateToken(Claims{
		TenantID: "t-1",
		DeviceID: "dev-1",
		Role:     "device_refresh",
	})

	w := postJSON(t, "/api/v1/auth/token/refresh",
		map[string]string{"refresh_token": expiredToken},
		mod.handleTokenRefresh,
	)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for expired refresh token, got %d", w.Code)
	}
}

func TestHandleTokenRefresh_ValidDeviceRefreshToken(t *testing.T) {
	cfg := testConfig()
	mod := &Module{cfg: cfg, jwt: NewJWTService(cfg.JWTSecret, cfg.JWTExpiry)}

	refreshJWT := NewJWTService(cfg.JWTSecret, 30*24*time.Hour)
	refreshToken, err := refreshJWT.GenerateToken(Claims{
		TenantID: "tenant-99",
		DeviceID: "device-99",
		Role:     "device_refresh",
	})
	if err != nil {
		t.Fatal(err)
	}

	w := postJSON(t, "/api/v1/auth/token/refresh",
		map[string]string{"refresh_token": refreshToken},
		mod.handleTokenRefresh,
	)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp tokenResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatal(err)
	}
	if resp.AccessToken == "" {
		t.Error("expected non-empty access_token")
	}
	if resp.RefreshToken == "" {
		t.Error("expected non-empty refresh_token")
	}
	if resp.TokenType != "Bearer" {
		t.Errorf("expected token_type=Bearer, got %q", resp.TokenType)
	}
}

func TestHandleTokenRefresh_ValidAdminRefreshToken(t *testing.T) {
	cfg := testConfig()
	mod := &Module{cfg: cfg, jwt: NewJWTService(cfg.JWTSecret, cfg.JWTExpiry)}

	refreshJWT := NewJWTService(cfg.JWTSecret, 7*24*time.Hour)
	refreshToken, _ := refreshJWT.GenerateToken(Claims{
		TenantID: "org-1",
		UserID:   "user-1",
		Role:     "admin_refresh",
	})

	w := postJSON(t, "/api/v1/auth/token/refresh",
		map[string]string{"refresh_token": refreshToken},
		mod.handleTokenRefresh,
	)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	// Verify the new access token contains the correct (stripped) role.
	var resp tokenResponse
	json.NewDecoder(w.Body).Decode(&resp)

	newSvc := NewJWTService(cfg.JWTSecret, cfg.JWTExpiry)
	claims, err := newSvc.ValidateToken(resp.AccessToken)
	if err != nil {
		t.Fatalf("access token should be valid: %v", err)
	}
	if claims["role"] != "admin" {
		t.Errorf("expected role=admin in new access token, got %q", claims["role"])
	}
}

func TestHandleTokenRefresh_InvalidBody(t *testing.T) {
	mod := newTestAuthModule(nil)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/token/refresh",
		bytes.NewReader([]byte(`{bad`)))
	w := httptest.NewRecorder()
	mod.handleTokenRefresh(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}
