package audit

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

type Entry struct {
	ID         string          `json:"id"`
	TenantID   string          `json:"tenant_id"`
	BranchID   *string         `json:"branch_id,omitempty"`
	DeviceID   string          `json:"device_id"`
	UserID     string          `json:"user_id"`
	EntityType string          `json:"entity_type"`
	EntityID   string          `json:"entity_id"`
	Action     string          `json:"action"`
	OldValue   json.RawMessage `json:"old_value,omitempty"`
	NewValue   json.RawMessage `json:"new_value,omitempty"`
	Timestamp  time.Time       `json:"timestamp"`
}

// handleList returns paginated audit_log entries for a tenant. HQ admins may
// override the tenant via X-Tenant-ID header (already wired by AuthRequired).
//
// GET /api/v1/audit-log?from=&to=&user_id=&action=&entity_type=&limit=&cursor=
func (m *Module) handleList(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if !uuid.IsValid(tenantID) {
		// Allow HQ admins to pass tenant_id via query when JWT only has org scope.
		if q := r.URL.Query().Get("tenant_id"); uuid.IsValid(q) {
			tenantID = q
		} else {
			response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
			return
		}
	}

	q := r.URL.Query()
	limit := 100
	if l := q.Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 && n <= 500 {
			limit = n
		}
	}

	args := []any{tenantID}
	where := "tenant_id = $1"

	if v := q.Get("from"); v != "" {
		if t, err := time.Parse("2006-01-02", v); err == nil {
			args = append(args, t)
			where += " AND timestamp >= $" + strconv.Itoa(len(args))
		}
	}
	if v := q.Get("to"); v != "" {
		if t, err := time.Parse("2006-01-02", v); err == nil {
			tEnd := time.Date(t.Year(), t.Month(), t.Day(), 23, 59, 59, 0, t.Location())
			args = append(args, tEnd)
			where += " AND timestamp <= $" + strconv.Itoa(len(args))
		}
	}
	if v := q.Get("user_id"); uuid.IsValid(v) {
		args = append(args, v)
		where += " AND user_id = $" + strconv.Itoa(len(args))
	}
	if v := q.Get("action"); v != "" {
		args = append(args, v)
		where += " AND action = $" + strconv.Itoa(len(args))
	}
	if v := q.Get("entity_type"); v != "" {
		args = append(args, v)
		where += " AND entity_type = $" + strconv.Itoa(len(args))
	}
	if v := q.Get("cursor"); v != "" {
		if t, err := time.Parse(time.RFC3339Nano, v); err == nil {
			args = append(args, t)
			where += " AND timestamp < $" + strconv.Itoa(len(args))
		}
	}
	args = append(args, limit+1)

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id::TEXT, tenant_id::TEXT, branch_id::TEXT, device_id, user_id::TEXT,
		       entity_type, entity_id::TEXT, action, old_value, new_value, timestamp
		FROM audit_log
		WHERE `+where+`
		ORDER BY timestamp DESC
		LIMIT $`+strconv.Itoa(len(args)), args...)
	if err != nil {
		slog.Error("audit: list", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to query audit log")
		return
	}
	defer rows.Close()

	out := make([]Entry, 0)
	for rows.Next() {
		var e Entry
		var branch sql.NullString
		var oldV, newV []byte
		if err := rows.Scan(&e.ID, &e.TenantID, &branch, &e.DeviceID, &e.UserID,
			&e.EntityType, &e.EntityID, &e.Action, &oldV, &newV, &e.Timestamp); err != nil {
			continue
		}
		if branch.Valid {
			s := branch.String
			e.BranchID = &s
		}
		if len(oldV) > 0 {
			e.OldValue = json.RawMessage(oldV)
		}
		if len(newV) > 0 {
			e.NewValue = json.RawMessage(newV)
		}
		out = append(out, e)
	}

	hasMore := len(out) > limit
	cursor := ""
	if hasMore {
		out = out[:limit]
		cursor = out[len(out)-1].Timestamp.UTC().Format(time.RFC3339Nano)
	}
	response.Paginated(w, out, cursor, hasMore)
}
