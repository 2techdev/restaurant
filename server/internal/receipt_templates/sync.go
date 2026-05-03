package receipt_templates

import (
	"database/sql"
	"log/slog"
	"net/http"
	"strings"

	"github.com/gastrocore/server/internal/shared/crypto"
	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// authorizeRead authorises POS sync calls. Accepts JWT (matched against the
// path tenant) OR an X-API-Key, with the same lookup order menu sync uses:
//   - device-scoped key (`gc_dev_…`) against pos_devices
//   - legacy per-tenant key against tenants.pos_api_key
//
// On success returns the resolved tenant id; otherwise responds with 401.
func (m *Module) authorizeRead(r *http.Request, pathTenantID string) (string, bool) {
	if pathTenantID == "" {
		return "", false
	}
	if t := middleware.GetTenantID(r.Context()); t != "" {
		if t == pathTenantID {
			return pathTenantID, true
		}
		return "", false
	}
	key := strings.TrimSpace(r.Header.Get("X-API-Key"))
	if key == "" {
		return "", false
	}
	// Device-scoped key — look up pos_devices.
	if devTenant := m.validateDeviceAPIKey(r, key); devTenant != "" {
		if devTenant != pathTenantID {
			return "", false
		}
		return pathTenantID, true
	}
	// Legacy per-tenant key.
	var stored sql.NullString
	err := m.db.QueryRowContext(r.Context(),
		`SELECT pos_api_key FROM tenants WHERE id = $1`, pathTenantID).Scan(&stored)
	if err != nil || !stored.Valid || stored.String == "" {
		return "", false
	}
	if !crypto.VerifyPassword(key, stored.String) {
		return "", false
	}
	return pathTenantID, true
}

// validateDeviceAPIKey: lightweight inlined version of menu's helper.
// Looks up the api_key against pos_devices.api_key_hash and returns tenantID.
func (m *Module) validateDeviceAPIKey(r *http.Request, apiKey string) string {
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT tenant_id, api_key_hash FROM pos_devices
		WHERE api_key_hash IS NOT NULL AND status = 'active'
	`)
	if err != nil {
		return ""
	}
	defer rows.Close()
	for rows.Next() {
		var tenantID, hash string
		if err := rows.Scan(&tenantID, &hash); err != nil {
			continue
		}
		if crypto.VerifyPassword(apiKey, hash) {
			return tenantID
		}
	}
	return ""
}

// SyncResp is the wire format consumed by the POS Drift sync.
type SyncResp struct {
	Templates  []Template `json:"templates"`
	TenantInfo TenantInfo `json:"tenant_info"`
}

// GET /api/v1/receipt-templates/sync/{tenantId}
//
// POS-facing sync endpoint. Returns every template for the tenant plus the
// CH-specific tenant info (UID, IBAN, address) the renderer needs locally.
// Auth: JWT (tenant-bound) OR X-API-Key from a paired device.
func (m *Module) handleSync(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenantId")
	if _, ok := m.authorizeRead(r, tenantID); !ok {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED",
			"JWT or X-API-Key required")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, name, language, width_mm, is_default,
		       COALESCE(header,''), body_format, COALESCE(footer,''),
		       paper_cut, open_drawer, copies, created_at, updated_at
		FROM receipt_templates
		WHERE tenant_id = $1
		ORDER BY is_default DESC, name ASC
	`, tenantID)
	if err != nil {
		slog.Error("receipt_templates: sync list", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR",
			"Failed to list templates")
		return
	}
	defer rows.Close()
	templates := make([]Template, 0)
	for rows.Next() {
		t, err := scanRow(rows)
		if err != nil {
			continue
		}
		templates = append(templates, t)
	}

	var info TenantInfo
	var address, phone, uid, iban, website sql.NullString
	if err := m.db.QueryRowContext(r.Context(), `
		SELECT id, name, address, phone, uid_nummer, iban, website,
		       COALESCE(default_language, 'de')
		FROM tenants WHERE id = $1
	`, tenantID).Scan(
		&info.ID, &info.Name, &address, &phone, &uid, &iban, &website,
		&info.DefaultLanguage,
	); err != nil && err != sql.ErrNoRows {
		slog.Warn("receipt_templates: tenant info for sync", "error", err)
	}
	info.Address = nullStr(address)
	info.Phone = nullStr(phone)
	info.UIDNummer = nullStr(uid)
	info.IBAN = nullStr(iban)
	info.Website = nullStr(website)

	response.JSON(w, http.StatusOK, SyncResp{
		Templates:  templates,
		TenantInfo: info,
	})
}
