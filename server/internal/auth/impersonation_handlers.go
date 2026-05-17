package auth

// F1 — Super admin impersonation (Wallee-style ghost login).
//
// Three endpoints:
//   POST /api/v1/admin/impersonate        super admin → start session, get JWT
//   POST /api/v1/admin/impersonate/exit   end session
//   GET  /api/v1/admin/tenants            list tenants + admin users
//
// Security model:
//   - Caller must have IsSuperAdmin=true on their JWT (set at login from
//     admin_users.is_super_admin, migration 024).
//   - Target user must NOT be a super admin (cannot impersonate other supers).
//   - Token expiry is 15 minutes — hard cap; refresh is intentionally not
//     supported.
//   - Rate limit: 50 impersonations/hour/super-admin (in-memory).
//   - Audit row written to impersonation_sessions on start; ended_at set on
//     exit. Ip + user-agent captured.

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

const (
	impersonationTokenExpiry  = 15 * time.Minute
	impersonationRateLimitMax = 50
	impersonationRateWindow   = time.Hour
)

// ── Rate limit (in-memory, per super-admin) ─────────────────────────────────

type impersonationRateState struct {
	mu      sync.Mutex
	buckets map[string]*rateBucket
}

type rateBucket struct {
	count   int
	resetAt time.Time
}

var globalImpersonationRate = &impersonationRateState{buckets: make(map[string]*rateBucket)}

func (r *impersonationRateState) allow(superAdminID string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	now := time.Now()
	b, ok := r.buckets[superAdminID]
	if !ok || now.After(b.resetAt) {
		r.buckets[superAdminID] = &rateBucket{count: 1, resetAt: now.Add(impersonationRateWindow)}
		return true
	}
	if b.count >= impersonationRateLimitMax {
		return false
	}
	b.count++
	return true
}

// ── Helpers ──────────────────────────────────────────────────────────────────

func clientIP(r *http.Request) string {
	if v := r.Header.Get("X-Forwarded-For"); v != "" {
		if i := strings.Index(v, ","); i >= 0 {
			return strings.TrimSpace(v[:i])
		}
		return strings.TrimSpace(v)
	}
	if v := r.Header.Get("X-Real-IP"); v != "" {
		return v
	}
	return r.RemoteAddr
}

func ctxIsSuperAdmin(ctx context.Context) bool {
	return middleware.IsSuperAdmin(ctx)
}

func ctxUserID(ctx context.Context) string {
	return middleware.GetUserID(ctx)
}

// ── Request / response types ─────────────────────────────────────────────────

type impersonateRequest struct {
	TargetUserID string `json:"target_user_id"`
	Reason       string `json:"reason,omitempty"`
}

type impersonateResponse struct {
	Success    bool           `json:"success"`
	SessionID  string         `json:"session_id"`
	Token      string         `json:"token"`
	ExpiresAt  time.Time      `json:"expires_at"`
	TargetUser targetUserInfo `json:"target_user"`
}

type targetUserInfo struct {
	ID             string `json:"id"`
	Email          string `json:"email"`
	Name           string `json:"name"`
	OrganizationID string `json:"organization_id"`
	Role           string `json:"role"`
}

type tenantInfo struct {
	OrganizationID   string     `json:"organization_id"`
	OrganizationName string     `json:"organization_name"`
	OwnerEmail       string     `json:"owner_email,omitempty"`
	OwnerUserID      string     `json:"owner_user_id,omitempty"`
	OwnerName        string     `json:"owner_name,omitempty"`
	AdminUserCount   int        `json:"admin_user_count"`
	LastActiveAt     *time.Time `json:"last_active_at,omitempty"`
}

type tenantsListResponse struct {
	Tenants []tenantInfo `json:"tenants"`
}

// ── Routes registration (called from auth/module.go) ─────────────────────────

func (m *Module) registerImpersonationRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/admin/impersonate", m.handleImpersonate)
	mux.HandleFunc("POST /api/v1/admin/impersonate/exit", m.handleImpersonateExit)
	mux.HandleFunc("GET /api/v1/admin/tenants", m.handleListTenants)
}

// ── POST /api/v1/admin/impersonate ───────────────────────────────────────────

func (m *Module) handleImpersonate(w http.ResponseWriter, r *http.Request) {
	if !ctxIsSuperAdmin(r.Context()) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Super admin role required")
		return
	}
	superAdminID := ctxUserID(r.Context())
	if superAdminID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Missing user context")
		return
	}

	var req impersonateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if strings.TrimSpace(req.TargetUserID) == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "target_user_id is required")
		return
	}

	if !globalImpersonationRate.allow(superAdminID) {
		response.Error(w, http.StatusTooManyRequests, "RATE_LIMITED",
			fmt.Sprintf("Impersonation rate limit reached (%d/hour)", impersonationRateLimitMax))
		return
	}

	var (
		targetID      string
		targetEmail   string
		targetName    string
		targetOrgID   string
		targetRole    string
		targetStatus  string
		targetIsSuper bool
	)
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, email, name, organization_id, role, status, COALESCE(is_super_admin, FALSE)
		FROM admin_users
		WHERE id = $1
	`, req.TargetUserID).Scan(
		&targetID, &targetEmail, &targetName, &targetOrgID, &targetRole, &targetStatus, &targetIsSuper,
	)
	if errors.Is(err, sql.ErrNoRows) {
		response.Error(w, http.StatusNotFound, "TARGET_NOT_FOUND", "Target user does not exist")
		return
	}
	if err != nil {
		slog.Error("impersonation: target lookup", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to resolve target user")
		return
	}
	if targetStatus != "active" {
		response.Error(w, http.StatusForbidden, "TARGET_INACTIVE", "Target user is suspended or inactive")
		return
	}
	if targetIsSuper {
		response.Error(w, http.StatusForbidden, "TARGET_IS_SUPER_ADMIN",
			"Cannot impersonate another super admin")
		return
	}
	if targetID == superAdminID {
		response.Error(w, http.StatusBadRequest, "CANNOT_IMPERSONATE_SELF",
			"Cannot impersonate yourself")
		return
	}

	var sessionID string
	var startedAt time.Time
	reason := strings.TrimSpace(req.Reason)
	var reasonArg interface{} = nil
	if reason != "" {
		reasonArg = reason
	}
	err = m.db.QueryRowContext(r.Context(), `
		INSERT INTO impersonation_sessions
		    (super_admin_id, target_user_id, target_tenant_id, reason, ip_address, user_agent)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, started_at
	`, superAdminID, targetID, targetOrgID, reasonArg, clientIP(r), r.UserAgent()).Scan(&sessionID, &startedAt)
	if err != nil {
		slog.Error("impersonation: session insert", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create session")
		return
	}

	orgRole := mapAdminRoleToOrgRole(targetRole)
	token, err := m.jwt.GenerateTokenWithExpiry(Claims{
		TenantID:               targetOrgID,
		UserID:                 targetID,
		Role:                   targetRole,
		OrganizationID:         targetOrgID,
		OrgRole:                orgRole,
		IsSuperAdmin:           false,
		ImpersonatedBy:         superAdminID,
		ImpersonationSessionID: sessionID,
	}, impersonationTokenExpiry)
	if err != nil {
		slog.Error("impersonation: token", "error", err)
		response.Error(w, http.StatusInternalServerError, "TOKEN_ERROR", "Failed to generate token")
		return
	}

	expiresAt := startedAt.Add(impersonationTokenExpiry)

	slog.Info("impersonation started",
		"super_admin_id", superAdminID,
		"target_user_id", targetID,
		"target_tenant_id", targetOrgID,
		"session_id", sessionID,
		"reason", reason,
		"ip", clientIP(r),
	)

	response.JSON(w, http.StatusOK, impersonateResponse{
		Success:   true,
		SessionID: sessionID,
		Token:     token,
		ExpiresAt: expiresAt,
		TargetUser: targetUserInfo{
			ID:             targetID,
			Email:          targetEmail,
			Name:           targetName,
			OrganizationID: targetOrgID,
			Role:           targetRole,
		},
	})
}

// ── POST /api/v1/admin/impersonate/exit ──────────────────────────────────────

type exitResponse struct {
	Success   bool   `json:"success"`
	SessionID string `json:"session_id,omitempty"`
}

func (m *Module) handleImpersonateExit(w http.ResponseWriter, r *http.Request) {
	sessionID := middleware.GetImpersonationSessionID(r.Context())
	if sessionID == "" {
		response.Error(w, http.StatusBadRequest, "NOT_IMPERSONATING",
			"This token is not an impersonation token")
		return
	}

	res, err := m.db.ExecContext(r.Context(), `
		UPDATE impersonation_sessions
		SET ended_at = NOW()
		WHERE id = $1 AND ended_at IS NULL
	`, sessionID)
	if err != nil {
		slog.Error("impersonation exit: update", "error", err, "session_id", sessionID)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to end session")
		return
	}
	if rows, _ := res.RowsAffected(); rows > 0 {
		slog.Info("impersonation ended", "session_id", sessionID)
	}

	response.JSON(w, http.StatusOK, exitResponse{Success: true, SessionID: sessionID})
}

// ── GET /api/v1/admin/tenants ────────────────────────────────────────────────

func (m *Module) handleListTenants(w http.ResponseWriter, r *http.Request) {
	if !ctxIsSuperAdmin(r.Context()) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Super admin role required")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT
		    o.id::text                                AS org_id,
		    o.name                                    AS org_name,
		    (
		        SELECT COUNT(*) FROM admin_users a2
		        WHERE a2.organization_id = o.id
		          AND a2.status = 'active'
		          AND COALESCE(a2.is_super_admin, FALSE) = FALSE
		    )                                         AS admin_count,
		    (
		        SELECT a3.id::text FROM admin_users a3
		        WHERE a3.organization_id = o.id
		          AND a3.status = 'active'
		          AND COALESCE(a3.is_super_admin, FALSE) = FALSE
		        ORDER BY a3.created_at ASC LIMIT 1
		    )                                         AS owner_id,
		    (
		        SELECT a4.email FROM admin_users a4
		        WHERE a4.organization_id = o.id
		          AND a4.status = 'active'
		          AND COALESCE(a4.is_super_admin, FALSE) = FALSE
		        ORDER BY a4.created_at ASC LIMIT 1
		    )                                         AS owner_email,
		    (
		        SELECT a5.name FROM admin_users a5
		        WHERE a5.organization_id = o.id
		          AND a5.status = 'active'
		          AND COALESCE(a5.is_super_admin, FALSE) = FALSE
		        ORDER BY a5.created_at ASC LIMIT 1
		    )                                         AS owner_name,
		    (
		        SELECT MAX(a6.last_login_at) FROM admin_users a6
		        WHERE a6.organization_id = o.id
		          AND COALESCE(a6.is_super_admin, FALSE) = FALSE
		    )                                         AS last_active_at
		FROM organizations o
		ORDER BY o.name ASC
	`)
	if err != nil {
		slog.Error("tenants list", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list tenants")
		return
	}
	defer rows.Close()

	out := tenantsListResponse{Tenants: []tenantInfo{}}
	for rows.Next() {
		var t tenantInfo
		var ownerID, ownerEmail, ownerName sql.NullString
		var lastActive sql.NullTime
		if err := rows.Scan(&t.OrganizationID, &t.OrganizationName, &t.AdminUserCount,
			&ownerID, &ownerEmail, &ownerName, &lastActive); err != nil {
			slog.Error("tenants list scan", "error", err)
			continue
		}
		if ownerID.Valid {
			t.OwnerUserID = ownerID.String
		}
		if ownerEmail.Valid {
			t.OwnerEmail = ownerEmail.String
		}
		if ownerName.Valid {
			t.OwnerName = ownerName.String
		}
		if lastActive.Valid {
			la := lastActive.Time
			t.LastActiveAt = &la
		}
		out.Tenants = append(out.Tenants, t)
	}
	if err := rows.Err(); err != nil {
		slog.Error("tenants list rows", "error", err)
	}

	response.JSON(w, http.StatusOK, out)
}
