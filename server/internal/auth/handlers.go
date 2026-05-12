package auth

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/crypto"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
	"github.com/lib/pq"
)

// --- Request / Response types ---

type deviceRegisterRequest struct {
	TenantID   string `json:"tenant_id"`
	DeviceName string `json:"device_name"`
	DeviceType string `json:"device_type"` // pos, kds, kiosk, waiter
	LicenseKey string `json:"license_key"`
}

type deviceRegisterResponse struct {
	DeviceID    string `json:"device_id"`
	DeviceToken string `json:"device_token"`
}

type deviceTokenRequest struct {
	DeviceID    string `json:"device_id"`
	DeviceToken string `json:"device_token"`
}

type tokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"` // seconds
	TokenType    string `json:"token_type"`
}

type adminLoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type refreshTokenRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// handleDeviceRegister registers a new POS device and returns a device token.
// POST /api/v1/auth/device/register
func (m *Module) handleDeviceRegister(w http.ResponseWriter, r *http.Request) {
	var req deviceRegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.TenantID == "" || req.DeviceName == "" || req.LicenseKey == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "tenant_id, device_name, and license_key are required")
		return
	}

	// Verify that the tenant exists.
	var exists bool
	err := m.db.QueryRowContext(r.Context(),
		`SELECT EXISTS(SELECT 1 FROM tenants WHERE id=$1 AND is_deleted=false)`,
		req.TenantID,
	).Scan(&exists)
	if err != nil || !exists {
		response.Error(w, http.StatusBadRequest, "TENANT_NOT_FOUND", "Tenant not found")
		return
	}

	deviceID := uuid.New()
	// Generate a secure device token (32 random bytes → UUID-like hex string).
	deviceToken := uuid.New() + uuid.New() // 64-char token

	if req.DeviceType == "" {
		req.DeviceType = "pos"
	}

	_, err = m.db.ExecContext(r.Context(), `
		INSERT INTO devices (
			id, tenant_id, device_name, device_type, device_token,
			status, capabilities, created_at, updated_at, is_deleted
		) VALUES ($1, $2, $3, $4, $5, 'active', '{}', NOW(), NOW(), false)
		ON CONFLICT (id) DO NOTHING
	`, deviceID, req.TenantID, req.DeviceName, req.DeviceType, deviceToken)
	if err != nil {
		slog.Error("auth: register device", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to register device")
		return
	}

	slog.Info("device registered", "device_id", deviceID, "tenant", req.TenantID, "type", req.DeviceType)
	response.JSON(w, http.StatusCreated, deviceRegisterResponse{
		DeviceID:    deviceID,
		DeviceToken: deviceToken,
	})
}

// handleDeviceToken exchanges a device token for a JWT access token.
// POST /api/v1/auth/device/token
func (m *Module) handleDeviceToken(w http.ResponseWriter, r *http.Request) {
	var req deviceTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.DeviceID == "" || req.DeviceToken == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "device_id and device_token are required")
		return
	}

	var tenantID, deviceType string
	var status string
	err := m.db.QueryRowContext(r.Context(), `
		SELECT tenant_id, device_type, status
		FROM devices
		WHERE id=$1 AND device_token=$2 AND is_deleted=false
	`, req.DeviceID, req.DeviceToken).Scan(&tenantID, &deviceType, &status)

	if err == sql.ErrNoRows {
		response.Error(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Invalid device credentials")
		return
	}
	if err != nil {
		slog.Error("auth: device token lookup", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to verify device")
		return
	}
	if status != "active" {
		response.Error(w, http.StatusForbidden, "DEVICE_INACTIVE", "Device is not active")
		return
	}

	token, err := m.jwt.GenerateToken(Claims{
		TenantID: tenantID,
		DeviceID: req.DeviceID,
		Role:     "device",
	})
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "TOKEN_ERROR", "Failed to generate token")
		return
	}

	// Generate a refresh token (simple, long-lived JWT).
	refreshExpiry := 30 * 24 * time.Hour
	jwtRefresh := NewJWTService(m.cfg.JWTSecret, refreshExpiry)
	refreshToken, _ := jwtRefresh.GenerateToken(Claims{
		TenantID: tenantID,
		DeviceID: req.DeviceID,
		Role:     "device_refresh",
	})

	response.JSON(w, http.StatusOK, tokenResponse{
		AccessToken:  token,
		RefreshToken: refreshToken,
		ExpiresIn:    int(m.cfg.JWTExpiry.Seconds()),
		TokenType:    "Bearer",
	})
}

// adminLoginResponse extends tokenResponse with user profile information.
type adminLoginResponse struct {
	AccessToken  string        `json:"access_token"`
	RefreshToken string        `json:"refresh_token"`
	ExpiresIn    int           `json:"expires_in"`
	TokenType    string        `json:"token_type"`
	User         adminUserInfo `json:"user"`
}

type adminUserInfo struct {
	ID             string   `json:"id"`
	OrganizationID string   `json:"organization_id"`
	Email          string   `json:"email"`
	Name           string   `json:"name"`
	Role           string   `json:"role"`
	OrgRole        string   `json:"org_role,omitempty"` // HQ chain role — derived from admin_users.role
	StoreIDs       []string `json:"store_ids,omitempty"`
	IsSuperAdmin   bool     `json:"is_super_admin,omitempty"` // F1 — Wallee-style ghost login (migration 024)
}

// mapAdminRoleToOrgRole maps the legacy admin_users.role values onto the HQ
// chain role taxonomy used by /api/v1/org/* endpoints. The mapping is the
// minimum-privilege one: only "admin" maps to HQ_ADMIN. Returning "" means
// the user has no HQ access (single-restaurant operator).
//
// Mapping rationale:
//   admin            → HQ_ADMIN              (full org control + destructive ops)
//   brand_manager    → HQ_MANAGER            (org control without destructive ops)
//   store_manager    → RESTAURANT_MANAGER    (single-tenant manager)
//   viewer           → ""                    (read-only, no HQ surface)
func mapAdminRoleToOrgRole(adminRole string) string {
	switch adminRole {
	case "admin":
		return "HQ_ADMIN"
	case "brand_manager":
		return "HQ_MANAGER"
	case "store_manager":
		return "RESTAURANT_MANAGER"
	default:
		return ""
	}
}

// backofficeAllowedRoles is the set of admin_users.role values that may sign
// into the backoffice via /api/v1/auth/admin/login. A row whose role is not
// in this set (e.g. a stray "waiter") will be rejected with 403 even if its
// password verifies — defence in depth against accidental table contamination.
var backofficeAllowedRoles = map[string]bool{
	"admin":         true,
	"brand_manager": true,
	"store_manager": true,
	"viewer":        true,
}

// posAllowedRoles is the set of app_users.role values that may sign into the
// POS app via /api/v1/auth/login. HQ-tier roles (super_admin, org_admin,
// owner, brand_manager, store_manager) are intentionally excluded — those
// accounts belong in admin_users and should not POS-login even if they leak
// into app_users.
var posAllowedRoles = map[string]bool{
	"manager": true,
	"cashier": true,
	"waiter":  true,
	"kitchen": true,
	"kds":     true,
	"kiosk":   true,
}

// handleAdminLogin authenticates a web dashboard admin by email and password.
// POST /api/v1/auth/admin/login
func (m *Module) handleAdminLogin(w http.ResponseWriter, r *http.Request) {
	var req adminLoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.Email == "" || req.Password == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "email and password are required")
		return
	}

	var (
		userID       string
		orgID        string
		name         string
		role         string
		status       string
		passwordHash string
		storeIDs     pq.StringArray
		isSuperAdmin bool
	)

	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, organization_id, name, role, status, password_hash,
		       COALESCE(store_ids, '{}'),
		       COALESCE(is_super_admin, FALSE)
		FROM admin_users
		WHERE email = $1
	`, req.Email).Scan(&userID, &orgID, &name, &role, &status, &passwordHash, &storeIDs, &isSuperAdmin)

	if err == sql.ErrNoRows {
		// Constant-time dummy verify so admin_users misses don't time-leak.
		crypto.VerifyPassword(req.Password, "pbkdf2$sha256$100000$AAAA$BBBB")
		// Cross-table hint: if this email actually exists in app_users we tell
		// the operator they're at the wrong portal — UX gain worth the small
		// enumeration trade-off for this pilot.
		var appExists bool
		_ = m.db.QueryRowContext(r.Context(),
			`SELECT EXISTS(SELECT 1 FROM app_users WHERE email=$1 AND is_active=TRUE)`,
			req.Email).Scan(&appExists)
		if appExists {
			response.Error(w, http.StatusForbidden, "WRONG_PORTAL",
				"Bu hesap POS personeline ait. POS uygulamasından giriş yapın.")
			return
		}
		response.Error(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Invalid email or password")
		return
	}
	if err != nil {
		slog.Error("auth: admin login DB", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Login failed")
		return
	}

	if !crypto.VerifyPassword(req.Password, passwordHash) {
		response.Error(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Invalid email or password")
		return
	}
	if status != "active" {
		response.Error(w, http.StatusForbidden, "ACCOUNT_INACTIVE", "Account is suspended or inactive")
		return
	}
	if !backofficeAllowedRoles[role] {
		response.Error(w, http.StatusForbidden, "WRONG_PORTAL",
			"Bu hesap backoffice girişi için uygun değil. POS personeli POS uygulamasına giriş yapmalı.")
		return
	}

	// Update last_login_at.
	_, _ = m.db.ExecContext(r.Context(), `
		UPDATE admin_users SET last_login_at=NOW() WHERE id=$1
	`, userID)

	orgRole := mapAdminRoleToOrgRole(role)

	// Tenant scoping: HQ-tier accounts (HQ_ADMIN / HQ_MANAGER / super admin)
	// keep the org as their default tenant context and may switch to any
	// tenant in their org via X-Tenant-ID. RESTAURANT_MANAGER (and other
	// single-restaurant roles) are pinned to their first assigned store_id
	// so downstream queries cannot accidentally pierce into sibling tenants.
	claimTenantID := orgID
	if orgRole == "RESTAURANT_MANAGER" && len(storeIDs) > 0 {
		claimTenantID = storeIDs[0]
	}

	token, err := m.jwt.GenerateToken(Claims{
		TenantID:       claimTenantID,
		UserID:         userID,
		Role:           role,
		OrganizationID: orgID,
		OrgRole:        orgRole,
		IsSuperAdmin:   isSuperAdmin,
	})
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "TOKEN_ERROR", "Failed to generate token")
		return
	}

	refreshExpiry := 7 * 24 * time.Hour
	jwtRefresh := NewJWTService(m.cfg.JWTSecret, refreshExpiry)
	refreshToken, _ := jwtRefresh.GenerateToken(Claims{
		TenantID:       claimTenantID,
		UserID:         userID,
		Role:           role + "_refresh",
		OrganizationID: orgID,
		OrgRole:        orgRole,
		IsSuperAdmin:   isSuperAdmin,
	})

	ids := []string(storeIDs)
	if ids == nil {
		ids = []string{}
	}

	response.JSON(w, http.StatusOK, adminLoginResponse{
		AccessToken:  token,
		RefreshToken: refreshToken,
		ExpiresIn:    int(m.cfg.JWTExpiry.Seconds()),
		TokenType:    "Bearer",
		User: adminUserInfo{
			ID:             userID,
			OrganizationID: orgID,
			Email:          req.Email,
			Name:           name,
			Role:           role,
			OrgRole:        orgRole,
			StoreIDs:       ids,
			IsSuperAdmin:   isSuperAdmin,
		},
	})
}

// handleTokenRefresh validates a refresh token and issues a new access token.
// POST /api/v1/auth/token/refresh
func (m *Module) handleTokenRefresh(w http.ResponseWriter, r *http.Request) {
	var req refreshTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.RefreshToken == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "refresh_token is required")
		return
	}

	// Refresh tokens use a long expiry, so we validate with the base JWT secret.
	// The role suffix "_refresh" distinguishes them from access tokens.
	refreshJWT := NewJWTService(m.cfg.JWTSecret, 30*24*time.Hour)
	claims, err := refreshJWT.ValidateToken(req.RefreshToken)
	if err != nil {
		response.Error(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid or expired refresh token")
		return
	}

	role := claims["role"]
	// Strip the "_refresh" suffix to get the actual role for the new access token.
	const suffix = "_refresh"
	if len(role) > len(suffix) && role[len(role)-len(suffix):] == suffix {
		role = role[:len(role)-len(suffix)]
	}

	newToken, err := m.jwt.GenerateToken(Claims{
		TenantID:       claims["tenant_id"],
		DeviceID:       claims["device_id"],
		UserID:         claims["user_id"],
		Role:           role,
		OrganizationID: claims["organization_id"],
		OrgRole:        claims["org_role"],
	})
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "TOKEN_ERROR", "Failed to generate token")
		return
	}

	// Issue a rotated refresh token as well.
	newRefreshExpiry := 30 * 24 * time.Hour
	jwtRefresh := NewJWTService(m.cfg.JWTSecret, newRefreshExpiry)
	newRefresh, _ := jwtRefresh.GenerateToken(Claims{
		TenantID:       claims["tenant_id"],
		DeviceID:       claims["device_id"],
		UserID:         claims["user_id"],
		Role:           role + suffix,
		OrganizationID: claims["organization_id"],
		OrgRole:        claims["org_role"],
	})

	response.JSON(w, http.StatusOK, tokenResponse{
		AccessToken:  newToken,
		RefreshToken: newRefresh,
		ExpiresIn:    int(m.cfg.JWTExpiry.Seconds()),
		TokenType:    "Bearer",
	})
}
