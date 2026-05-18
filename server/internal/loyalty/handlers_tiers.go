package loyalty

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

func resolveTenant(r *http.Request) string {
	if t := middleware.GetTenantID(r.Context()); t != "" {
		return t
	}
	return r.URL.Query().Get("tenant_id")
}

func canManageLoyalty(role string) bool {
	switch role {
	case "OWNER", "MANAGER", "HQ_ADMIN", "HQ_MANAGER":
		return true
	}
	return false
}

// ---------------------------------------------------------------------------
// GET /api/v1/loyalty/tiers
// ---------------------------------------------------------------------------

func (m *Module) handleListTiers(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, code, name, name_translations, min_points, max_points,
		       multiplier, benefits, color_hex, sort_order, is_active,
		       created_at, updated_at
		FROM loyalty_tiers
		WHERE tenant_id = $1
		ORDER BY sort_order ASC, min_points ASC
	`, tenantID)
	if err != nil {
		slog.Error("loyalty: list tiers", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list tiers")
		return
	}
	defer rows.Close()
	out := make([]Tier, 0)
	for rows.Next() {
		var t Tier
		var maxPoints sql.NullInt64
		var color sql.NullString
		if err := rows.Scan(&t.ID, &t.TenantID, &t.Code, &t.Name, &t.NameTranslations,
			&t.MinPoints, &maxPoints, &t.Multiplier, &t.Benefits, &color,
			&t.SortOrder, &t.IsActive, &t.CreatedAt, &t.UpdatedAt); err != nil {
			slog.Warn("loyalty: scan tier", "error", err)
			continue
		}
		if maxPoints.Valid {
			v := int(maxPoints.Int64)
			t.MaxPoints = &v
		}
		if color.Valid {
			t.ColorHex = &color.String
		}
		out = append(out, t)
	}
	response.JSON(w, http.StatusOK, map[string]any{"tiers": out})
}

type tierReq struct {
	Code             string          `json:"code"`
	Name             string          `json:"name"`
	NameTranslations json.RawMessage `json:"name_translations"`
	MinPoints        int             `json:"min_points"`
	MaxPoints        *int            `json:"max_points"`
	Multiplier       float64         `json:"multiplier"`
	Benefits         json.RawMessage `json:"benefits"`
	ColorHex         *string         `json:"color_hex"`
	SortOrder        int             `json:"sort_order"`
	IsActive         *bool           `json:"is_active"`
}

func (m *Module) handleCreateTier(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" || !canManageLoyalty(middleware.GetRole(r.Context())) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
		return
	}
	var req tierReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if req.Code == "" || req.Name == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "code and name required")
		return
	}
	if req.Multiplier <= 0 {
		req.Multiplier = 1.0
	}
	if len(req.NameTranslations) == 0 {
		req.NameTranslations = json.RawMessage(`{}`)
	}
	if len(req.Benefits) == 0 {
		req.Benefits = json.RawMessage(`[]`)
	}
	id := uuid.New()
	active := true
	if req.IsActive != nil {
		active = *req.IsActive
	}
	now := time.Now().UTC()
	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO loyalty_tiers (id, tenant_id, code, name, name_translations,
		                           min_points, max_points, multiplier, benefits,
		                           color_hex, sort_order, is_active, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5::jsonb,$6,$7,$8,$9::jsonb,$10,$11,$12,$13,$13)
	`, id, tenantID, req.Code, req.Name, string(req.NameTranslations),
		req.MinPoints, req.MaxPoints, req.Multiplier, string(req.Benefits),
		req.ColorHex, req.SortOrder, active, now)
	if err != nil {
		slog.Error("loyalty: create tier", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create tier")
		return
	}
	response.Created(w, map[string]any{"id": id})
}

func (m *Module) handleUpdateTier(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" || !canManageLoyalty(middleware.GetRole(r.Context())) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
		return
	}
	id := r.PathValue("id")
	if id == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "id required")
		return
	}
	var req tierReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if len(req.NameTranslations) == 0 {
		req.NameTranslations = json.RawMessage(`{}`)
	}
	if len(req.Benefits) == 0 {
		req.Benefits = json.RawMessage(`[]`)
	}
	active := true
	if req.IsActive != nil {
		active = *req.IsActive
	}
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE loyalty_tiers
		SET name = $1,
		    name_translations = $2::jsonb,
		    min_points = $3,
		    max_points = $4,
		    multiplier = $5,
		    benefits = $6::jsonb,
		    color_hex = $7,
		    sort_order = $8,
		    is_active = $9,
		    updated_at = NOW()
		WHERE id = $10 AND tenant_id = $11
	`, req.Name, string(req.NameTranslations), req.MinPoints, req.MaxPoints,
		req.Multiplier, string(req.Benefits), req.ColorHex, req.SortOrder, active,
		id, tenantID)
	if err != nil {
		slog.Error("loyalty: update tier", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update tier")
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Tier not found")
		return
	}
	response.NoContent(w)
}

func (m *Module) handleDeleteTier(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" || !canManageLoyalty(middleware.GetRole(r.Context())) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
		return
	}
	id := r.PathValue("id")
	res, err := m.db.ExecContext(r.Context(),
		`DELETE FROM loyalty_tiers WHERE id = $1 AND tenant_id = $2`, id, tenantID)
	if err != nil {
		slog.Error("loyalty: delete tier", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete tier")
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Tier not found")
		return
	}
	response.NoContent(w)
}
