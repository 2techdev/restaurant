package licenses

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// handleValidate validates a license key and returns its status.
// POST /api/v1/licenses/validate
func (m *Module) handleValidate(w http.ResponseWriter, r *http.Request) {
	var req struct {
		LicenseKey string `json:"license_key"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.LicenseKey == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "license_key is required")
		return
	}

	var sub struct {
		ID          string
		TenantID    string
		Plan        string
		Status      string
		MaxDevices  int
		EndDate     sql.NullTime
		TrialEndsAt sql.NullTime
		Features    []byte
	}

	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, plan, status, max_devices,
		       end_date, trial_ends_at, features
		FROM tenant_subscriptions
		WHERE license_key = $1
		LIMIT 1
	`, req.LicenseKey).Scan(
		&sub.ID, &sub.TenantID, &sub.Plan, &sub.Status,
		&sub.MaxDevices, &sub.EndDate, &sub.TrialEndsAt, &sub.Features,
	)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "License key not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to validate license")
		return
	}

	// Count active devices for this tenant
	var usedDevices int
	m.db.QueryRowContext(r.Context(), `
		SELECT COUNT(*) FROM device_registrations
		WHERE tenant_id = $1 AND status = 'active' AND is_deleted = FALSE
	`, sub.TenantID).Scan(&usedDevices)

	// Determine validity
	isValid := sub.Status == "active" || sub.Status == "trial"
	if sub.EndDate.Valid && sub.EndDate.Time.Before(time.Now()) {
		isValid = false
	}
	if sub.Status == "trial" && sub.TrialEndsAt.Valid && sub.TrialEndsAt.Time.Before(time.Now()) {
		isValid = false
	}

	var flags FeatureFlags
	if len(sub.Features) > 0 {
		json.Unmarshal(sub.Features, &flags) //nolint: ignore error - use zero value on failure
	}
	flags.MaxDevices = sub.MaxDevices

	var expiresAt *time.Time
	if sub.EndDate.Valid {
		t := sub.EndDate.Time
		expiresAt = &t
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"valid":        isValid,
		"plan":         sub.Plan,
		"status":       sub.Status,
		"max_devices":  sub.MaxDevices,
		"used_devices": usedDevices,
		"expires_at":   expiresAt,
		"features":     flags,
	})
}

// handleActivate activates or links a license key to a tenant.
// POST /api/v1/licenses/activate
func (m *Module) handleActivate(w http.ResponseWriter, r *http.Request) {
	var req struct {
		LicenseKey string `json:"license_key"`
		TenantID   string `json:"tenant_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.LicenseKey == "" || req.TenantID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "license_key and tenant_id are required")
		return
	}

	// Check the license exists and is not already bound to another tenant
	var existingTenantID sql.NullString
	var status string
	err := m.db.QueryRowContext(r.Context(), `
		SELECT tenant_id, status FROM tenant_subscriptions WHERE license_key = $1
	`, req.LicenseKey).Scan(&existingTenantID, &status)

	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "License key not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to look up license")
		return
	}

	if existingTenantID.Valid && existingTenantID.String != "" && existingTenantID.String != req.TenantID {
		response.Error(w, http.StatusConflict, "CONFLICT", "License key is already activated for another tenant")
		return
	}

	// Activate: bind tenant and set status to active
	_, err = m.db.ExecContext(r.Context(), `
		UPDATE tenant_subscriptions
		SET tenant_id = $1, status = 'active', start_date = NOW(), updated_at = NOW()
		WHERE license_key = $2
	`, req.TenantID, req.LicenseKey)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to activate license")
		return
	}

	// Return the updated subscription
	var sub Subscription
	var endDate sql.NullTime
	var trialEndsAt sql.NullTime

	m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, license_key, plan, status, start_date, end_date, trial_ends_at, created_at, updated_at
		FROM tenant_subscriptions WHERE license_key = $1
	`, req.LicenseKey).Scan(
		&sub.ID, &sub.TenantID, &sub.LicenseID, &sub.Plan, &sub.Status,
		&sub.StartDate, &endDate, &trialEndsAt,
		&sub.CreatedAt, &sub.UpdatedAt,
	)
	if endDate.Valid {
		t := endDate.Time
		sub.EndDate = &t
	}
	if trialEndsAt.Valid {
		t := trialEndsAt.Time
		sub.TrialEndsAt = &t
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"activated":    true,
		"subscription": sub,
	})
}

// handleGetFeatures returns the feature flags for the authenticated tenant's subscription.
// GET /api/v1/licenses/features
func (m *Module) handleGetFeatures(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		// Return default feature flags for unauthenticated calls (used by POS before login)
		response.JSON(w, http.StatusOK, defaultFeatureFlags("starter"))
		return
	}

	var plan string
	var featuresJSON []byte
	var status string

	err := m.db.QueryRowContext(r.Context(), `
		SELECT plan, status, features
		FROM tenant_subscriptions
		WHERE tenant_id = $1
		ORDER BY created_at DESC
		LIMIT 1
	`, tenantID).Scan(&plan, &status, &featuresJSON)

	if err == sql.ErrNoRows {
		// No subscription found — return trial defaults
		response.JSON(w, http.StatusOK, defaultFeatureFlags("trial"))
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch features")
		return
	}

	var flags FeatureFlags
	if len(featuresJSON) > 0 {
		json.Unmarshal(featuresJSON, &flags) //nolint: ignore error
	} else {
		flags = defaultFeatureFlags(plan)
	}

	response.JSON(w, http.StatusOK, flags)
}

// defaultFeatureFlags returns sensible defaults based on plan name.
func defaultFeatureFlags(plan string) FeatureFlags {
	switch plan {
	case "enterprise":
		return FeatureFlags{
			MaxDevices: 50, MaxUsers: 100,
			CloudSync: true, CloudReports: true, MultiFloor: true,
			KitchenDisplay: true, CustomerDisplay: true,
			ERPNextBridge: true, FiscalIntegration: true,
			APIAccess: true, WhiteLabel: true,
		}
	case "professional":
		return FeatureFlags{
			MaxDevices: 10, MaxUsers: 30,
			CloudSync: true, CloudReports: true, MultiFloor: true,
			KitchenDisplay: true, CustomerDisplay: false,
			ERPNextBridge: false, FiscalIntegration: false,
			APIAccess: true, WhiteLabel: false,
		}
	default: // starter / trial
		return FeatureFlags{
			MaxDevices: 3, MaxUsers: 10,
			CloudSync: true, CloudReports: true, MultiFloor: false,
			KitchenDisplay: true, CustomerDisplay: false,
			ERPNextBridge: false, FiscalIntegration: false,
			APIAccess: false, WhiteLabel: false,
		}
	}
}
