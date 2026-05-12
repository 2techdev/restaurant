package partner

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

type editionDTO struct {
	ID            string          `json:"id"`
	Code          string          `json:"code"`
	Name          string          `json:"name"`
	Features      json.RawMessage `json:"features"`
	MaxStores     *int            `json:"max_stores,omitempty"`
	MaxDevices    *int            `json:"max_devices,omitempty"`
	PriceChfMonth float64         `json:"price_chf_month"`
	IsActive      bool            `json:"is_active"`
	CreatedAt     time.Time       `json:"created_at"`
}

func (m *Module) handleEditionList(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, ""); !ok {
		return
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, code, name, features, max_stores, max_devices,
		       price_chf_month, is_active, created_at
		  FROM editions
		 ORDER BY price_chf_month ASC, name
	`)
	if err != nil {
		slog.Error("partner: edition list", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list editions")
		return
	}
	defer rows.Close()
	out := []editionDTO{}
	for rows.Next() {
		var e editionDTO
		var maxStores, maxDevices sql.NullInt32
		if err := rows.Scan(&e.ID, &e.Code, &e.Name, &e.Features,
			&maxStores, &maxDevices, &e.PriceChfMonth, &e.IsActive,
			&e.CreatedAt); err != nil {
			continue
		}
		if maxStores.Valid {
			v := int(maxStores.Int32)
			e.MaxStores = &v
		}
		if maxDevices.Valid {
			v := int(maxDevices.Int32)
			e.MaxDevices = &v
		}
		out = append(out, e)
	}
	response.JSON(w, http.StatusOK, map[string]any{"data": out})
}

type editionUpsertRequest struct {
	Code          string          `json:"code"`
	Name          string          `json:"name"`
	Features      json.RawMessage `json:"features"`
	MaxStores     *int            `json:"max_stores,omitempty"`
	MaxDevices    *int            `json:"max_devices,omitempty"`
	PriceChfMonth *float64        `json:"price_chf_month,omitempty"`
	IsActive      *bool           `json:"is_active,omitempty"`
}

func (m *Module) handleEditionCreate(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, "OPERATOR"); !ok {
		return
	}
	var req editionUpsertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	req.Code = strings.TrimSpace(req.Code)
	req.Name = strings.TrimSpace(req.Name)
	if req.Code == "" || req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "code and name required")
		return
	}
	features := req.Features
	if len(features) == 0 {
		features = json.RawMessage(`{}`)
	}
	price := 0.0
	if req.PriceChfMonth != nil {
		price = *req.PriceChfMonth
	}
	var id string
	err := m.db.QueryRowContext(r.Context(), `
		INSERT INTO editions (code, name, features, max_stores, max_devices, price_chf_month, is_active)
		VALUES ($1, $2, $3::jsonb, $4, $5, $6, COALESCE($7, true))
		RETURNING id
	`, req.Code, req.Name, string(features), req.MaxStores, req.MaxDevices, price, req.IsActive).Scan(&id)
	if err != nil {
		if strings.Contains(err.Error(), "editions_code_key") {
			response.Error(w, http.StatusConflict, "DUPLICATE", "code already exists")
			return
		}
		slog.Error("partner: edition create", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create edition")
		return
	}
	response.JSON(w, http.StatusCreated, map[string]string{"id": id})
}

func (m *Module) handleEditionUpdate(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, "OPERATOR"); !ok {
		return
	}
	id := r.PathValue("id")
	var req editionUpsertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	features := req.Features
	if len(features) == 0 {
		features = json.RawMessage(`null`)
	}
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE editions SET
		  name            = COALESCE(NULLIF($2,''), name),
		  features        = COALESCE(NULLIF($3,'null')::jsonb, features),
		  max_stores      = $4,
		  max_devices     = $5,
		  price_chf_month = COALESCE($6, price_chf_month),
		  is_active       = COALESCE($7, is_active),
		  updated_at      = NOW()
		WHERE id = $1
	`, id, strings.TrimSpace(req.Name), string(features), req.MaxStores, req.MaxDevices, req.PriceChfMonth, req.IsActive)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Edition not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

func (m *Module) handleEditionDelete(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, "OPERATOR"); !ok {
		return
	}
	id := r.PathValue("id")
	// Refuse hard delete when in use; flip is_active=false instead.
	var inUse int
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT COUNT(*) FROM tenants WHERE current_edition_id = $1`, id).Scan(&inUse)
	if inUse > 0 {
		_, err := m.db.ExecContext(r.Context(),
			`UPDATE editions SET is_active=false, updated_at=NOW() WHERE id=$1`, id)
		if err != nil {
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "deactivate failed")
			return
		}
		response.JSON(w, http.StatusOK, map[string]string{"status": "deactivated_in_use"})
		return
	}
	res, err := m.db.ExecContext(r.Context(), `DELETE FROM editions WHERE id=$1`, id)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Edition not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
