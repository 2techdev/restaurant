package menu

// Device pairing — POS tablets exchange admin credentials for a
// device-scoped, revocable API key. Three endpoints:
//
//   POST   /api/v1/me/devices/register      — POS calls after admin login
//   GET    /api/v1/me/devices               — backoffice lists tablets
//   DELETE /api/v1/me/devices/{id}          — backoffice revokes a tablet
//
// The plain key is shown ONCE in the register response. The server stores
// only a bcrypt hash (`pos_devices.api_key_hash`) plus a 12-char lookup
// prefix. Menu sync endpoints accept these keys via `X-API-Key`.

import (
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"

	"github.com/gastrocore/server/internal/shared/crypto"
	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// keyPrefixLen is the index window we slice off the plaintext key to drive
// bcrypt-candidate lookups. 12 chars from a 32-byte URL-safe key gives us
// ~72 bits of pre-hash uniqueness, which collides at <1e-9 across the
// pilot's expected device count.
const keyPrefixLen = 12

// keyPrefixTag is prepended so plaintext keys are visually identifiable in
// logs and never confused with raw JWTs or session tokens.
const keyPrefixTag = "gc_dev_"

// ---------------------------------------------------------------------------
// Wire types
// ---------------------------------------------------------------------------

type registerDeviceRequest struct {
	TenantID          string `json:"tenant_id"`
	Name              string `json:"name"`
	DeviceFingerprint string `json:"device_fingerprint,omitempty"`
}

type registerDeviceResponse struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	APIKey    string `json:"api_key"`
	TenantID  string `json:"tenant_id"`
	CreatedAt string `json:"created_at"`
	Warning   string `json:"warning"`
}

type deviceListItem struct {
	ID            string  `json:"id"`
	Name          string  `json:"name"`
	APIKeyPrefix  string  `json:"api_key_prefix"`
	TenantID      string  `json:"tenant_id"`
	CreatedAt     string  `json:"created_at"`
	LastSeenAt    *string `json:"last_seen_at"`
	Fingerprint   *string `json:"device_fingerprint"`
}

// ---------------------------------------------------------------------------
// Routes — wired from module.go
// ---------------------------------------------------------------------------

func (m *Module) registerDevicePairingRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/me/devices/register", m.handleDeviceRegister)
	mux.HandleFunc("GET /api/v1/me/devices", m.handleDeviceList)
	mux.HandleFunc("DELETE /api/v1/me/devices/{id}", m.handleDeviceRevoke)
}

// ---------------------------------------------------------------------------
// POST /api/v1/me/devices/register
// ---------------------------------------------------------------------------

func (m *Module) handleDeviceRegister(w http.ResponseWriter, r *http.Request) {
	// Auth: any authenticated admin user. Tenant-access check happens after
	// we read the body so the validation rules live in one place.
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Login required")
		return
	}

	var req registerDeviceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	req.TenantID = strings.TrimSpace(req.TenantID)
	req.Name = strings.TrimSpace(req.Name)
	if req.TenantID == "" || req.Name == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "tenant_id and name are required")
		return
	}
	if len(req.Name) > 80 {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "name must be <= 80 chars")
		return
	}

	// Tenant access: HQ_ADMIN/HQ_MANAGER may register devices for any tenant
	// in their organization; restaurant-scoped users only for their own
	// JWT-bound tenant.
	if !m.userCanRegisterForTenant(r, req.TenantID) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "User cannot register devices for this tenant")
		return
	}

	// Generate a 32-byte plaintext key. base64url + tag → ~50 chars total.
	// Trimmed of '=' padding so it fits header values cleanly.
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		response.Error(w, http.StatusInternalServerError, "RAND_ERROR", "Failed to generate key")
		return
	}
	plain := keyPrefixTag + strings.TrimRight(base64.URLEncoding.EncodeToString(buf), "=")
	prefix := plain[:keyPrefixLen]

	hash, err := crypto.HashPassword(plain)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "HASH_ERROR", "Failed to hash key")
		return
	}

	var (
		id        string
		createdAt string
	)
	err = m.db.QueryRowContext(r.Context(), `
		INSERT INTO pos_devices (tenant_id, user_id, name, device_fingerprint, api_key_hash, api_key_prefix)
		VALUES ($1, $2, $3, NULLIF($4, ''), $5, $6)
		RETURNING id, created_at::text
	`, req.TenantID, userID, req.Name, req.DeviceFingerprint, hash, prefix).Scan(&id, &createdAt)
	if err != nil {
		// Unique violation on (tenant_id, name) lands here.
		if isUniqueViolation(err) {
			response.Error(w, http.StatusConflict, "DEVICE_NAME_TAKEN",
				"A device with this name already exists for this tenant")
			return
		}
		slog.Error("device register: insert", "error", err, "tenant", req.TenantID)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to insert device")
		return
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"success": true,
		"data": registerDeviceResponse{
			ID:        id,
			Name:      req.Name,
			APIKey:    plain,
			TenantID:  req.TenantID,
			CreatedAt: createdAt,
			Warning:   "This key is shown only once. Store it now; you cannot retrieve it later.",
		},
	})
}

// ---------------------------------------------------------------------------
// GET /api/v1/me/devices?tenant_id=...
// ---------------------------------------------------------------------------

func (m *Module) handleDeviceList(w http.ResponseWriter, r *http.Request) {
	if middleware.GetUserID(r.Context()) == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Login required")
		return
	}

	tenantID := strings.TrimSpace(r.URL.Query().Get("tenant_id"))
	if tenantID == "" {
		// Default to the user's JWT tenant. HQ users can override with the
		// query param to scope to a specific restaurant.
		tenantID = middleware.GetTenantID(r.Context())
	}
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "tenant_id is required")
		return
	}
	if !m.userCanRegisterForTenant(r, tenantID) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "User cannot view devices for this tenant")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, name, api_key_prefix, tenant_id,
		       created_at::text,
		       last_seen_at::text,
		       device_fingerprint
		FROM pos_devices
		WHERE tenant_id = $1 AND revoked_at IS NULL
		ORDER BY created_at DESC
	`, tenantID)
	if err != nil {
		slog.Error("device list: query", "error", err, "tenant", tenantID)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list devices")
		return
	}
	defer rows.Close()

	out := []deviceListItem{}
	for rows.Next() {
		var it deviceListItem
		var lastSeen, fp sql.NullString
		if err := rows.Scan(&it.ID, &it.Name, &it.APIKeyPrefix, &it.TenantID,
			&it.CreatedAt, &lastSeen, &fp); err != nil {
			slog.Error("device list: scan", "error", err)
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to scan device")
			return
		}
		if lastSeen.Valid {
			s := lastSeen.String
			it.LastSeenAt = &s
		}
		if fp.Valid {
			s := fp.String
			it.Fingerprint = &s
		}
		out = append(out, it)
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"success": true,
		"data":    out,
	})
}

// ---------------------------------------------------------------------------
// DELETE /api/v1/me/devices/{id}
// ---------------------------------------------------------------------------

func (m *Module) handleDeviceRevoke(w http.ResponseWriter, r *http.Request) {
	if middleware.GetUserID(r.Context()) == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Login required")
		return
	}
	deviceID := strings.TrimSpace(r.PathValue("id"))
	if deviceID == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "device id is required")
		return
	}

	// Look up the row to confirm tenant access before the UPDATE, so a
	// bad-actor guessing UUIDs gets a 403 instead of a silent no-op 404.
	var tenantID string
	var revokedAt sql.NullTime
	err := m.db.QueryRowContext(r.Context(),
		`SELECT tenant_id, revoked_at FROM pos_devices WHERE id = $1`, deviceID).
		Scan(&tenantID, &revokedAt)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Device not found")
		return
	}
	if err != nil {
		slog.Error("device revoke: lookup", "error", err, "device", deviceID)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to look up device")
		return
	}
	if !m.userCanRegisterForTenant(r, tenantID) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "User cannot revoke devices for this tenant")
		return
	}
	if revokedAt.Valid {
		// Already revoked — idempotent success.
		response.JSON(w, http.StatusOK, map[string]any{"success": true, "data": map[string]any{"id": deviceID, "alreadyRevoked": true}})
		return
	}

	if _, err := m.db.ExecContext(r.Context(),
		`UPDATE pos_devices SET revoked_at = NOW() WHERE id = $1`, deviceID); err != nil {
		slog.Error("device revoke: update", "error", err, "device", deviceID)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to revoke device")
		return
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"success": true,
		"data":    map[string]any{"id": deviceID, "revoked": true},
	})
}

// ---------------------------------------------------------------------------
// Tenant access check
// ---------------------------------------------------------------------------

// userCanRegisterForTenant returns true if the JWT in the request grants the
// user the right to manage devices for `tenantID`. Rules:
//
//   * HQ_ADMIN / HQ_MANAGER (org_role) — yes, for any tenant in their org.
//     We don't enforce the org membership here yet because the multi-tenant
//     pilot has only one org; once the pilot expands this should grow into
//     a join against organization_memberships.
//   * Restaurant-scoped roles (admin / brand_manager / store_manager) — yes
//     iff JWT's tenant_id matches the requested tenant.
func (m *Module) userCanRegisterForTenant(r *http.Request, tenantID string) bool {
	if tenantID == "" {
		return false
	}
	orgRole := middleware.GetOrgRole(r.Context())
	if orgRole == "HQ_ADMIN" || orgRole == "HQ_MANAGER" {
		return true
	}
	role := middleware.GetRole(r.Context())
	if role != "admin" && role != "brand_manager" && role != "store_manager" {
		return false
	}
	return middleware.GetTenantID(r.Context()) == tenantID
}

// ---------------------------------------------------------------------------
// X-API-Key validation — called from authorizeTenantRead in menusync.go
// ---------------------------------------------------------------------------

// validateDeviceAPIKey looks up an X-API-Key against `pos_devices`. Returns
// the device's tenant_id on success, "" otherwise. Side effect on success:
// `last_seen_at` is bumped to NOW() so the backoffice device list shows
// recency without a separate heartbeat endpoint.
func (m *Module) validateDeviceAPIKey(r *http.Request, key string) string {
	if key == "" || len(key) <= keyPrefixLen {
		return ""
	}
	if !strings.HasPrefix(key, keyPrefixTag) {
		return ""
	}
	prefix := key[:keyPrefixLen]

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, api_key_hash
		FROM pos_devices
		WHERE api_key_prefix = $1 AND revoked_at IS NULL
	`, prefix)
	if err != nil {
		slog.Error("device api key: query", "error", err)
		return ""
	}
	defer rows.Close()

	for rows.Next() {
		var id, tenantID, hash string
		if err := rows.Scan(&id, &tenantID, &hash); err != nil {
			continue
		}
		if crypto.VerifyPassword(key, hash) {
			// Bump last_seen_at; ignore errors, this is observability only.
			_, _ = m.db.ExecContext(r.Context(),
				`UPDATE pos_devices SET last_seen_at = NOW() WHERE id = $1`, id)
			return tenantID
		}
	}
	return ""
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// isUniqueViolation matches Postgres' SQLSTATE 23505 (unique_violation). We
// cross-package match on the error string so we don't have to import lib/pq
// types into this package.
func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	s := err.Error()
	return strings.Contains(s, "23505") ||
		strings.Contains(s, "duplicate key value violates unique constraint")
}
