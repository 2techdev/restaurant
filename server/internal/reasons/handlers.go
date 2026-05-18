package reasons

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// reasonDTO is the wire shape for both void and discount reasons. The
// `MaxDiscountPercent` field is nil for void rows.
type reasonDTO struct {
	ID                  string          `json:"id"`
	Code                string          `json:"code"`
	Labels              json.RawMessage `json:"labels"`
	RequiresApproval    bool            `json:"requires_approval"`
	MaxDiscountPercent  *float64        `json:"max_discount_percent,omitempty"`
	DisplayOrder        int             `json:"display_order"`
	IsActive            bool            `json:"is_active"`
	CreatedAt           time.Time       `json:"created_at"`
	UpdatedAt           time.Time       `json:"updated_at"`
}

type upsertRequest struct {
	Code                string          `json:"code"`
	Labels              json.RawMessage `json:"labels"`
	RequiresApproval    *bool           `json:"requires_approval,omitempty"`
	MaxDiscountPercent  *float64        `json:"max_discount_percent,omitempty"`
	DisplayOrder        *int            `json:"display_order,omitempty"`
	IsActive            *bool           `json:"is_active,omitempty"`
}

// tableFor maps the "kind" path segment to the underlying table name.
// Anything outside the whitelist returns "" — the caller treats that as 404.
func tableFor(kind string) string {
	switch kind {
	case "void":
		return "void_reasons"
	case "discount":
		return "discount_reasons"
	}
	return ""
}

// requireWrite returns the caller's tenant + 403s anything below RESTAURANT_MANAGER.
// Reads are open to any authenticated tenant user.
func (m *Module) requireWrite(w http.ResponseWriter, r *http.Request) (string, bool) {
	tenantID := middleware.GetTenantID(r.Context())
	role := middleware.GetOrgRole(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return "", false
	}
	if role != "HQ_ADMIN" && role != "HQ_MANAGER" && role != "RESTAURANT_MANAGER" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Manager role required")
		return "", false
	}
	return tenantID, true
}

func (m *Module) handleList(kind string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		table := tableFor(kind)
		if table == "" {
			response.Error(w, http.StatusNotFound, "NOT_FOUND", "unknown kind")
			return
		}
		tenantID := middleware.GetTenantID(r.Context())
		if tenantID == "" {
			response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
			return
		}

		// Build the query — discount table has the extra max_discount_percent
		// column. We construct one ordered SELECT either way so the row scanner
		// stays simple.
		extra := ""
		if kind == "discount" {
			extra = "max_discount_percent,"
		}
		q := `SELECT id, code, labels, requires_approval, ` + extra +
			`display_order, is_active, created_at, updated_at FROM ` + table +
			` WHERE tenant_id = $1 ORDER BY display_order ASC, code ASC`
		rows, err := m.db.QueryContext(r.Context(), q, tenantID)
		if err != nil {
			slog.Error("reasons: list", "kind", kind, "error", err)
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list reasons")
			return
		}
		defer rows.Close()

		out := []reasonDTO{}
		for rows.Next() {
			var d reasonDTO
			var maxPercent sql.NullFloat64
			if kind == "discount" {
				if err := rows.Scan(&d.ID, &d.Code, &d.Labels, &d.RequiresApproval,
					&maxPercent, &d.DisplayOrder, &d.IsActive,
					&d.CreatedAt, &d.UpdatedAt); err != nil {
					continue
				}
				if maxPercent.Valid {
					v := maxPercent.Float64
					d.MaxDiscountPercent = &v
				}
			} else {
				if err := rows.Scan(&d.ID, &d.Code, &d.Labels, &d.RequiresApproval,
					&d.DisplayOrder, &d.IsActive,
					&d.CreatedAt, &d.UpdatedAt); err != nil {
					continue
				}
			}
			out = append(out, d)
		}
		response.JSON(w, http.StatusOK, map[string]any{"data": out})
	}
}

func (m *Module) handleCreate(kind string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		table := tableFor(kind)
		if table == "" {
			response.Error(w, http.StatusNotFound, "NOT_FOUND", "unknown kind")
			return
		}
		tenantID, ok := m.requireWrite(w, r)
		if !ok {
			return
		}
		var req upsertRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
			return
		}
		req.Code = strings.TrimSpace(strings.ToUpper(req.Code))
		if req.Code == "" {
			response.Error(w, http.StatusBadRequest, "VALIDATION", "code required")
			return
		}
		labels := req.Labels
		if len(labels) == 0 {
			labels = json.RawMessage(`{}`)
		}
		requiresApproval := false
		if req.RequiresApproval != nil {
			requiresApproval = *req.RequiresApproval
		}
		displayOrder := 0
		if req.DisplayOrder != nil {
			displayOrder = *req.DisplayOrder
		}
		isActive := true
		if req.IsActive != nil {
			isActive = *req.IsActive
		}

		var id string
		var err error
		if kind == "discount" {
			err = m.db.QueryRowContext(r.Context(), `
				INSERT INTO discount_reasons
				  (tenant_id, code, labels, requires_approval, max_discount_percent, display_order, is_active)
				VALUES ($1, $2, $3::jsonb, $4, $5, $6, $7)
				RETURNING id
			`, tenantID, req.Code, string(labels), requiresApproval,
				req.MaxDiscountPercent, displayOrder, isActive).Scan(&id)
		} else {
			err = m.db.QueryRowContext(r.Context(), `
				INSERT INTO void_reasons
				  (tenant_id, code, labels, requires_approval, display_order, is_active)
				VALUES ($1, $2, $3::jsonb, $4, $5, $6)
				RETURNING id
			`, tenantID, req.Code, string(labels), requiresApproval,
				displayOrder, isActive).Scan(&id)
		}
		if err != nil {
			if strings.Contains(err.Error(), "_code_key") {
				response.Error(w, http.StatusConflict, "DUPLICATE", "code already exists")
				return
			}
			slog.Error("reasons: create", "kind", kind, "error", err)
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create")
			return
		}
		response.JSON(w, http.StatusCreated, map[string]string{"id": id, "code": req.Code})
	}
}

func (m *Module) handleUpdate(kind string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		table := tableFor(kind)
		if table == "" {
			response.Error(w, http.StatusNotFound, "NOT_FOUND", "unknown kind")
			return
		}
		tenantID, ok := m.requireWrite(w, r)
		if !ok {
			return
		}
		id := r.PathValue("id")
		var req upsertRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
			return
		}
		// COALESCE pattern: only fields the client sent are touched.
		labels := req.Labels
		labelsArg := string(labels)
		if len(labels) == 0 {
			labelsArg = "" // empty -> keep
		}
		q := `UPDATE ` + table + ` SET
		         code              = COALESCE(NULLIF($2,''), code),
		         labels            = COALESCE(NULLIF($3,'')::jsonb, labels),
		         requires_approval = COALESCE($4, requires_approval),
		         display_order     = COALESCE($5, display_order),
		         is_active         = COALESCE($6, is_active),
		         updated_at        = NOW()`
		args := []any{id, strings.ToUpper(strings.TrimSpace(req.Code)), labelsArg,
			req.RequiresApproval, req.DisplayOrder, req.IsActive}
		if kind == "discount" {
			q += `,
		         max_discount_percent = COALESCE($7, max_discount_percent)`
			args = append(args, req.MaxDiscountPercent)
		}
		q += ` WHERE id = $1 AND tenant_id = $` + nextArg(len(args)+1)
		args = append(args, tenantID)

		res, err := m.db.ExecContext(r.Context(), q, args...)
		if err != nil {
			slog.Error("reasons: update", "kind", kind, "error", err)
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update")
			return
		}
		if n, _ := res.RowsAffected(); n == 0 {
			response.Error(w, http.StatusNotFound, "NOT_FOUND", "Reason not found")
			return
		}
		response.JSON(w, http.StatusOK, map[string]string{"status": "updated"})
	}
}

func (m *Module) handleDelete(kind string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		table := tableFor(kind)
		if table == "" {
			response.Error(w, http.StatusNotFound, "NOT_FOUND", "unknown kind")
			return
		}
		tenantID, ok := m.requireWrite(w, r)
		if !ok {
			return
		}
		id := r.PathValue("id")
		res, err := m.db.ExecContext(r.Context(),
			`DELETE FROM `+table+` WHERE id = $1 AND tenant_id = $2`, id, tenantID)
		if err != nil {
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete")
			return
		}
		if n, _ := res.RowsAffected(); n == 0 {
			response.Error(w, http.StatusNotFound, "NOT_FOUND", "Reason not found")
			return
		}
		response.JSON(w, http.StatusOK, map[string]string{"status": "deleted"})
	}
}

// nextArg keeps the SQL placeholder math obvious; given how few args we
// have, a real itoa is overkill but a tiny lookup is the smallest stdlib-free
// option.
func nextArg(n int) string {
	if n < 10 {
		return string(rune('0' + n))
	}
	// fall back — should never need >9 in this module.
	return "10"
}
