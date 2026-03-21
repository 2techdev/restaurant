package licenses

import (
	"encoding/json"
	"net/http"

	"github.com/gastrocore/server/internal/shared/response"
)

// handleValidate validates a license token and returns its status.
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

	// TODO: Look up license by key
	// TODO: Verify expiry, device count, etc.
	// TODO: Return validation result

	response.JSON(w, http.StatusOK, map[string]any{
		"valid":        true,
		"plan":         "professional",
		"max_devices":  5,
		"used_devices": 1,
		"expires_at":   nil,
		"features":     FeatureFlags{},
	})
}

// handleActivate activates a subscription for a tenant.
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

	// TODO: Validate license key
	// TODO: Create or update subscription record
	// TODO: Return activation result

	response.JSON(w, http.StatusOK, map[string]any{
		"activated": true,
		"subscription": Subscription{},
	})
}

// handleGetFeatures returns the feature flags for the authenticated tenant.
// GET /api/v1/licenses/features
func (m *Module) handleGetFeatures(w http.ResponseWriter, r *http.Request) {
	// TODO: Extract tenant_id from context
	// TODO: Look up subscription and plan
	// TODO: Return feature flags

	response.JSON(w, http.StatusOK, FeatureFlags{
		MaxDevices:       5,
		MaxUsers:         20,
		CloudSync:        true,
		CloudReports:     true,
		MultiFloor:       true,
		KitchenDisplay:   true,
		CustomerDisplay:  false,
		ERPNextBridge:    false,
		FiscalIntegration: false,
		APIAccess:        true,
		WhiteLabel:       false,
	})
}
