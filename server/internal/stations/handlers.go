package stations

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

type Station struct {
	ID        string  `json:"id"`
	Name      string  `json:"name"`
	Color     string  `json:"color"`
	PrinterID *string `json:"printer_id,omitempty"`
	SortOrder int     `json:"sort_order"`
	IsActive  bool    `json:"is_active"`
}

func (m *Module) handleList(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if !uuid.IsValid(tenantID) {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, name, color, printer_id::TEXT, sort_order, is_active
		FROM stations
		WHERE tenant_id = $1 AND is_deleted = FALSE
		ORDER BY sort_order, name
	`, tenantID)
	if err != nil {
		slog.Error("stations: list", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list stations")
		return
	}
	defer rows.Close()

	out := make([]Station, 0)
	for rows.Next() {
		var s Station
		var printerID sql.NullString
		if err := rows.Scan(&s.ID, &s.Name, &s.Color, &printerID, &s.SortOrder, &s.IsActive); err != nil {
			continue
		}
		if printerID.Valid {
			v := printerID.String
			s.PrinterID = &v
		}
		out = append(out, s)
	}
	response.JSON(w, http.StatusOK, out)
}

type upsertRequest struct {
	Name      string  `json:"name"`
	Color     *string `json:"color"`
	PrinterID *string `json:"printer_id"`
	SortOrder *int    `json:"sort_order"`
	IsActive  *bool   `json:"is_active"`
}

func (m *Module) handleCreate(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if !uuid.IsValid(tenantID) {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	var req upsertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "name required")
		return
	}

	id := uuid.New()
	color := "#4f46e5"
	if req.Color != nil && *req.Color != "" {
		color = *req.Color
	}
	sortOrder := 0
	if req.SortOrder != nil {
		sortOrder = *req.SortOrder
	}
	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}
	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO stations (id, tenant_id, name, color, printer_id, sort_order, is_active)
		VALUES ($1, $2, $3, $4, NULLIF($5, '')::UUID, $6, $7)
	`, id, tenantID, req.Name, color, ptrStr(req.PrinterID), sortOrder, isActive)
	if err != nil {
		slog.Error("stations: create", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create station")
		return
	}
	m.writeOne(w, r, tenantID, id)
}

func (m *Module) handleUpdate(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	id := r.PathValue("id")
	if !uuid.IsValid(tenantID) || !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid tenant or id")
		return
	}
	var req upsertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	// printer_id: nil pointer = leave current value; "" = NULL; uuid = set.
	var printerParam any
	switch {
	case req.PrinterID == nil:
		printerParam = nil
	case *req.PrinterID == "":
		printerParam = sql.NullString{}
	default:
		printerParam = *req.PrinterID
	}

	result, err := m.db.ExecContext(r.Context(), `
		UPDATE stations SET
			name = CASE WHEN $3 = '' THEN name ELSE $3 END,
			color = COALESCE($4, color),
			printer_id = CASE
				WHEN $5::TEXT IS NULL THEN printer_id
				WHEN $5::TEXT = '' THEN NULL
				ELSE $5::UUID
			END,
			sort_order = COALESCE($6, sort_order),
			is_active = COALESCE($7, is_active),
			updated_at = NOW()
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = FALSE
	`, id, tenantID, req.Name, req.Color, printerParam, req.SortOrder, req.IsActive)
	if err != nil {
		slog.Error("stations: update", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update station")
		return
	}
	if n, _ := result.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Station not found")
		return
	}
	m.writeOne(w, r, tenantID, id)
}

func (m *Module) handleDelete(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	id := r.PathValue("id")
	if !uuid.IsValid(tenantID) || !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid tenant or id")
		return
	}
	result, err := m.db.ExecContext(r.Context(), `
		UPDATE stations SET is_deleted = TRUE, updated_at = NOW()
		WHERE id = $1 AND tenant_id = $2
	`, id, tenantID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete station")
		return
	}
	if n, _ := result.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Station not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (m *Module) writeOne(w http.ResponseWriter, r *http.Request, tenantID, id string) {
	var s Station
	var printerID sql.NullString
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, name, color, printer_id::TEXT, sort_order, is_active
		FROM stations WHERE id = $1 AND tenant_id = $2
	`, id, tenantID).Scan(&s.ID, &s.Name, &s.Color, &printerID, &s.SortOrder, &s.IsActive)
	if err != nil {
		slog.Error("stations: writeOne", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load station")
		return
	}
	if printerID.Valid {
		v := printerID.String
		s.PrinterID = &v
	}
	response.JSON(w, http.StatusOK, s)
}

func ptrStr(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}
