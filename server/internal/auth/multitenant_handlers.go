package auth

// multitenant_handlers.go — New multi-tenant auth endpoints:
//   POST /api/v1/auth/register   — create brand + first store + owner account
//   POST /api/v1/auth/login      — email/password login for all user types
//   POST /api/v1/auth/pin-login  — PIN + store_id for POS staff
//   POST /api/v1/auth/pair-device — 6-digit pairing code for KDS/ODS
//   POST /api/v1/auth/refresh    — persisted refresh token rotation

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log/slog"
	"math/big"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/crypto"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

// ─────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────

// hashToken returns the hex-encoded SHA-256 of a raw token string.
// Used for storing/looking up refresh tokens without keeping the
// plaintext value in the database.
func hashToken(raw string) string {
	h := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(h[:])
}

// generateRefreshToken creates a cryptographically random 72-char opaque token.
func generateRefreshToken() string {
	return uuid.New() + uuid.New() // 2 × RFC 4122 UUID = 72 chars (dashes included)
}

// storeRefreshToken persists the hashed token for the given user.
func (m *Module) storeRefreshToken(userID, rawToken, deviceID string, expiry time.Duration) error {
	hash := hashToken(rawToken)
	expiresAt := time.Now().Add(expiry)
	_, err := m.db.Exec(`
		INSERT INTO refresh_tokens (id, user_id, token_hash, device_id, expires_at)
		VALUES (gen_random_uuid(), $1, $2, $3, $4)
	`, userID, hash, deviceID, expiresAt)
	return err
}

// issueTokenPair creates an access JWT + raw refresh token and persists the refresh.
func (m *Module) issueTokenPair(
	claims Claims,
	userID string,
	refreshExpiry time.Duration,
	deviceID string,
) (accessToken, refreshToken string, err error) {
	accessToken, err = m.jwt.GenerateToken(claims)
	if err != nil {
		return "", "", fmt.Errorf("generate access token: %w", err)
	}

	rawRefresh := generateRefreshToken()
	if err = m.storeRefreshToken(userID, rawRefresh, deviceID, refreshExpiry); err != nil {
		return "", "", fmt.Errorf("store refresh token: %w", err)
	}

	return accessToken, rawRefresh, nil
}

// generateStoreCode creates a unique store code like "CH000042".
func generateStoreCode(country string) string {
	n, _ := rand.Int(rand.Reader, big.NewInt(999999))
	return fmt.Sprintf("%s%06d", country, n.Int64()+1)
}

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/register
// ─────────────────────────────────────────────────────────────

type registerRequest struct {
	// Brand / org
	BrandName string `json:"brand_name"` // required: "Restaurant Group Zürich"
	// First store
	StoreName string `json:"store_name"` // required: "Zürich Hauptbahnhof"
	Country   string `json:"country"`    // optional, default "CH"
	Currency  string `json:"currency"`   // optional, default "CHF"
	Timezone  string `json:"timezone"`   // optional, default "Europe/Zurich"
	// Owner account
	Email    string `json:"email"`    // required
	Password string `json:"password"` // required, min 8 chars
}

type registerResponse struct {
	AccessToken  string       `json:"access_token"`
	RefreshToken string       `json:"refresh_token"`
	ExpiresIn    int          `json:"expires_in"`
	TokenType    string       `json:"token_type"`
	User         appUserInfo  `json:"user"`
	BrandID      string       `json:"brand_id"`  // = organization_id
	StoreID      string       `json:"store_id"`
}

type appUserInfo struct {
	ID             string `json:"id"`
	OrganizationID string `json:"organization_id"`
	StoreID        string `json:"store_id,omitempty"`
	Email          string `json:"email,omitempty"`
	Username       string `json:"username,omitempty"`
	DisplayName    string `json:"display_name"`
	Role           string `json:"role"`
}

// handleRegister creates a brand (organization) + first store + brand_manager account.
// POST /api/v1/auth/register
func (m *Module) handleRegister(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	if req.BrandName == "" || req.StoreName == "" || req.Email == "" || req.Password == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR",
			"brand_name, store_name, email, and password are required")
		return
	}
	if len(req.Password) < 8 {
		response.Error(w, http.StatusBadRequest, "WEAK_PASSWORD", "Password must be at least 8 characters")
		return
	}

	// Defaults
	if req.Country == "" {
		req.Country = "CH"
	}
	if req.Currency == "" {
		req.Currency = "CHF"
	}
	if req.Timezone == "" {
		req.Timezone = "Europe/Zurich"
	}

	// Check email uniqueness upfront (avoids transaction rollback for a common error)
	var emailExists bool
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT EXISTS(SELECT 1 FROM app_users WHERE email=$1)`, req.Email,
	).Scan(&emailExists)
	if emailExists {
		response.Error(w, http.StatusConflict, "EMAIL_TAKEN", "An account with this email already exists")
		return
	}

	passwordHash, err := crypto.HashPassword(req.Password)
	if err != nil {
		slog.Error("auth: hash password", "error", err)
		response.Error(w, http.StatusInternalServerError, "HASH_ERROR", "Failed to process password")
		return
	}

	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to start transaction")
		return
	}
	defer tx.Rollback()

	// 1. Create organization (= "brand" in API terminology)
	orgID := uuid.New()
	_, err = tx.ExecContext(r.Context(), `
		INSERT INTO organizations (id, name, country, plan, status, created_at, updated_at)
		VALUES ($1, $2, $3, 'free', 'active', NOW(), NOW())
	`, orgID, req.BrandName, req.Country)
	if err != nil {
		slog.Error("auth: create org", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create organization")
		return
	}

	// 2. Create brand record linked to org
	brandID := uuid.New()
	_, err = tx.ExecContext(r.Context(), `
		INSERT INTO brands (id, organization_id, name, status, created_at, updated_at)
		VALUES ($1, $2, $3, 'active', NOW(), NOW())
	`, brandID, orgID, req.BrandName)
	if err != nil {
		slog.Error("auth: create brand", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create brand")
		return
	}

	// 3. Create first store with a unique store_code
	storeID := uuid.New()
	storeCode := generateStoreCode(req.Country)
	_, err = tx.ExecContext(r.Context(), `
		INSERT INTO stores (
			id, brand_id, organization_id, store_code, name,
			country, timezone, currency, status, created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'active', NOW(), NOW())
	`, storeID, brandID, orgID, storeCode, req.StoreName,
		req.Country, req.Timezone, req.Currency)
	if err != nil {
		slog.Error("auth: create store", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create store")
		return
	}

	// 4. Create brand_manager user (store_id = NULL → org-level access)
	userID := uuid.New()
	_, err = tx.ExecContext(r.Context(), `
		INSERT INTO app_users (
			id, organization_id, store_id, email, password_hash,
			role, display_name, is_active, created_at, updated_at
		) VALUES ($1, $2, NULL, $3, $4, 'brand_manager', $5, TRUE, NOW(), NOW())
	`, userID, orgID, req.Email, passwordHash, req.BrandName+" Owner")
	if err != nil {
		slog.Error("auth: create app_user", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create user")
		return
	}

	if err = tx.Commit(); err != nil {
		slog.Error("auth: register commit", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to complete registration")
		return
	}

	slog.Info("auth: registered new brand",
		"org_id", orgID, "store_id", storeID, "user_id", userID)

	accessToken, refreshToken, err := m.issueTokenPair(Claims{
		TenantID: orgID,
		UserID:   userID,
		StoreID:  storeID,
		Role:     "brand_manager",
	}, userID, 30*24*time.Hour, "")
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "TOKEN_ERROR", "Failed to issue tokens")
		return
	}

	response.JSON(w, http.StatusCreated, registerResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int(m.cfg.JWTExpiry.Seconds()),
		TokenType:    "Bearer",
		BrandID:      orgID,
		StoreID:      storeID,
		User: appUserInfo{
			ID:             userID,
			OrganizationID: orgID,
			Email:          req.Email,
			DisplayName:    req.BrandName + " Owner",
			Role:           "brand_manager",
		},
	})
}

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/login
// ─────────────────────────────────────────────────────────────

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	// Optional: if provided, the refresh token will be scoped to this device.
	DeviceID string `json:"device_id,omitempty"`
}

type loginResponse struct {
	AccessToken  string      `json:"access_token"`
	RefreshToken string      `json:"refresh_token"`
	ExpiresIn    int         `json:"expires_in"`
	TokenType    string      `json:"token_type"`
	User         appUserInfo `json:"user"`
}

// handleLogin authenticates by email + password.
// POST /api/v1/auth/login
func (m *Module) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
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
		storeID      sql.NullString
		displayName  string
		role         string
		passwordHash string
		isActive     bool
	)

	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, organization_id, store_id, COALESCE(display_name,''), role,
		       password_hash, is_active
		FROM app_users
		WHERE email = $1
	`, req.Email).Scan(&userID, &orgID, &storeID, &displayName, &role, &passwordHash, &isActive)

	if err == sql.ErrNoRows {
		// Constant-time dummy verify to prevent timing leaks.
		crypto.VerifyPassword(req.Password, "pbkdf2$sha256$100000$AAAA$BBBB")
		// Cross-table hint: an admin_users email landing on POS login means the
		// operator picked the wrong app. Surface a clear redirect message.
		var adminExists bool
		_ = m.db.QueryRowContext(r.Context(),
			`SELECT EXISTS(SELECT 1 FROM admin_users WHERE email=$1 AND status='active')`,
			req.Email).Scan(&adminExists)
		if adminExists {
			response.Error(w, http.StatusForbidden, "WRONG_PORTAL",
				"Bu hesap backoffice yöneticisine ait. POS girişi için restorana özel POS Operatörü hesabıyla giriş yapın.")
			return
		}
		response.Error(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Invalid email or password")
		return
	}
	if err != nil {
		slog.Error("auth: login query", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Login failed")
		return
	}

	if !crypto.VerifyPassword(req.Password, passwordHash) {
		response.Error(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Invalid email or password")
		return
	}
	if !isActive {
		response.Error(w, http.StatusForbidden, "ACCOUNT_INACTIVE", "Account is suspended or inactive")
		return
	}
	if !posAllowedRoles[role] {
		response.Error(w, http.StatusForbidden, "WRONG_PORTAL",
			"Bu hesap POS girişi için uygun değil. Restorana özel POS Operatörü hesabıyla giriş yapın.")
		return
	}

	// Update last_login
	_, _ = m.db.ExecContext(r.Context(), `UPDATE app_users SET last_login=NOW() WHERE id=$1`, userID)

	claims := Claims{
		TenantID: orgID,
		UserID:   userID,
		Role:     role,
	}
	if storeID.Valid {
		claims.StoreID = storeID.String
	}

	// Refresh expiry: 365 days for free/offline, 30 days for paid (simplified: use 30d)
	refreshExpiry := 30 * 24 * time.Hour
	accessToken, refreshToken, err := m.issueTokenPair(claims, userID, refreshExpiry, req.DeviceID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "TOKEN_ERROR", "Failed to issue tokens")
		return
	}

	info := appUserInfo{
		ID:             userID,
		OrganizationID: orgID,
		DisplayName:    displayName,
		Email:          req.Email,
		Role:           role,
	}
	if storeID.Valid {
		info.StoreID = storeID.String
	}

	response.JSON(w, http.StatusOK, loginResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int(m.cfg.JWTExpiry.Seconds()),
		TokenType:    "Bearer",
		User:         info,
	})
}

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/pin-login
// ─────────────────────────────────────────────────────────────

type pinLoginRequest struct {
	PIN     string `json:"pin"`
	StoreID string `json:"store_id"`
}

type pinLoginResponse struct {
	AccessToken string `json:"access_token"`
	ExpiresIn   int    `json:"expires_in"`
	TokenType   string `json:"token_type"`
	EmployeeID  string `json:"employee_id"`
	Name        string `json:"name"`
	Role        string `json:"role"`
}

// handlePINLogin authenticates a POS staff member by PIN + store_id.
// POST /api/v1/auth/pin-login
func (m *Module) handlePINLogin(w http.ResponseWriter, r *http.Request) {
	var req pinLoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.PIN == "" || req.StoreID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "pin and store_id are required")
		return
	}

	// Fetch all active employees for this store that have a PIN
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, organization_id, name, role, pin_hash
		FROM employees
		WHERE store_id = $1 AND is_active = TRUE AND pin_hash IS NOT NULL
	`, req.StoreID)
	if err != nil {
		slog.Error("auth: pin-login query", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Login failed")
		return
	}
	defer rows.Close()

	type candidate struct {
		id, orgID, name, role, pinHash string
	}
	var matched *candidate

	for rows.Next() {
		var c candidate
		if err := rows.Scan(&c.id, &c.orgID, &c.name, &c.role, &c.pinHash); err != nil {
			continue
		}
		if crypto.VerifyPIN(req.PIN, c.pinHash) {
			matched = &c
			break
		}
	}
	rows.Close()

	if matched == nil {
		response.Error(w, http.StatusUnauthorized, "INVALID_PIN", "Invalid PIN")
		return
	}

	// PIN sessions are short-lived access-only (no refresh token stored)
	token, err := m.jwt.GenerateToken(Claims{
		TenantID: matched.orgID,
		UserID:   matched.id,
		StoreID:  req.StoreID,
		Role:     matched.role,
	})
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "TOKEN_ERROR", "Failed to generate token")
		return
	}

	response.JSON(w, http.StatusOK, pinLoginResponse{
		AccessToken: token,
		ExpiresIn:   int(m.cfg.JWTExpiry.Seconds()),
		TokenType:   "Bearer",
		EmployeeID:  matched.id,
		Name:        matched.name,
		Role:        matched.role,
	})
}

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/pair-device
// ─────────────────────────────────────────────────────────────

type pairDeviceRequest struct {
	PairingCode string `json:"pairing_code"` // 6-digit code shown on POS
	StoreID     string `json:"store_id"`
	DeviceType  string `json:"device_type"`  // kds, ods
	DeviceName  string `json:"device_name"`
}

type pairDeviceResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
	TokenType    string `json:"token_type"`
	DeviceUserID string `json:"device_user_id"`
}

// handlePairDevice exchanges a 6-digit pairing code for a JWT.
// POST /api/v1/auth/pair-device
func (m *Module) handlePairDevice(w http.ResponseWriter, r *http.Request) {
	var req pairDeviceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.PairingCode == "" || req.StoreID == "" || req.DeviceType == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR",
			"pairing_code, store_id, and device_type are required")
		return
	}

	// Lookup active (unpaired, not expired) pairing record
	var pairingID, orgID string
	err := m.db.QueryRowContext(r.Context(), `
		SELECT dp.id, s.organization_id
		FROM device_pairings dp
		JOIN stores s ON s.id = dp.store_id
		WHERE dp.pairing_code = $1
		  AND dp.store_id = $2
		  AND dp.paired_at IS NULL
		  AND dp.expires_at > NOW()
	`, req.PairingCode, req.StoreID).Scan(&pairingID, &orgID)

	if err == sql.ErrNoRows {
		response.Error(w, http.StatusUnauthorized, "INVALID_CODE", "Invalid or expired pairing code")
		return
	}
	if err != nil {
		slog.Error("auth: pair-device lookup", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to verify pairing code")
		return
	}

	// Create a device app_user (password_hash is a random unusable value — device logs in via refresh token only)
	deviceUserID := uuid.New()
	unusableHash, _ := crypto.HashPassword(uuid.New()) // random, never usable for login
	displayName := req.DeviceName
	if displayName == "" {
		displayName = req.DeviceType + "-" + req.StoreID[:8]
	}

	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to start transaction")
		return
	}
	defer tx.Rollback()

	_, err = tx.ExecContext(r.Context(), `
		INSERT INTO app_users (
			id, organization_id, store_id, password_hash,
			role, display_name, is_active, created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, TRUE, NOW(), NOW())
	`, deviceUserID, orgID, req.StoreID, unusableHash, req.DeviceType, displayName)
	if err != nil {
		slog.Error("auth: pair-device create user", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create device user")
		return
	}

	// Mark pairing as used
	_, err = tx.ExecContext(r.Context(), `
		UPDATE device_pairings
		SET paired_at=NOW(), user_id=$2, device_name=$3, device_type=$4
		WHERE id=$1
	`, pairingID, deviceUserID, displayName, req.DeviceType)
	if err != nil {
		slog.Error("auth: pair-device update pairing", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to complete pairing")
		return
	}

	if err = tx.Commit(); err != nil {
		slog.Error("auth: pair-device commit", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to complete pairing")
		return
	}

	accessToken, refreshToken, err := m.issueTokenPair(Claims{
		TenantID:   orgID,
		UserID:     deviceUserID,
		StoreID:    req.StoreID,
		DeviceType: req.DeviceType,
		Role:       req.DeviceType, // role = kds / ods
	}, deviceUserID, 365*24*time.Hour, pairingID) // long-lived for offline devices
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "TOKEN_ERROR", "Failed to issue tokens")
		return
	}

	slog.Info("auth: device paired",
		"pairing_id", pairingID, "device_user_id", deviceUserID,
		"store_id", req.StoreID, "type", req.DeviceType)

	response.JSON(w, http.StatusOK, pairDeviceResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int(m.cfg.JWTExpiry.Seconds()),
		TokenType:    "Bearer",
		DeviceUserID: deviceUserID,
	})
}

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/refresh  (persisted token rotation)
// ─────────────────────────────────────────────────────────────

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
	DeviceID     string `json:"device_id,omitempty"`
}

// handleRefreshPersisted validates a stored refresh token, rotates it, and issues
// a new access + refresh pair.
// POST /api/v1/auth/refresh
func (m *Module) handleRefreshPersisted(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.RefreshToken == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "refresh_token is required")
		return
	}

	tokenHash := hashToken(req.RefreshToken)

	var (
		rtID      string
		userID    string
		expiresAt time.Time
	)
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, user_id, expires_at
		FROM refresh_tokens
		WHERE token_hash = $1
	`, tokenHash).Scan(&rtID, &userID, &expiresAt)

	if err == sql.ErrNoRows {
		response.Error(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid or revoked refresh token")
		return
	}
	if err != nil {
		slog.Error("auth: refresh token lookup", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to validate token")
		return
	}
	if time.Now().After(expiresAt) {
		// Clean up expired token
		_, _ = m.db.ExecContext(r.Context(), `DELETE FROM refresh_tokens WHERE id=$1`, rtID)
		response.Error(w, http.StatusUnauthorized, "TOKEN_EXPIRED", "Refresh token has expired")
		return
	}

	// Load user to rebuild claims
	var orgID, role string
	var storeID, deviceType sql.NullString
	var isActive bool

	err = m.db.QueryRowContext(r.Context(), `
		SELECT organization_id, store_id, role, is_active
		FROM app_users WHERE id = $1
	`, userID).Scan(&orgID, &storeID, &role, &isActive)

	if err == sql.ErrNoRows {
		response.Error(w, http.StatusUnauthorized, "USER_NOT_FOUND", "User account no longer exists")
		return
	}
	if err != nil {
		slog.Error("auth: refresh user lookup", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load user")
		return
	}
	if !isActive {
		response.Error(w, http.StatusForbidden, "ACCOUNT_INACTIVE", "Account is suspended")
		return
	}
	_ = deviceType // not stored in app_users, carried in role for device accounts

	// Delete old token (rotation — prevents reuse)
	_, _ = m.db.ExecContext(r.Context(), `DELETE FROM refresh_tokens WHERE id=$1`, rtID)

	claims := Claims{
		TenantID: orgID,
		UserID:   userID,
		Role:     role,
	}
	if storeID.Valid {
		claims.StoreID = storeID.String
	}
	// For device roles (kds, ods), set DeviceType from role
	switch role {
	case "kds", "ods", "kiosk":
		claims.DeviceType = role
	}

	// Preserve similar expiry to the original token
	remaining := time.Until(expiresAt)
	refreshExpiry := remaining
	if refreshExpiry < 24*time.Hour {
		refreshExpiry = 24 * time.Hour // always at least 24h
	}

	accessToken, newRefreshToken, err := m.issueTokenPair(claims, userID, refreshExpiry, req.DeviceID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "TOKEN_ERROR", "Failed to issue tokens")
		return
	}

	response.JSON(w, http.StatusOK, tokenResponse{
		AccessToken:  accessToken,
		RefreshToken: newRefreshToken,
		ExpiresIn:    int(m.cfg.JWTExpiry.Seconds()),
		TokenType:    "Bearer",
	})
}

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/pairing-code  (POS generates a code for KDS)
// ─────────────────────────────────────────────────────────────

type generatePairingCodeRequest struct {
	StoreID    string `json:"store_id"`
	DeviceType string `json:"device_type"` // kds, ods
}

type generatePairingCodeResponse struct {
	PairingCode string    `json:"pairing_code"`
	ExpiresAt   time.Time `json:"expires_at"`
}

// handleGeneratePairingCode creates a 6-digit code that a KDS/ODS device can use
// to authenticate. Requires an authenticated POS/admin session.
// POST /api/v1/auth/pairing-code
func (m *Module) handleGeneratePairingCode(w http.ResponseWriter, r *http.Request) {
	var req generatePairingCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.StoreID == "" || req.DeviceType == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store_id and device_type are required")
		return
	}

	// Generate a 6-digit numeric code
	n, _ := rand.Int(rand.Reader, big.NewInt(900000))
	code := fmt.Sprintf("%06d", n.Int64()+100000)

	expiresAt := time.Now().Add(10 * time.Minute)

	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO device_pairings (id, store_id, pairing_code, device_type, expires_at, created_at)
		VALUES (gen_random_uuid(), $1, $2, $3, $4, NOW())
		ON CONFLICT (store_id, pairing_code) WHERE paired_at IS NULL
		DO UPDATE SET expires_at = EXCLUDED.expires_at
	`, req.StoreID, code, req.DeviceType, expiresAt)
	if err != nil {
		slog.Error("auth: generate pairing code", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to generate pairing code")
		return
	}

	slog.Info("auth: pairing code generated",
		"store_id", req.StoreID, "device_type", req.DeviceType)

	response.JSON(w, http.StatusCreated, generatePairingCodeResponse{
		PairingCode: code,
		ExpiresAt:   expiresAt,
	})
}
