package crm

import (
	"context"
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// ── Segments CRUD ───────────────────────────────────────────────────────────

// handleListSegments returns segments for the current tenant.
// GET /api/v1/crm/segments
func (m *Module) handleListSegments(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, name, description, definition, is_dynamic,
		       created_by, created_at, updated_at, is_deleted
		FROM customer_segments
		WHERE tenant_id = $1 AND is_deleted = false
		ORDER BY created_at DESC
	`, tenantID)
	if err != nil {
		slog.Error("crm: list segments", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to query segments")
		return
	}
	defer rows.Close()

	segments := make([]Segment, 0)
	for rows.Next() {
		s, err := scanSegment(rows)
		if err != nil {
			slog.Error("crm: scan segment", "error", err)
			continue
		}
		segments = append(segments, s)
	}

	// Attach a fast count for each (small N — segments are operator-managed).
	for i := range segments {
		count, err := m.countSegmentMembers(r.Context(), tenantID, segments[i].Definition)
		if err == nil {
			segments[i].MemberCount = &count
		}
	}

	response.JSON(w, http.StatusOK, map[string]any{"segments": segments})
}

// handleGetSegment returns a single segment + its member count.
// GET /api/v1/crm/segments/{id}
func (m *Module) handleGetSegment(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	row := m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, name, description, definition, is_dynamic,
		       created_by, created_at, updated_at, is_deleted
		FROM customer_segments
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID)
	s, err := scanSegment(row)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "not_found", "segment not found")
		return
	}
	if err != nil {
		slog.Error("crm: get segment", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to get segment")
		return
	}
	count, err := m.countSegmentMembers(r.Context(), tenantID, s.Definition)
	if err == nil {
		s.MemberCount = &count
	}
	response.JSON(w, http.StatusOK, s)
}

// handleCreateSegment creates a new segment.
// POST /api/v1/crm/segments
func (m *Module) handleCreateSegment(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	var req CreateSegmentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_body", "invalid JSON")
		return
	}
	if req.ID == "" {
		response.Error(w, http.StatusBadRequest, "validation_error", "id required")
		return
	}
	if req.Name == "" {
		response.Error(w, http.StatusBadRequest, "validation_error", "name required")
		return
	}
	// Validate definition.
	if _, _, err := buildSegmentWhere(req.Definition, 1); err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_definition", err.Error())
		return
	}

	defJSON, err := json.Marshal(req.Definition)
	if err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_body", "failed to encode definition")
		return
	}
	isDynamic := true
	if req.IsDynamic != nil {
		isDynamic = *req.IsDynamic
	}
	createdBy := middleware.GetUserID(r.Context())

	now := time.Now().UTC()
	_, err = m.db.ExecContext(r.Context(), `
		INSERT INTO customer_segments (id, tenant_id, name, description, definition, is_dynamic,
		                               created_by, created_at, updated_at, is_deleted)
		VALUES ($1,$2,$3,$4,$5::jsonb,$6,$7,$8,$8,false)
		ON CONFLICT (id) DO NOTHING
	`, req.ID, tenantID, req.Name, req.Description, string(defJSON), isDynamic, sqlNullStr(createdBy), now)
	if err != nil {
		slog.Error("crm: create segment", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to create segment")
		return
	}

	seg := Segment{
		ID:          req.ID,
		TenantID:    tenantID,
		Name:        req.Name,
		Description: req.Description,
		Definition:  req.Definition,
		IsDynamic:   isDynamic,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	if createdBy != "" {
		seg.CreatedBy = &createdBy
	}
	response.Created(w, seg)
}

// handleUpdateSegment updates a segment.
// PUT /api/v1/crm/segments/{id}
func (m *Module) handleUpdateSegment(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	var req UpdateSegmentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_body", "invalid JSON")
		return
	}

	var defJSON any
	if req.Definition != nil {
		if _, _, err := buildSegmentWhere(*req.Definition, 1); err != nil {
			response.Error(w, http.StatusBadRequest, "invalid_definition", err.Error())
			return
		}
		b, err := json.Marshal(req.Definition)
		if err != nil {
			response.Error(w, http.StatusBadRequest, "invalid_body", "failed to encode definition")
			return
		}
		defJSON = string(b)
	}

	now := time.Now().UTC()
	result, err := m.db.ExecContext(r.Context(), `
		UPDATE customer_segments
		SET name        = COALESCE($3, name),
		    description = COALESCE($4, description),
		    definition  = COALESCE($5::jsonb, definition),
		    is_dynamic  = COALESCE($6, is_dynamic),
		    updated_at  = $7
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID, req.Name, req.Description, defJSON, req.IsDynamic, now)
	if err != nil {
		slog.Error("crm: update segment", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to update segment")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "not_found", "segment not found")
		return
	}
	response.NoContent(w)
}

// handleDeleteSegment soft-deletes a segment.
// DELETE /api/v1/crm/segments/{id}
func (m *Module) handleDeleteSegment(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}
	now := time.Now().UTC()
	result, err := m.db.ExecContext(r.Context(), `
		UPDATE customer_segments SET is_deleted = true, updated_at = $3
		WHERE id = $1 AND tenant_id = $2
	`, id, tenantID, now)
	if err != nil {
		slog.Error("crm: delete segment", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to delete segment")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "not_found", "segment not found")
		return
	}
	response.NoContent(w)
}

// handleSegmentMembers returns the customers currently matching a saved segment.
// GET /api/v1/crm/segments/{id}/members?limit=&cursor=
func (m *Module) handleSegmentMembers(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}
	limit := 50
	if l := r.URL.Query().Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 && n <= 500 {
			limit = n
		}
	}

	// Load the segment definition.
	var defJSON []byte
	if err := m.db.QueryRowContext(r.Context(),
		`SELECT definition FROM customer_segments WHERE id = $1 AND tenant_id = $2 AND is_deleted = false`,
		id, tenantID,
	).Scan(&defJSON); err != nil {
		if err == sql.ErrNoRows {
			response.Error(w, http.StatusNotFound, "not_found", "segment not found")
			return
		}
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to load segment")
		return
	}
	var def SegmentDefinition
	if err := json.Unmarshal(defJSON, &def); err != nil {
		response.Error(w, http.StatusInternalServerError, "invalid_definition", "failed to decode definition")
		return
	}

	customers, err := m.listSegmentMembers(r.Context(), tenantID, def, limit)
	if err != nil {
		slog.Error("crm: segment members", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", err.Error())
		return
	}
	response.JSON(w, http.StatusOK, map[string]any{
		"segment_id": id,
		"count":      len(customers),
		"customers":  customers,
	})
}

// handleSegmentPreview applies a definition without persisting — used by the
// segment editor in the backoffice to show a live matched-count badge.
// POST /api/v1/crm/segments/preview
func (m *Module) handleSegmentPreview(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}
	var req PreviewSegmentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_body", "invalid JSON")
		return
	}
	limit := req.Limit
	if limit <= 0 || limit > 200 {
		limit = 10
	}

	count, err := m.countSegmentMembers(r.Context(), tenantID, req.Definition)
	if err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_definition", err.Error())
		return
	}
	sample, err := m.listSegmentMembers(r.Context(), tenantID, req.Definition, limit)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "db_error", err.Error())
		return
	}
	response.JSON(w, http.StatusOK, map[string]any{
		"matched_count": count,
		"sample":        sample,
	})
}

// ── helpers ─────────────────────────────────────────────────────────────────

func (m *Module) countSegmentMembers(ctx context.Context, tenantID string, def SegmentDefinition) (int, error) {
	where, args, err := buildSegmentWhere(def, 2)
	if err != nil {
		return 0, err
	}
	query := `SELECT COUNT(*) FROM customers WHERE tenant_id = $1 AND is_deleted = false`
	if where != "" {
		query += " AND " + where
	}
	allArgs := append([]any{tenantID}, args...)
	var count int
	if err := m.db.QueryRowContext(ctx, query, allArgs...).Scan(&count); err != nil {
		return 0, err
	}
	return count, nil
}

func (m *Module) listSegmentMembers(ctx context.Context, tenantID string, def SegmentDefinition, limit int) ([]Customer, error) {
	where, args, err := buildSegmentWhere(def, 2)
	if err != nil {
		return nil, err
	}
	query := `SELECT ` + customerColumns + ` FROM customers WHERE tenant_id = $1 AND is_deleted = false`
	if where != "" {
		query += " AND " + where
	}
	query += ` ORDER BY total_spent_cents DESC, name ASC LIMIT ` + strconv.Itoa(limit)
	allArgs := append([]any{tenantID}, args...)

	rows, err := m.db.QueryContext(ctx, query, allArgs...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]Customer, 0)
	for rows.Next() {
		c, err := scanCustomer(rows)
		if err != nil {
			continue
		}
		out = append(out, c)
	}
	return out, nil
}

// scanSegment reads one customer_segments row, decoding the JSONB definition.
func scanSegment(s rowScanner) (Segment, error) {
	var seg Segment
	var description sql.NullString
	var createdBy sql.NullString
	var defJSON []byte
	if err := s.Scan(
		&seg.ID, &seg.TenantID, &seg.Name, &description, &defJSON, &seg.IsDynamic,
		&createdBy, &seg.CreatedAt, &seg.UpdatedAt, &seg.IsDeleted,
	); err != nil {
		return seg, err
	}
	if description.Valid {
		seg.Description = &description.String
	}
	if createdBy.Valid {
		seg.CreatedBy = &createdBy.String
	}
	if len(defJSON) > 0 {
		_ = json.Unmarshal(defJSON, &seg.Definition)
	}
	return seg, nil
}

// sqlNullStr maps a possibly-empty Go string to a sql.NullString.
func sqlNullStr(s string) sql.NullString {
	return sql.NullString{String: s, Valid: s != ""}
}
