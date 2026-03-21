package reservations

import (
	"context"
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

// handleListReservations returns reservations filtered by date and/or status.
// GET /api/v1/reservations?tenant_id=&date=&status=&from=&to=
func (m *Module) handleListReservations(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	tenantID := q.Get("tenant_id")
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}
	date := q.Get("date")   // YYYY-MM-DD; if empty returns all
	status := q.Get("status")
	from := q.Get("from")   // YYYY-MM-DD range start
	to := q.Get("to")       // YYYY-MM-DD range end

	query := `
		SELECT id, tenant_id, customer_name, phone, guest_count, table_id,
		       date, time, duration_minutes, status, notes, customer_id,
		       created_at, updated_at, is_deleted
		FROM reservations
		WHERE tenant_id = $1
		  AND is_deleted = false
		  AND ($2 = '' OR date = $2)
		  AND ($3 = '' OR status = $3)
		  AND ($4 = '' OR date >= $4)
		  AND ($5 = '' OR date <= $5)
		ORDER BY date ASC, time ASC
		LIMIT 500
	`

	rows, err := m.db.QueryContext(r.Context(), query, tenantID, date, status, from, to)
	if err != nil {
		slog.Error("reservations: list", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to query reservations")
		return
	}
	defer rows.Close()

	items := make([]Reservation, 0)
	for rows.Next() {
		res, err := scanReservation(rows)
		if err != nil {
			slog.Warn("reservations: scan", "error", err)
			continue
		}
		items = append(items, res)
	}
	if err := rows.Err(); err != nil {
		slog.Error("reservations: rows error", "error", err)
	}

	response.JSON(w, http.StatusOK, items)
}

// handleCreateReservation creates a new reservation.
// POST /api/v1/reservations
func (m *Module) handleCreateReservation(w http.ResponseWriter, r *http.Request) {
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	var req CreateReservationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_body", "invalid JSON")
		return
	}
	if req.ID == "" || req.CustomerName == "" || req.Date == "" || req.Time == "" {
		response.Error(w, http.StatusBadRequest, "validation_error", "id, customer_name, date, time required")
		return
	}
	if req.GuestCount <= 0 {
		req.GuestCount = 1
	}
	if req.DurationMins <= 0 {
		req.DurationMins = 90
	}

	// Conflict check if table assigned
	if req.TableID != nil && *req.TableID != "" {
		conflicts, err := m.queryConflicts(r.Context(), tenantID, *req.TableID, req.Date, req.Time, req.DurationMins, "")
		if err != nil {
			slog.Error("reservations: conflict check", "error", err)
		} else if len(conflicts) > 0 {
			response.ErrorWithDetails(w, http.StatusConflict, "table_conflict",
				"table is already reserved at that time",
				ConflictCheckResponse{HasConflict: true, Conflicts: conflicts})
			return
		}
	}

	now := time.Now().UTC()
	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO reservations
		  (id, tenant_id, customer_name, phone, guest_count, table_id,
		   date, time, duration_minutes, status, notes, customer_id,
		   created_at, updated_at, is_deleted)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'pending',$10,$11,$12,$12,false)
		ON CONFLICT (id) DO NOTHING
	`, req.ID, tenantID, req.CustomerName, req.Phone, req.GuestCount, req.TableID,
		req.Date, req.Time, req.DurationMins, req.Notes, req.CustomerID, now)
	if err != nil {
		slog.Error("reservations: create", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to create reservation")
		return
	}

	m.publishSyncEvent(r.Context(), tenantID, "reservations", req.ID, "insert", req)

	res := Reservation{
		ID:           req.ID,
		TenantID:     tenantID,
		CustomerName: req.CustomerName,
		Phone:        req.Phone,
		GuestCount:   req.GuestCount,
		TableID:      req.TableID,
		Date:         req.Date,
		Time:         req.Time,
		DurationMins: req.DurationMins,
		Status:       "pending",
		Notes:        req.Notes,
		CustomerID:   req.CustomerID,
		CreatedAt:    now,
		UpdatedAt:    now,
	}
	response.Created(w, res)
}

// handleGetReservation returns a single reservation.
// GET /api/v1/reservations/{id}
func (m *Module) handleGetReservation(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	row := m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, customer_name, phone, guest_count, table_id,
		       date, time, duration_minutes, status, notes, customer_id,
		       created_at, updated_at, is_deleted
		FROM reservations
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID)

	res, err := scanReservationRow(row)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "not_found", "reservation not found")
		return
	}
	if err != nil {
		slog.Error("reservations: get", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to get reservation")
		return
	}

	response.JSON(w, http.StatusOK, res)
}

// handleUpdateReservation updates an existing reservation.
// PUT /api/v1/reservations/{id}
func (m *Module) handleUpdateReservation(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	var req UpdateReservationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_body", "invalid JSON")
		return
	}

	// Validate status if provided
	if req.Status != nil {
		switch *req.Status {
		case "pending", "confirmed", "seated", "cancelled", "no_show":
		default:
			response.Error(w, http.StatusBadRequest, "validation_error",
				"status must be pending, confirmed, seated, cancelled, or no_show")
			return
		}
	}

	now := time.Now().UTC()
	result, err := m.db.ExecContext(r.Context(), `
		UPDATE reservations SET
			customer_name  = COALESCE($3, customer_name),
			phone          = COALESCE($4, phone),
			guest_count    = COALESCE($5, guest_count),
			table_id       = COALESCE($6, table_id),
			date           = COALESCE($7, date),
			time           = COALESCE($8, time),
			duration_minutes = COALESCE($9, duration_minutes),
			status         = COALESCE($10, status),
			notes          = COALESCE($11, notes),
			updated_at     = $12
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID, req.CustomerName, req.Phone, req.GuestCount, req.TableID,
		req.Date, req.Time, req.DurationMins, req.Status, req.Notes, now)
	if err != nil {
		slog.Error("reservations: update", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to update reservation")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "not_found", "reservation not found")
		return
	}

	m.publishSyncEvent(r.Context(), tenantID, "reservations", id, "update", req)
	response.NoContent(w)
}

// handleDeleteReservation soft-deletes a reservation.
// DELETE /api/v1/reservations/{id}
func (m *Module) handleDeleteReservation(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	now := time.Now().UTC()
	result, err := m.db.ExecContext(r.Context(), `
		UPDATE reservations SET is_deleted = true, updated_at = $3
		WHERE id = $1 AND tenant_id = $2
	`, id, tenantID, now)
	if err != nil {
		slog.Error("reservations: delete", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to delete reservation")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "not_found", "reservation not found")
		return
	}

	m.publishSyncEvent(r.Context(), tenantID, "reservations", id, "delete", map[string]string{"id": id})
	response.NoContent(w)
}

// handleCalendar returns reservations grouped by day for a date range.
// GET /api/v1/reservations/calendar?tenant_id=&from=YYYY-MM-DD&to=YYYY-MM-DD
func (m *Module) handleCalendar(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	tenantID := q.Get("tenant_id")
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}
	from := q.Get("from")
	to := q.Get("to")
	if from == "" {
		from = time.Now().UTC().Format("2006-01-02")
	}
	if to == "" {
		// default: 14-day window
		t, _ := time.Parse("2006-01-02", from)
		to = t.AddDate(0, 0, 14).Format("2006-01-02")
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, customer_name, phone, guest_count, table_id,
		       date, time, duration_minutes, status, notes, customer_id,
		       created_at, updated_at, is_deleted
		FROM reservations
		WHERE tenant_id = $1
		  AND is_deleted = false
		  AND date >= $2
		  AND date <= $3
		ORDER BY date ASC, time ASC
	`, tenantID, from, to)
	if err != nil {
		slog.Error("reservations: calendar", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to query calendar")
		return
	}
	defer rows.Close()

	byDay := map[string]*CalendarDay{}
	for rows.Next() {
		res, err := scanReservation(rows)
		if err != nil {
			continue
		}
		if _, ok := byDay[res.Date]; !ok {
			byDay[res.Date] = &CalendarDay{Date: res.Date}
		}
		byDay[res.Date].Reservations = append(byDay[res.Date].Reservations, res)
		byDay[res.Date].Count++
	}

	// Build ordered slice
	days := make([]CalendarDay, 0, len(byDay))
	cur, _ := time.Parse("2006-01-02", from)
	end, _ := time.Parse("2006-01-02", to)
	for !cur.After(end) {
		d := cur.Format("2006-01-02")
		if day, ok := byDay[d]; ok {
			days = append(days, *day)
		} else {
			days = append(days, CalendarDay{Date: d, Count: 0, Reservations: []Reservation{}})
		}
		cur = cur.AddDate(0, 0, 1)
	}

	response.JSON(w, http.StatusOK, days)
}

// handleCheckConflict detects if a table is double-booked at the requested time.
// POST /api/v1/reservations/check-conflict
func (m *Module) handleCheckConflict(w http.ResponseWriter, r *http.Request) {
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	var req ConflictCheckRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_body", "invalid JSON")
		return
	}
	if req.TableID == "" || req.Date == "" || req.Time == "" {
		response.Error(w, http.StatusBadRequest, "validation_error", "table_id, date, time required")
		return
	}
	if req.DurationMins <= 0 {
		req.DurationMins = 90
	}

	conflicts, err := m.queryConflicts(r.Context(), tenantID, req.TableID, req.Date, req.Time, req.DurationMins, req.ExcludeID)
	if err != nil {
		slog.Error("reservations: check conflict", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to check conflicts")
		return
	}

	response.JSON(w, http.StatusOK, ConflictCheckResponse{
		HasConflict: len(conflicts) > 0,
		Conflicts:   conflicts,
	})
}

// queryConflicts returns reservations on the same table that overlap the given time window.
// Overlap: existing_start < new_end AND existing_end > new_start.
func (m *Module) queryConflicts(ctx context.Context, tenantID, tableID, date, timeStr string, durationMins int, excludeID string) ([]Reservation, error) {
	rows, err := m.db.QueryContext(ctx, `
		SELECT id, tenant_id, customer_name, phone, guest_count, table_id,
		       date, time, duration_minutes, status, notes, customer_id,
		       created_at, updated_at, is_deleted
		FROM reservations
		WHERE tenant_id   = $1
		  AND table_id    = $2
		  AND date        = $3
		  AND is_deleted  = false
		  AND status NOT IN ('cancelled', 'no_show')
		  AND ($6 = '' OR id != $6)
		  AND (time::time < ($4::time + ($5 || ' minutes')::interval))
		  AND ((time::time + (duration_minutes || ' minutes')::interval) > $4::time)
	`, tenantID, tableID, date, timeStr, durationMins, excludeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var conflicts []Reservation
	for rows.Next() {
		res, err := scanReservation(rows)
		if err != nil {
			continue
		}
		conflicts = append(conflicts, res)
	}
	return conflicts, rows.Err()
}

// scanReservation scans a *sql.Rows into a Reservation.
func scanReservation(rows *sql.Rows) (Reservation, error) {
	var res Reservation
	var phone, notes, tableID, customerID sql.NullString
	err := rows.Scan(
		&res.ID, &res.TenantID, &res.CustomerName, &phone, &res.GuestCount, &tableID,
		&res.Date, &res.Time, &res.DurationMins, &res.Status, &notes, &customerID,
		&res.CreatedAt, &res.UpdatedAt, &res.IsDeleted,
	)
	if phone.Valid {
		res.Phone = &phone.String
	}
	if notes.Valid {
		res.Notes = &notes.String
	}
	if tableID.Valid {
		res.TableID = &tableID.String
	}
	if customerID.Valid {
		res.CustomerID = &customerID.String
	}
	return res, err
}

// scanReservationRow scans a *sql.Row into a Reservation.
func scanReservationRow(row *sql.Row) (Reservation, error) {
	var res Reservation
	var phone, notes, tableID, customerID sql.NullString
	err := row.Scan(
		&res.ID, &res.TenantID, &res.CustomerName, &phone, &res.GuestCount, &tableID,
		&res.Date, &res.Time, &res.DurationMins, &res.Status, &notes, &customerID,
		&res.CreatedAt, &res.UpdatedAt, &res.IsDeleted,
	)
	if phone.Valid {
		res.Phone = &phone.String
	}
	if notes.Valid {
		res.Notes = &notes.String
	}
	if tableID.Valid {
		res.TableID = &tableID.String
	}
	if customerID.Valid {
		res.CustomerID = &customerID.String
	}
	return res, err
}
