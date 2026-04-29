package org

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

// ─────────────────────────────────────────────────────────────
// GET /api/v1/org/me
// Returns the current user's organization plus the member-restaurant list.
// ─────────────────────────────────────────────────────────────
func (m *Module) handleMe(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserID(r.Context())
	if !uuid.IsValid(uid) {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "User context required")
		return
	}

	var (
		orgID    sql.NullString
		orgRole  sql.NullString
		userName sql.NullString
	)
	err := m.db.QueryRowContext(r.Context(), `
		SELECT organization_id::text, org_role, COALESCE(name,'')
		FROM users WHERE id = $1
	`, uid).Scan(&orgID, &orgRole, &userName)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		slog.Error("org/me: fetch user", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to read user")
		return
	}

	out := map[string]any{
		"user_id":  uid,
		"name":     userName.String,
		"org_role": orgRole.String,
	}

	if !orgID.Valid {
		out["organization"] = nil
		out["restaurants"] = []any{}
		response.JSON(w, http.StatusOK, out)
		return
	}

	org, err := m.fetchOrganization(r.Context(), orgID.String)
	if err != nil {
		slog.Error("org/me: fetch org", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to read organization")
		return
	}
	out["organization"] = org

	members, err := m.listMemberRestaurants(r.Context(), orgID.String)
	if err != nil {
		slog.Error("org/me: list members", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list restaurants")
		return
	}
	out["restaurants"] = members

	response.JSON(w, http.StatusOK, out)
}

// ─────────────────────────────────────────────────────────────
// GET /api/v1/org/{orgId}/restaurants
// HQ_ADMIN view: each member tenant + last activity + today's revenue.
// ─────────────────────────────────────────────────────────────
func (m *Module) handleListRestaurants(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	if _, ok := m.hqOnly(w, r, orgID); !ok {
		return
	}
	rows, err := m.listMemberRestaurants(r.Context(), orgID)
	if err != nil {
		slog.Error("org: list restaurants", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list restaurants")
		return
	}
	response.JSON(w, http.StatusOK, map[string]any{"data": rows})
}

// ─────────────────────────────────────────────────────────────
// POST /api/v1/org/{orgId}/restaurants
// Body: { "name": "...", "tenant_id": "<existing tenant>"  } – or –
//       { "name": "...", "create_new": true }
// ─────────────────────────────────────────────────────────────
func (m *Module) handleCreateRestaurant(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	if _, ok := m.hqOnly(w, r, orgID); !ok {
		return
	}

	var req struct {
		Name      string `json:"name"`
		TenantID  string `json:"tenant_id"`
		CreateNew bool   `json:"create_new"`
		IsMaster  bool   `json:"is_master"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.Name == "" && req.TenantID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "name or tenant_id required")
		return
	}

	tenantID := req.TenantID
	if req.CreateNew || tenantID == "" {
		// Create a fresh tenant row.
		tenantID = uuid.New()
		_, err := m.db.ExecContext(r.Context(), `
			INSERT INTO tenants (id, name, organization_id, created_at, updated_at)
			VALUES ($1, $2, $3, NOW(), NOW())
		`, tenantID, req.Name, orgID)
		if err != nil {
			slog.Error("org: create tenant", "error", err)
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create restaurant")
			return
		}
	} else {
		if !uuid.IsValid(tenantID) {
			response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "tenant_id must be UUID")
			return
		}
		// Bind existing tenant.
		res, err := m.db.ExecContext(r.Context(), `
			UPDATE tenants SET organization_id = $1, updated_at = NOW()
			WHERE id = $2
		`, orgID, tenantID)
		if err != nil {
			slog.Error("org: bind tenant", "error", err)
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to bind restaurant")
			return
		}
		if n, _ := res.RowsAffected(); n == 0 {
			response.Error(w, http.StatusNotFound, "NOT_FOUND", "Tenant not found")
			return
		}
	}

	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO organization_memberships (organization_id, tenant_id, joined_at, is_master)
		VALUES ($1, $2, NOW(), $3)
		ON CONFLICT (organization_id, tenant_id) DO UPDATE
		  SET is_master = EXCLUDED.is_master
	`, orgID, tenantID, req.IsMaster)
	if err != nil {
		slog.Error("org: create membership", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to attach restaurant")
		return
	}

	response.Created(w, map[string]any{
		"tenant_id":       tenantID,
		"organization_id": orgID,
		"is_master":       req.IsMaster,
	})
}

// ─────────────────────────────────────────────────────────────
// DELETE /api/v1/org/{orgId}/restaurants/{restaurantId}
// Detaches a tenant from the org. Does NOT delete the tenant row.
// ─────────────────────────────────────────────────────────────
func (m *Module) handleDetachRestaurant(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	if _, ok := m.hqAdminOnly(w, r, orgID); !ok {
		return
	}
	tid := r.PathValue("restaurantId")
	if !uuid.IsValid(tid) {
		response.Error(w, http.StatusBadRequest, "INVALID_ID", "Invalid restaurant id")
		return
	}

	res, err := m.db.ExecContext(r.Context(), `
		DELETE FROM organization_memberships
		WHERE organization_id = $1 AND tenant_id = $2
	`, orgID, tid)
	if err != nil {
		slog.Error("org: detach", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to detach restaurant")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Membership not found")
		return
	}

	// Clear the tenant.organization_id pointer too, but only if it still
	// points at this org (defensive — the tenant could have been re-attached).
	_, err = m.db.ExecContext(r.Context(), `
		UPDATE tenants SET organization_id = NULL, updated_at = NOW()
		WHERE id = $1 AND organization_id = $2
	`, tid, orgID)
	if err != nil {
		slog.Warn("org: clear tenant.organization_id", "error", err)
	}

	response.NoContent(w)
}

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

func (m *Module) fetchOrganization(ctx context.Context, orgID string) (*Organization, error) {
	row := m.db.QueryRowContext(ctx, `
		SELECT id, name, owner_user_id::text, COALESCE(settings_json,'{}'::jsonb), created_at, updated_at
		FROM organizations WHERE id = $1
	`, orgID)
	var o Organization
	var owner sql.NullString
	var settings []byte
	if err := row.Scan(&o.ID, &o.Name, &owner, &settings, &o.CreatedAt, &o.UpdatedAt); err != nil {
		return nil, err
	}
	if owner.Valid {
		o.OwnerUserID = &owner.String
	}
	o.Settings = settings
	return &o, nil
}

// listMemberRestaurants returns each member tenant + cheap rollups:
//   - last_activity_at (max(closed_at) on tickets, fallback to opened_at)
//   - today_revenue (sum(total) over today's closed tickets)
func (m *Module) listMemberRestaurants(ctx context.Context, orgID string) ([]MemberRestaurant, error) {
	rows, err := m.db.QueryContext(ctx, `
		SELECT
		  m.tenant_id,
		  COALESCE(t.name, ''),
		  m.is_master,
		  m.joined_at,
		  (SELECT MAX(COALESCE(closed_at, opened_at)) FROM tickets WHERE tenant_id = m.tenant_id AND is_deleted = FALSE),
		  COALESCE(
		    (SELECT SUM(total) FROM tickets
		     WHERE tenant_id = m.tenant_id
		       AND is_deleted = FALSE
		       AND status = 'closed'
		       AND closed_at >= date_trunc('day', NOW())), 0)
		FROM organization_memberships m
		LEFT JOIN tenants t ON t.id = m.tenant_id
		WHERE m.organization_id = $1
		ORDER BY t.name ASC
	`, orgID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]MemberRestaurant, 0)
	for rows.Next() {
		var r MemberRestaurant
		var last sql.NullTime
		var rev sql.NullInt64
		if err := rows.Scan(&r.TenantID, &r.Name, &r.IsMaster, &r.JoinedAt, &last, &rev); err != nil {
			continue
		}
		if last.Valid {
			t := last.Time
			r.LastActivityAt = &t
		}
		if rev.Valid {
			r.TodayRevenue = rev.Int64
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// memberTenantIDs returns the list of tenant ids that belong to the org.
func (m *Module) memberTenantIDs(ctx context.Context, orgID string) ([]string, error) {
	rows, err := m.db.QueryContext(ctx, `SELECT tenant_id::text FROM organization_memberships WHERE organization_id = $1`, orgID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	ids := make([]string, 0)
	for rows.Next() {
		var s string
		if err := rows.Scan(&s); err == nil {
			ids = append(ids, s)
		}
	}
	return ids, rows.Err()
}

// masterTenantID returns the tenant flagged is_master=true for the org, if any.
// HQ master menu CRUD writes rows that live under this tenant_id (so existing
// menu tooling continues to work). When no master tenant is configured the
// caller must create one first.
func (m *Module) masterTenantID(ctx context.Context, orgID string) (string, error) {
	var s sql.NullString
	err := m.db.QueryRowContext(ctx, `
		SELECT tenant_id::text FROM organization_memberships
		WHERE organization_id = $1 AND is_master = TRUE LIMIT 1
	`, orgID).Scan(&s)
	if err == sql.ErrNoRows || !s.Valid {
		return "", errMasterMissing
	}
	if err != nil {
		return "", err
	}
	return s.String, nil
}

var errMasterMissing = errors.New("organization has no master tenant configured")
