package license

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

// handleGenerate issues a new signed offline license token.
//
// POST /api/v1/license/generate
//
// In production this endpoint must be protected by an admin-level auth
// middleware. For the development server it is accessible without auth so
// that tokens can be generated during local testing.
func (m *Module) handleGenerate(w http.ResponseWriter, r *http.Request) {
	var req GenerateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY",
			"Request body must be valid JSON: "+err.Error())
		return
	}

	if req.BusinessID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR",
			"business_id is required")
		return
	}

	resp, err := m.svc.Generate(req)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "GENERATE_ERROR",
			err.Error())
		return
	}

	response.JSON(w, http.StatusOK, resp)
}

// handleValidate verifies an existing license token and returns its claims.
//
// POST /api/v1/license/validate
//
// Clients can call this to confirm a token's authenticity. The endpoint
// does NOT require a database round-trip — it only verifies the Ed25519
// signature and parses the embedded claims.
func (m *Module) handleValidate(w http.ResponseWriter, r *http.Request) {
	var req ValidateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY",
			"Request body must be valid JSON: "+err.Error())
		return
	}

	if req.Token == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR",
			"token is required")
		return
	}

	claims, err := m.svc.Validate(req.Token)
	if err != nil {
		response.JSON(w, http.StatusOK, ValidateResponse{
			Valid:  false,
			Error:  err.Error(),
		})
		return
	}

	expired := IsExpired(claims)
	response.JSON(w, http.StatusOK, ValidateResponse{
		Valid:    !expired,
		Claims:   claims,
		Expired:  expired,
	})
}

// handleStatus returns a summary of a token's current status, including
// whether it is expired and how many days remain.
//
// POST /api/v1/license/status
func (m *Module) handleStatus(w http.ResponseWriter, r *http.Request) {
	var req ValidateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY",
			"Request body must be valid JSON: "+err.Error())
		return
	}

	if req.Token == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR",
			"token is required")
		return
	}

	claims, err := m.svc.Validate(req.Token)
	if err != nil {
		response.JSON(w, http.StatusOK, map[string]any{
			"valid":   false,
			"error":   err.Error(),
		})
		return
	}

	exp, _ := time.Parse(time.RFC3339, claims.ExpiresAt)
	daysRemaining := 0
	if !exp.IsZero() {
		d := int(time.Until(exp).Hours() / 24)
		if d > 0 {
			daysRemaining = d
		}
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"valid":          !IsExpired(claims),
		"edition":        claims.Edition,
		"customer_name":  claims.CustomerName,
		"max_devices":    claims.MaxDevices,
		"features":       claims.Features,
		"expires_at":     claims.ExpiresAt,
		"days_remaining": daysRemaining,
		"expired":        IsExpired(claims),
	})
}
