package stores

// settings.go — Per-store settings API for the backoffice Settings page.
//
// Routes registered:
//   GET  /api/v1/stores/{id}/settings — return the settings subset
//   PUT  /api/v1/stores/{id}/settings — update the settings subset
//
// The settings subset is a curated view of the stores row focused on what the
// backoffice Settings page edits: restaurant info, currency/timezone, VAT, and
// the service charge toggle + percent. Fuller store edits still go through
// PUT /api/v1/stores/{id}.

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// StoreSettings is the backoffice-facing settings projection of a store.
type StoreSettings struct {
	StoreID              string   `json:"store_id"`
	Name                 string   `json:"name"`
	Address              string   `json:"address"`
	Phone                string   `json:"phone"`
	Email                string   `json:"email"`
	Currency             string   `json:"currency"`
	Timezone             string   `json:"timezone"`
	TaxRate              float64  `json:"tax_rate"`
	Language             string   `json:"language"`
	ServiceChargeEnabled bool     `json:"service_charge_enabled"`
	ServiceChargePercent float64  `json:"service_charge_percent"`
	GangsEnabled         bool     `json:"gangs_enabled"`
	MaxGangs             int      `json:"max_gangs"`
	GangLabels           []string `json:"gang_labels"`
}

// handleGetSettings returns the settings subset of a store.
// GET /api/v1/stores/{id}/settings
func (m *Module) handleGetSettings(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	storeID := r.PathValue("id")
	if orgID == "" || storeID == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "store id required")
		return
	}

	var s StoreSettings
	var gangLabelsJSON []byte
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, name,
		       COALESCE(address,''), COALESCE(phone,''), COALESCE(email,''),
		       currency, timezone, COALESCE(tax_rate,0),
		       COALESCE(language,'tr'),
		       COALESCE(service_charge_enabled, FALSE),
		       COALESCE(service_charge_percent, 10),
		       COALESCE(gangs_enabled, TRUE),
		       COALESCE(max_gangs, 3),
		       COALESCE(gang_labels, '["Gang 1","Gang 2","Gang 3"]'::jsonb)
		FROM stores
		WHERE id=$1 AND organization_id=$2
	`, storeID, orgID).Scan(
		&s.StoreID, &s.Name,
		&s.Address, &s.Phone, &s.Email,
		&s.Currency, &s.Timezone, &s.TaxRate,
		&s.Language,
		&s.ServiceChargeEnabled, &s.ServiceChargePercent,
		&s.GangsEnabled, &s.MaxGangs, &gangLabelsJSON,
	)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Store not found")
		return
	}
	if err != nil {
		slog.Error("stores: get settings", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch settings")
		return
	}
	if len(gangLabelsJSON) > 0 {
		if err := json.Unmarshal(gangLabelsJSON, &s.GangLabels); err != nil {
			slog.Warn("stores: invalid gang_labels JSON, using defaults", "error", err, "store_id", s.StoreID)
			s.GangLabels = defaultGangLabels(s.MaxGangs)
		}
	}
	if s.GangLabels == nil {
		s.GangLabels = defaultGangLabels(s.MaxGangs)
	}

	response.JSON(w, http.StatusOK, s)
}

// defaultGangLabels returns ["Gang 1", "Gang 2", ...] up to n items.
func defaultGangLabels(n int) []string {
	if n < 1 {
		n = 3
	}
	out := make([]string, n)
	for i := 0; i < n; i++ {
		out[i] = "Gang " + strconv.Itoa(i+1)
	}
	return out
}

type updateSettingsRequest struct {
	Name                 *string   `json:"name"`
	Address              *string   `json:"address"`
	Phone                *string   `json:"phone"`
	Email                *string   `json:"email"`
	Currency             *string   `json:"currency"`
	Timezone             *string   `json:"timezone"`
	TaxRate              *float64  `json:"tax_rate"`
	Language             *string   `json:"language"`
	ServiceChargeEnabled *bool     `json:"service_charge_enabled"`
	ServiceChargePercent *float64  `json:"service_charge_percent"`
	GangsEnabled         *bool     `json:"gangs_enabled"`
	MaxGangs             *int      `json:"max_gangs"`
	GangLabels           *[]string `json:"gang_labels"`
}

// handleUpdateSettings updates a subset of store settings.
// PUT /api/v1/stores/{id}/settings
func (m *Module) handleUpdateSettings(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	storeID := r.PathValue("id")
	if orgID == "" || storeID == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "store id required")
		return
	}

	var req updateSettingsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.TaxRate != nil && (*req.TaxRate < 0 || *req.TaxRate > 100) {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "tax_rate must be between 0 and 100")
		return
	}
	if req.ServiceChargePercent != nil && (*req.ServiceChargePercent < 0 || *req.ServiceChargePercent > 100) {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "service_charge_percent must be between 0 and 100")
		return
	}
	if req.MaxGangs != nil && (*req.MaxGangs < 1 || *req.MaxGangs > 5) {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "max_gangs must be between 1 and 5")
		return
	}
	// If both max_gangs and gang_labels are provided, their lengths must match.
	// If only gang_labels is provided, length must be 1..5.
	if req.GangLabels != nil {
		labels := *req.GangLabels
		if len(labels) < 1 || len(labels) > 5 {
			response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "gang_labels length must be between 1 and 5")
			return
		}
		for _, l := range labels {
			if l == "" {
				response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "gang_labels entries must not be empty")
				return
			}
		}
		if req.MaxGangs != nil && len(labels) != *req.MaxGangs {
			response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "gang_labels length must equal max_gangs")
			return
		}
	}

	// Encode gang_labels to JSON text (nil when not provided so COALESCE keeps current value).
	var gangLabelsJSON *string
	if req.GangLabels != nil {
		b, err := json.Marshal(*req.GangLabels)
		if err != nil {
			response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "invalid gang_labels")
			return
		}
		s := string(b)
		gangLabelsJSON = &s
	}

	result, err := m.db.ExecContext(r.Context(), `
		UPDATE stores SET
			name = COALESCE($3, name),
			address = COALESCE($4, address),
			phone = COALESCE($5, phone),
			email = COALESCE($6, email),
			currency = COALESCE($7, currency),
			timezone = COALESCE($8, timezone),
			tax_rate = COALESCE($9, tax_rate),
			language = COALESCE($10, language),
			service_charge_enabled = COALESCE($11, service_charge_enabled),
			service_charge_percent = COALESCE($12, service_charge_percent),
			gangs_enabled = COALESCE($13, gangs_enabled),
			max_gangs = COALESCE($14, max_gangs),
			gang_labels = COALESCE($15::jsonb, gang_labels),
			updated_at = NOW()
		WHERE id=$1 AND organization_id=$2
	`, storeID, orgID,
		req.Name, req.Address, req.Phone, req.Email,
		req.Currency, req.Timezone, req.TaxRate,
		req.Language,
		req.ServiceChargeEnabled, req.ServiceChargePercent,
		req.GangsEnabled, req.MaxGangs, gangLabelsJSON,
	)
	if err != nil {
		slog.Error("stores: update settings", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update settings")
		return
	}
	if n, _ := result.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Store not found")
		return
	}

	m.handleGetSettings(w, r)
}
