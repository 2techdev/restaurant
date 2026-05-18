package loyalty

import (
	"database/sql"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// ---------------------------------------------------------------------------
// GET /api/v1/loyalty/settings
// ---------------------------------------------------------------------------

func (m *Module) handleGetSettings(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	s, err := m.loadSettings(r, tenantID)
	if err != nil {
		slog.Error("loyalty: load settings", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load settings")
		return
	}
	response.JSON(w, http.StatusOK, s)
}

func (m *Module) loadSettings(r *http.Request, tenantID string) (Settings, error) {
	var s Settings
	s.TenantID = tenantID
	err := m.db.QueryRowContext(r.Context(), `
		SELECT is_enabled, earn_rate_points_per_chf, redeem_rate_points_per_chf, expiry_months
		FROM loyalty_program_settings
		WHERE tenant_id = $1
	`, tenantID).Scan(&s.IsEnabled, &s.EarnRatePointsPerCHF, &s.RedeemRatePointsPerCHF, &s.ExpiryMonths)
	if errors.Is(err, sql.ErrNoRows) {
		// Auto-create row on first access (defaults).
		_, ierr := m.db.ExecContext(r.Context(),
			`INSERT INTO loyalty_program_settings (tenant_id) VALUES ($1) ON CONFLICT DO NOTHING`,
			tenantID)
		if ierr != nil {
			return s, ierr
		}
		s.IsEnabled = false
		s.EarnRatePointsPerCHF = 1.0
		s.RedeemRatePointsPerCHF = 100.0
		s.ExpiryMonths = 24
		return s, nil
	}
	return s, err
}

// ---------------------------------------------------------------------------
// PUT /api/v1/loyalty/settings
// ---------------------------------------------------------------------------

type settingsReq struct {
	IsEnabled              *bool    `json:"is_enabled"`
	EarnRatePointsPerCHF   *float64 `json:"earn_rate_points_per_chf"`
	RedeemRatePointsPerCHF *float64 `json:"redeem_rate_points_per_chf"`
	ExpiryMonths           *int     `json:"expiry_months"`
}

func (m *Module) handleUpdateSettings(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" || !canManageLoyalty(middleware.GetRole(r.Context())) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
		return
	}
	var req settingsReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	// Ensure a row exists.
	if _, err := m.loadSettings(r, tenantID); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load settings")
		return
	}
	_, err := m.db.ExecContext(r.Context(), `
		UPDATE loyalty_program_settings
		SET is_enabled = COALESCE($2, is_enabled),
		    earn_rate_points_per_chf = COALESCE($3, earn_rate_points_per_chf),
		    redeem_rate_points_per_chf = COALESCE($4, redeem_rate_points_per_chf),
		    expiry_months = COALESCE($5, expiry_months),
		    updated_at = NOW()
		WHERE tenant_id = $1
	`, tenantID, req.IsEnabled, req.EarnRatePointsPerCHF, req.RedeemRatePointsPerCHF, req.ExpiryMonths)
	if err != nil {
		slog.Error("loyalty: update settings", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update settings")
		return
	}
	s, _ := m.loadSettings(r, tenantID)
	response.JSON(w, http.StatusOK, s)
}
