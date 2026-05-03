package receipt_templates

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"

	"github.com/gastrocore/server/internal/shared/response"
)

// TenantInfo carries the CH-specific receipt-printing fields a tenant needs
// to comply with MWST law (UID-Nummer mandatory on every Beleg).
type TenantInfo struct {
	ID              string `json:"id"`
	Name            string `json:"name"`
	Address         string `json:"address"`
	Phone           string `json:"phone"`
	UIDNummer       string `json:"uid_nummer"`
	IBAN            string `json:"iban"`
	Website         string `json:"website"`
	DefaultLanguage string `json:"default_language"`
}

type tenantInfoUpdateReq struct {
	Address         *string `json:"address"`
	Phone           *string `json:"phone"`
	UIDNummer       *string `json:"uid_nummer"`
	IBAN            *string `json:"iban"`
	Website         *string `json:"website"`
	DefaultLanguage *string `json:"default_language"`
}

// GET /api/v1/receipt-templates/tenant-info
// Returns CH-specific tenant fields for use in the receipt-templates editor
// (preview substitution and tenant-info form).
func (m *Module) handleTenantInfoGet(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	var info TenantInfo
	var address, phone, uid, iban, website sql.NullString
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, name, address, phone, uid_nummer, iban, website,
		       COALESCE(default_language, 'de')
		FROM tenants
		WHERE id = $1
	`, tenantID).Scan(
		&info.ID, &info.Name, &address, &phone, &uid, &iban, &website,
		&info.DefaultLanguage,
	)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Tenant not found")
		return
	}
	if err != nil {
		slog.Error("receipt_templates: tenant info get", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load tenant info")
		return
	}
	info.Address = nullStr(address)
	info.Phone = nullStr(phone)
	info.UIDNummer = nullStr(uid)
	info.IBAN = nullStr(iban)
	info.Website = nullStr(website)
	response.JSON(w, http.StatusOK, info)
}

// PUT /api/v1/receipt-templates/tenant-info
// Partial update of CH-specific fields. Only provided keys are written.
func (m *Module) handleTenantInfoUpdate(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	var req tenantInfoUpdateReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	// Validate UID format if provided: CHE-XXX.XXX.XXX (optional ' MWST' or ' IVA' or ' TVA' suffix).
	if req.UIDNummer != nil && *req.UIDNummer != "" {
		if !isLikelyUID(*req.UIDNummer) {
			response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR",
				"uid_nummer must look like CHE-XXX.XXX.XXX MWST")
			return
		}
	}
	if req.DefaultLanguage != nil && *req.DefaultLanguage != "" {
		switch *req.DefaultLanguage {
		case "de", "fr", "it", "en", "tr":
		default:
			response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR",
				"default_language must be one of de|fr|it|en|tr")
			return
		}
	}

	res, err := m.db.ExecContext(r.Context(), `
		UPDATE tenants SET
			address          = COALESCE($2, address),
			phone            = COALESCE($3, phone),
			uid_nummer       = COALESCE($4, uid_nummer),
			iban             = COALESCE($5, iban),
			website          = COALESCE($6, website),
			default_language = COALESCE($7, default_language),
			updated_at       = NOW()
		WHERE id = $1
	`, tenantID,
		ptrToNull(req.Address),
		ptrToNull(req.Phone),
		ptrToNull(req.UIDNummer),
		ptrToNull(req.IBAN),
		ptrToNull(req.Website),
		ptrToNull(req.DefaultLanguage),
	)
	if err != nil {
		slog.Error("receipt_templates: tenant info update", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update tenant info")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Tenant not found")
		return
	}
	response.NoContent(w)
}

// isLikelyUID is a permissive shape check — CHE-XXX.XXX.XXX with optional
// 2-4 letter suffix (MWST | IVA | TVA | VAT). Strict mod-11 checksum is out
// of scope for the pilot; the operator is the source of truth.
func isLikelyUID(s string) bool {
	s = strings.TrimSpace(s)
	if !strings.HasPrefix(s, "CHE-") {
		return false
	}
	body := strings.TrimPrefix(s, "CHE-")
	parts := strings.SplitN(body, " ", 2)
	digits := parts[0]
	if len(digits) != 11 || digits[3] != '.' || digits[7] != '.' {
		return false
	}
	for i, c := range digits {
		if i == 3 || i == 7 {
			continue
		}
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

func ptrToNull(p *string) any {
	if p == nil {
		return nil
	}
	v := strings.TrimSpace(*p)
	if v == "" {
		return nil
	}
	return v
}
