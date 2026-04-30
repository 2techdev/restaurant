package feedback

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

type Feedback struct {
	ID         string     `json:"id"`
	TenantID   string     `json:"tenant_id"`
	CustomerID *string    `json:"customer_id,omitempty"`
	OrderID    *string    `json:"order_id,omitempty"`
	Rating     int        `json:"rating"`
	Comment    *string    `json:"comment,omitempty"`
	Resolved   bool       `json:"resolved"`
	ResolvedBy *string    `json:"resolved_by,omitempty"`
	ResolvedAt *time.Time `json:"resolved_at,omitempty"`
	CreatedAt  time.Time  `json:"created_at"`
}

func resolveTenant(r *http.Request) string {
	if t := middleware.GetTenantID(r.Context()); t != "" {
		return t
	}
	return r.URL.Query().Get("tenant_id")
}

// handleList returns feedback rows for a tenant, optionally filtered by
// resolved=true|false and rating=N. Paged via cursor (created_at).
// GET /api/v1/feedback?resolved=false&rating=&limit=&cursor=
func (m *Module) handleList(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	q := r.URL.Query()
	limit := 50
	if l := q.Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 && n <= 200 {
			limit = n
		}
	}

	args := []any{tenantID}
	where := "tenant_id = $1"

	if v := q.Get("resolved"); v != "" {
		args = append(args, v == "true")
		where += " AND resolved = $" + strconv.Itoa(len(args))
	}
	if v := q.Get("rating"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 1 && n <= 5 {
			args = append(args, n)
			where += " AND rating = $" + strconv.Itoa(len(args))
		}
	}
	args = append(args, limit+1)

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, customer_id, order_id, rating, comment,
		       resolved, resolved_by, resolved_at, created_at
		FROM feedback
		WHERE `+where+`
		ORDER BY created_at DESC
		LIMIT $`+strconv.Itoa(len(args)), args...)
	if err != nil {
		slog.Error("feedback: list", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list feedback")
		return
	}
	defer rows.Close()

	out := make([]Feedback, 0)
	for rows.Next() {
		var f Feedback
		var customerID, orderID, comment, resolvedBy sql.NullString
		var resolvedAt sql.NullTime
		if err := rows.Scan(&f.ID, &f.TenantID, &customerID, &orderID, &f.Rating,
			&comment, &f.Resolved, &resolvedBy, &resolvedAt, &f.CreatedAt); err != nil {
			continue
		}
		if customerID.Valid {
			s := customerID.String
			f.CustomerID = &s
		}
		if orderID.Valid {
			s := orderID.String
			f.OrderID = &s
		}
		if comment.Valid {
			s := comment.String
			f.Comment = &s
		}
		if resolvedBy.Valid {
			s := resolvedBy.String
			f.ResolvedBy = &s
		}
		if resolvedAt.Valid {
			t := resolvedAt.Time
			f.ResolvedAt = &t
		}
		out = append(out, f)
	}

	hasMore := len(out) > limit
	if hasMore {
		out = out[:limit]
	}
	response.Paginated(w, out, "", hasMore)
}

// handleCreate stores a feedback record. customer_id, order_id and comment
// are optional; rating (1-5) is required.
// POST /api/v1/feedback
func (m *Module) handleCreate(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	var req struct {
		CustomerID *string `json:"customer_id"`
		OrderID    *string `json:"order_id"`
		Rating     int     `json:"rating"`
		Comment    *string `json:"comment"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	if req.Rating < 1 || req.Rating > 5 {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "rating must be 1..5")
		return
	}

	id := uuid.New()
	now := time.Now().UTC()
	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO feedback (id, tenant_id, customer_id, order_id, rating, comment, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7)
	`, id, tenantID, nullableString(req.CustomerID), nullableString(req.OrderID),
		req.Rating, nullableString(req.Comment), now)
	if err != nil {
		slog.Error("feedback: create", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to store feedback")
		return
	}

	response.Created(w, Feedback{
		ID:         id,
		TenantID:   tenantID,
		CustomerID: req.CustomerID,
		OrderID:    req.OrderID,
		Rating:     req.Rating,
		Comment:    req.Comment,
		Resolved:   false,
		CreatedAt:  now,
	})
}

// handleResolve marks a feedback row resolved. Body may include the resolver's
// name/id (recorded for audit) but the JWT user_id is preferred.
// PUT /api/v1/feedback/{id}/resolve
func (m *Module) handleResolve(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")

	resolver := middleware.GetUserID(r.Context())
	if resolver == "" {
		var body struct {
			ResolvedBy string `json:"resolved_by"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)
		resolver = body.ResolvedBy
	}

	now := time.Now().UTC()
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE feedback SET resolved = true, resolved_by = $3, resolved_at = $4
		WHERE id = $1 AND tenant_id = $2 AND resolved = false
	`, id, tenantID, nullableString(&resolver), now)
	if err != nil {
		slog.Error("feedback: resolve", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to resolve feedback")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Feedback not found or already resolved")
		return
	}
	response.JSON(w, http.StatusOK, map[string]any{
		"id":          id,
		"resolved":    true,
		"resolved_by": resolver,
		"resolved_at": now,
	})
}

func nullableString(s *string) any {
	if s == nil || *s == "" {
		return nil
	}
	return *s
}
