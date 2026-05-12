package partner

import (
	"database/sql"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

// Brand is the operator-facing alias for `organizations` — chain HQ.
type brandDTO struct {
	ID         string    `json:"id"`
	Name       string    `json:"name"`
	DealerID   *string   `json:"dealer_id,omitempty"`
	StoreCount int       `json:"store_count"`
	CreatedAt  time.Time `json:"created_at"`
}

func (m *Module) handleBrandList(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, ""); !ok {
		return
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT o.id, o.name, o.dealer_id::text, o.created_at,
		       (SELECT COUNT(*) FROM organization_memberships m WHERE m.organization_id = o.id)
		  FROM organizations o
		 WHERE o.deleted_at IS NULL
		 ORDER BY o.created_at DESC
	`)
	if err != nil {
		slog.Error("partner: brand list", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list brands")
		return
	}
	defer rows.Close()
	out := []brandDTO{}
	for rows.Next() {
		var b brandDTO
		var dealer sql.NullString
		if err := rows.Scan(&b.ID, &b.Name, &dealer, &b.CreatedAt, &b.StoreCount); err != nil {
			continue
		}
		if dealer.Valid && dealer.String != "" {
			s := dealer.String
			b.DealerID = &s
		}
		out = append(out, b)
	}
	response.JSON(w, http.StatusOK, map[string]any{"data": out})
}

type brandUpsertRequest struct {
	Name     string  `json:"name"`
	DealerID *string `json:"dealer_id,omitempty"`
}

func (m *Module) handleBrandCreate(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, "MANAGER"); !ok {
		return
	}
	var req brandUpsertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "Name required")
		return
	}
	var id string
	err := m.db.QueryRowContext(r.Context(), `
		INSERT INTO organizations (name, dealer_id, plan, status)
		VALUES ($1, NULLIF($2,'')::uuid, 'free', 'active')
		RETURNING id
	`, req.Name, deref(req.DealerID)).Scan(&id)
	if err != nil {
		slog.Error("partner: brand create", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create brand")
		return
	}
	response.JSON(w, http.StatusCreated, map[string]string{"id": id, "name": req.Name})
}

func (m *Module) handleBrandUpdate(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, "MANAGER"); !ok {
		return
	}
	id := r.PathValue("id")
	var req brandUpsertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE organizations
		   SET name      = COALESCE(NULLIF($2,''), name),
		       dealer_id = NULLIF($3,'')::uuid,
		       updated_at = NOW()
		 WHERE id = $1 AND deleted_at IS NULL
	`, id, strings.TrimSpace(req.Name), deref(req.DealerID))
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Brand not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

func (m *Module) handleBrandDelete(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, "OPERATOR"); !ok {
		return
	}
	id := r.PathValue("id")
	// Soft delete only — every brand has stores attached, hard delete would
	// cascade-orphan tenants and break audit trails.
	res, err := m.db.ExecContext(r.Context(),
		`UPDATE organizations SET deleted_at=NOW(), updated_at=NOW() WHERE id=$1 AND deleted_at IS NULL`, id)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Brand not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func deref(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

// suppress unused-import in this file when handlers.go is split later.
var _ = errors.New
