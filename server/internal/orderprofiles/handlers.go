package orderprofiles

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"sort"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// resolveTenant returns the JWT-bound tenant ID, or "" when missing.
// The route file requires JWT for everything, so the empty-string path
// short-circuits to a 401.
func resolveTenant(r *http.Request) string {
	return middleware.GetTenantID(r.Context())
}

func (m *Module) handleList(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	profiles, err := m.listProfiles(r.Context(), tenantID)
	if err != nil {
		slog.Error("order-profiles: list", "error", err, "tenant", tenantID)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list order profiles")
		return
	}
	response.JSON(w, http.StatusOK, map[string]any{
		"success": true,
		"data": map[string]any{
			"profiles": profiles,
		},
	})
}

func (m *Module) handleGet(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	p, err := m.getProfile(r.Context(), tenantID, id)
	if err != nil {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Order profile not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]any{
		"success": true,
		"data":    p,
	})
}

// profileWriteReq is a thin DTO so we can validate user input before
// touching the store layer.  Fields are intentionally permissive on
// missing optionals — the store fills defaults.
type profileWriteReq struct {
	Code             string            `json:"code"`
	Name             string            `json:"name"`
	NameTranslations map[string]string `json:"nameTranslations"`
	Description      string            `json:"description"`
	IsActive         *bool             `json:"isActive"`
	IsDefault        bool              `json:"isDefault"`
	Priority         int               `json:"priority"`
	Settings         ProfileSettings   `json:"settings"`
	PricingRules     []PricingRule     `json:"pricingRules"`
}

func (m *Module) handleCreate(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	role := middleware.GetRole(r.Context())
	if role != "admin" && role != "brand_manager" && role != "manager" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Admin or manager role required")
		return
	}
	var req profileWriteReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	if req.Code == "" || req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "code and name are required")
		return
	}
	p := profileFromReq(req)
	out, err := m.upsertProfile(r.Context(), tenantID, p)
	if err != nil {
		slog.Error("order-profiles: create", "error", err, "tenant", tenantID)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create order profile")
		return
	}
	m.notifyChanged(r.Context(), tenantID)
	response.JSON(w, http.StatusCreated, map[string]any{
		"success": true,
		"data":    out,
	})
}

func (m *Module) handleUpdate(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	role := middleware.GetRole(r.Context())
	if role != "admin" && role != "brand_manager" && role != "manager" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Admin or manager role required")
		return
	}
	id := r.PathValue("id")
	var req profileWriteReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	if req.Code == "" || req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "code and name are required")
		return
	}
	p := profileFromReq(req)
	p.ID = id
	out, err := m.upsertProfile(r.Context(), tenantID, p)
	if err != nil {
		if errors.Is(err, errProfileNotFound) {
			response.Error(w, http.StatusNotFound, "NOT_FOUND", "Order profile not found")
			return
		}
		slog.Error("order-profiles: update", "error", err, "tenant", tenantID, "id", id)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update order profile")
		return
	}
	m.notifyChanged(r.Context(), tenantID)
	response.JSON(w, http.StatusOK, map[string]any{
		"success": true,
		"data":    out,
	})
}

func (m *Module) handleDelete(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	role := middleware.GetRole(r.Context())
	if role != "admin" && role != "brand_manager" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Admin role required to delete")
		return
	}
	id := r.PathValue("id")
	if err := m.deleteProfile(r.Context(), tenantID, id); err != nil {
		if errors.Is(err, errProfileNotFound) {
			response.Error(w, http.StatusNotFound, "NOT_FOUND",
				"Profile not found (or it is the default and cannot be deleted)")
			return
		}
		slog.Error("order-profiles: delete", "error", err, "tenant", tenantID, "id", id)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete order profile")
		return
	}
	m.notifyChanged(r.Context(), tenantID)
	w.WriteHeader(http.StatusNoContent)
}

// handleActive — what's active right now for this tenant.  The handler
// honours the optional `at` query param (RFC3339) so the backoffice "Test
// Mode" preview can ask "if it were 16:30 today, which profile would win?".
// Without `at` the current server clock is used.
func (m *Module) handleActive(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	at := time.Now()
	if q := r.URL.Query().Get("at"); q != "" {
		if t, err := time.Parse(time.RFC3339, q); err == nil {
			at = t
		}
	}
	profiles, err := m.listProfiles(r.Context(), tenantID)
	if err != nil {
		slog.Error("order-profiles: active list", "error", err, "tenant", tenantID)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to compute active profiles")
		return
	}
	out := computeActive(profiles, at, tenantID)
	response.JSON(w, http.StatusOK, map[string]any{
		"success": true,
		"data":    out,
	})
}

// computeActive evaluates the schedule for every profile and returns the
// summary DTO.  Public-ish so tests can drive it without a DB.
func computeActive(profiles []*Profile, at time.Time, tenantID string) ActiveProfileSummary {
	out := ActiveProfileSummary{
		TenantID:   tenantID,
		ComputedAt: at.UTC(),
		ActiveIDs:  []string{},
	}
	var defaultProfile *Profile
	var matched []*Profile
	for _, p := range profiles {
		if p.IsDefault {
			id := p.ID
			out.DefaultID = &id
			defaultProfile = p
		}
		if ProfileMatchesNow(p, at) {
			matched = append(matched, p)
			out.ActiveIDs = append(out.ActiveIDs, p.ID)
		}
	}
	sort.Strings(out.ActiveIDs)
	winner := chooseWinner(matched, defaultProfile)
	if winner != nil {
		id := winner.ID
		out.WinnerID = &id
		out.WinnerProfile = winner
	}
	return out
}

func profileFromReq(req profileWriteReq) *Profile {
	active := true
	if req.IsActive != nil {
		active = *req.IsActive
	}
	if req.NameTranslations == nil {
		req.NameTranslations = map[string]string{}
	}
	if req.Settings.Schedule == nil {
		req.Settings.Schedule = []ScheduleSlot{}
	}
	if req.PricingRules == nil {
		req.PricingRules = []PricingRule{}
	}
	return &Profile{
		Code:             req.Code,
		Name:             req.Name,
		NameTranslations: req.NameTranslations,
		Description:      req.Description,
		IsActive:         active,
		IsDefault:        req.IsDefault,
		Priority:         req.Priority,
		Settings:         req.Settings,
		PricingRules:     req.PricingRules,
	}
}
