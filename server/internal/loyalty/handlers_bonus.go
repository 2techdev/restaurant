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

func (m *Module) handleListBonusCampaigns(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, name, description, multiplier, starts_at, ends_at, is_active, created_at, updated_at
		FROM loyalty_bonus_campaigns
		WHERE tenant_id = $1
		ORDER BY starts_at DESC
	`, tenantID)
	if err != nil {
		slog.Error("loyalty: list bonus campaigns", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list bonus campaigns")
		return
	}
	defer rows.Close()
	out := make([]BonusCampaign, 0)
	for rows.Next() {
		var c BonusCampaign
		var desc sql.NullString
		if err := rows.Scan(&c.ID, &c.TenantID, &c.Name, &desc, &c.Multiplier,
			&c.StartsAt, &c.EndsAt, &c.IsActive, &c.CreatedAt, &c.UpdatedAt); err != nil {
			continue
		}
		if desc.Valid {
			c.Description = &desc.String
		}
		out = append(out, c)
	}
	response.JSON(w, http.StatusOK, map[string]any{"campaigns": out})
}

type bonusReq struct {
	Name        string     `json:"name"`
	Description *string    `json:"description"`
	Multiplier  float64    `json:"multiplier"`
	StartsAt    time.Time  `json:"starts_at"`
	EndsAt      time.Time  `json:"ends_at"`
	IsActive    *bool      `json:"is_active"`
}

func (m *Module) handleCreateBonusCampaign(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" || !canManageLoyalty(middleware.GetRole(r.Context())) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
		return
	}
	var req bonusReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if req.Name == "" || req.Multiplier <= 0 || !req.EndsAt.After(req.StartsAt) {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "name, multiplier > 0, ends_at > starts_at required")
		return
	}
	active := true
	if req.IsActive != nil {
		active = *req.IsActive
	}
	id := uuid.New()
	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO loyalty_bonus_campaigns
		  (id, tenant_id, name, description, multiplier, starts_at, ends_at, is_active, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,NOW(),NOW())
	`, id, tenantID, req.Name, req.Description, req.Multiplier, req.StartsAt, req.EndsAt, active)
	if err != nil {
		slog.Error("loyalty: create bonus", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create campaign")
		return
	}
	response.Created(w, map[string]any{"id": id})
}

func (m *Module) handleUpdateBonusCampaign(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" || !canManageLoyalty(middleware.GetRole(r.Context())) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
		return
	}
	id := r.PathValue("id")
	var req bonusReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	active := true
	if req.IsActive != nil {
		active = *req.IsActive
	}
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE loyalty_bonus_campaigns
		SET name = $1, description = $2, multiplier = $3,
		    starts_at = $4, ends_at = $5, is_active = $6, updated_at = NOW()
		WHERE id = $7 AND tenant_id = $8
	`, req.Name, req.Description, req.Multiplier, req.StartsAt, req.EndsAt, active, id, tenantID)
	if err != nil {
		slog.Error("loyalty: update bonus", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update campaign")
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Campaign not found")
		return
	}
	response.NoContent(w)
}

func (m *Module) handleDeleteBonusCampaign(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" || !canManageLoyalty(middleware.GetRole(r.Context())) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
		return
	}
	id := r.PathValue("id")
	res, err := m.db.ExecContext(r.Context(),
		`DELETE FROM loyalty_bonus_campaigns WHERE id = $1 AND tenant_id = $2`, id, tenantID)
	if err != nil {
		slog.Error("loyalty: delete bonus", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete campaign")
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Campaign not found")
		return
	}
	response.NoContent(w)
}
