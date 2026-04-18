package tables

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

type Table struct {
	ID             string   `json:"id"`
	Name           string   `json:"name"`
	Capacity       int      `json:"capacity"`
	Shape          string   `json:"shape"`
	PosX           float64  `json:"pos_x"`
	PosY           float64  `json:"pos_y"`
	Width          float64  `json:"width"`
	Height         float64  `json:"height"`
	Status         string   `json:"status"`
	Zone           *string  `json:"zone,omitempty"`
	FloorID        *string  `json:"floor_id,omitempty"`
	CurrentOrderID *string  `json:"current_order_id,omitempty"`
	CurrentTotal   *int64   `json:"current_total,omitempty"`
}

func (m *Module) handleList(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if !uuid.IsValid(tenantID) {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT rt.id, rt.name, rt.capacity, rt.shape,
		       rt.pos_x, rt.pos_y, rt.width, rt.height,
		       rt.status, rt.zone, rt.floor_id::TEXT,
		       rt.current_order_id::TEXT,
		       (SELECT total FROM tickets t WHERE t.id = rt.current_order_id AND t.is_deleted = FALSE) AS current_total
		FROM restaurant_tables rt
		WHERE rt.tenant_id = $1 AND rt.is_deleted = FALSE
		ORDER BY rt.zone NULLS FIRST, rt.name
	`, tenantID)
	if err != nil {
		slog.Error("tables: list", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list tables")
		return
	}
	defer rows.Close()

	out := make([]Table, 0)
	for rows.Next() {
		var t Table
		var zone, floorID, currentOrderID sql.NullString
		var currentTotal sql.NullInt64
		if err := rows.Scan(
			&t.ID, &t.Name, &t.Capacity, &t.Shape,
			&t.PosX, &t.PosY, &t.Width, &t.Height,
			&t.Status, &zone, &floorID,
			&currentOrderID, &currentTotal,
		); err != nil {
			continue
		}
		if zone.Valid {
			s := zone.String
			t.Zone = &s
		}
		if floorID.Valid {
			s := floorID.String
			t.FloorID = &s
		}
		if currentOrderID.Valid {
			s := currentOrderID.String
			t.CurrentOrderID = &s
		}
		if currentTotal.Valid {
			v := currentTotal.Int64
			t.CurrentTotal = &v
		}
		out = append(out, t)
	}

	response.JSON(w, http.StatusOK, out)
}

type upsertRequest struct {
	Name     string   `json:"name"`
	Capacity int      `json:"capacity"`
	Shape    string   `json:"shape"`
	PosX     *float64 `json:"pos_x"`
	PosY     *float64 `json:"pos_y"`
	Width    *float64 `json:"width"`
	Height   *float64 `json:"height"`
	Status   *string  `json:"status"`
	Zone     *string  `json:"zone"`
	FloorID  *string  `json:"floor_id"`
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
	if req.Capacity < 1 {
		req.Capacity = 2
	}
	if req.Shape == "" {
		req.Shape = "rectangle"
	}

	id := uuid.New()
	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO restaurant_tables (
			id, tenant_id, floor_id, name, capacity, shape,
			pos_x, pos_y, width, height, status, zone
		) VALUES (
			$1, $2, NULLIF($3,'')::UUID, $4, $5, $6,
			COALESCE($7, 0), COALESCE($8, 0),
			COALESCE($9, 100), COALESCE($10, 100),
			COALESCE($11, 'available'), NULLIF($12, '')
		)
	`,
		id, tenantID, nullableStr(req.FloorID),
		req.Name, req.Capacity, req.Shape,
		req.PosX, req.PosY, req.Width, req.Height,
		req.Status, nullableStr(req.Zone),
	)
	if err != nil {
		slog.Error("tables: create", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create table")
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

	result, err := m.db.ExecContext(r.Context(), `
		UPDATE restaurant_tables SET
			name = CASE WHEN $3 = '' THEN name ELSE $3 END,
			capacity = COALESCE(NULLIF($4, 0), capacity),
			shape = CASE WHEN $5 = '' THEN shape ELSE $5 END,
			pos_x = COALESCE($6, pos_x),
			pos_y = COALESCE($7, pos_y),
			width = COALESCE($8, width),
			height = COALESCE($9, height),
			status = COALESCE($10, status),
			zone = COALESCE($11, zone),
			floor_id = CASE WHEN $12::TEXT IS NULL THEN floor_id ELSE NULLIF($12, '')::UUID END,
			updated_at = NOW()
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = FALSE
	`,
		id, tenantID,
		req.Name, req.Capacity, req.Shape,
		req.PosX, req.PosY, req.Width, req.Height,
		req.Status, req.Zone, nullableStr(req.FloorID),
	)
	if err != nil {
		slog.Error("tables: update", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update table")
		return
	}
	if n, _ := result.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Table not found")
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

	// Only allow deletion when the table is currently unoccupied.
	var status string
	err := m.db.QueryRowContext(r.Context(),
		`SELECT status FROM restaurant_tables WHERE id=$1 AND tenant_id=$2 AND is_deleted=FALSE`,
		id, tenantID,
	).Scan(&status)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Table not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch table")
		return
	}
	if status != "available" && status != "free" {
		response.Error(w, http.StatusConflict, "TABLE_BUSY", "Only free tables can be deleted")
		return
	}

	_, err = m.db.ExecContext(r.Context(),
		`UPDATE restaurant_tables SET is_deleted=TRUE, updated_at=NOW()
		 WHERE id=$1 AND tenant_id=$2`,
		id, tenantID,
	)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete table")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (m *Module) writeOne(w http.ResponseWriter, r *http.Request, tenantID, id string) {
	var t Table
	var zone, floorID, currentOrderID sql.NullString
	var currentTotal sql.NullInt64
	err := m.db.QueryRowContext(r.Context(), `
		SELECT rt.id, rt.name, rt.capacity, rt.shape,
		       rt.pos_x, rt.pos_y, rt.width, rt.height,
		       rt.status, rt.zone, rt.floor_id::TEXT,
		       rt.current_order_id::TEXT,
		       (SELECT total FROM tickets ti WHERE ti.id = rt.current_order_id AND ti.is_deleted = FALSE)
		FROM restaurant_tables rt
		WHERE rt.id = $1 AND rt.tenant_id = $2
	`, id, tenantID).Scan(
		&t.ID, &t.Name, &t.Capacity, &t.Shape,
		&t.PosX, &t.PosY, &t.Width, &t.Height,
		&t.Status, &zone, &floorID,
		&currentOrderID, &currentTotal,
	)
	if err != nil {
		slog.Error("tables: writeOne", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load table")
		return
	}
	if zone.Valid {
		s := zone.String
		t.Zone = &s
	}
	if floorID.Valid {
		s := floorID.String
		t.FloorID = &s
	}
	if currentOrderID.Valid {
		s := currentOrderID.String
		t.CurrentOrderID = &s
	}
	if currentTotal.Valid {
		v := currentTotal.Int64
		t.CurrentTotal = &v
	}
	response.JSON(w, http.StatusOK, t)
}

// nullableStr returns "" when the pointer is nil; otherwise its value. Used
// with NULLIF($n, '')::UUID to map "" → NULL for optional UUID columns.
func nullableStr(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
