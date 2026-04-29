package auth

import (
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/crypto"
	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// HQ admins manage admin_users via /api/v1/admin/users/*. Routes are scoped to
// the caller's organization_id (read from JWT). HQ_ADMIN can mutate; others get
// 403.

type adminUserDTO struct {
	ID             string     `json:"id"`
	OrganizationID string     `json:"organization_id"`
	Email          string     `json:"email"`
	Name           string     `json:"name"`
	Role           string     `json:"role"`
	StoreIDs       []string   `json:"store_ids,omitempty"`
	Status         string     `json:"status"`
	LastLoginAt    *time.Time `json:"last_login_at,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
}

func (m *Module) registerAdminUserRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/admin/users", m.handleAdminUserList)
	mux.HandleFunc("POST /api/v1/admin/users", m.handleAdminUserCreate)
	mux.HandleFunc("GET /api/v1/admin/users/{id}", m.handleAdminUserGet)
	mux.HandleFunc("PUT /api/v1/admin/users/{id}", m.handleAdminUserUpdate)
	mux.HandleFunc("PUT /api/v1/admin/users/{id}/disable", m.handleAdminUserDisable)
	mux.HandleFunc("PUT /api/v1/admin/users/{id}/enable", m.handleAdminUserEnable)
	mux.HandleFunc("PUT /api/v1/admin/users/{id}/reset-password", m.handleAdminUserResetPassword)
	mux.HandleFunc("DELETE /api/v1/admin/users/{id}", m.handleAdminUserDelete)
}

// requireHQAdmin is a small inline guard. HQ_MANAGER may read; HQ_ADMIN may write.
func (m *Module) requireHQAdmin(r *http.Request, write bool) (orgID string, ok bool, status int, msg string) {
	orgID = middleware.GetOrganizationID(r.Context())
	role := middleware.GetOrgRole(r.Context())
	if orgID == "" {
		return "", false, http.StatusUnauthorized, "Organization context required"
	}
	if role != "HQ_ADMIN" && role != "HQ_MANAGER" {
		return "", false, http.StatusForbidden, "HQ admin access required"
	}
	if write && role != "HQ_ADMIN" {
		return "", false, http.StatusForbidden, "HQ_ADMIN access required for this action"
	}
	return orgID, true, 0, ""
}

func (m *Module) handleAdminUserList(w http.ResponseWriter, r *http.Request) {
	orgID, ok, status, msg := m.requireHQAdmin(r, false)
	if !ok {
		response.Error(w, status, "FORBIDDEN", msg)
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, organization_id, email, name, role, COALESCE(store_ids, '{}'),
		       status, last_login_at, created_at, updated_at
		  FROM admin_users
		 WHERE organization_id = $1
		 ORDER BY created_at DESC
	`, orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list users")
		return
	}
	defer rows.Close()

	out := []adminUserDTO{}
	for rows.Next() {
		var u adminUserDTO
		var storeIDs []sql.NullString
		var lastLogin sql.NullTime
		// Postgres uuid[] reads via pq.Array — we don't import pq here, use text array fallback.
		var rawStoreIDs string
		if err := rows.Scan(&u.ID, &u.OrganizationID, &u.Email, &u.Name, &u.Role,
			&rawStoreIDs, &u.Status, &lastLogin, &u.CreatedAt, &u.UpdatedAt); err != nil {
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to read user row")
			return
		}
		_ = storeIDs
		u.StoreIDs = parsePgUUIDArray(rawStoreIDs)
		if lastLogin.Valid {
			t := lastLogin.Time
			u.LastLoginAt = &t
		}
		out = append(out, u)
	}
	response.JSON(w, http.StatusOK, map[string]any{"data": out})
}

func parsePgUUIDArray(raw string) []string {
	raw = strings.TrimSpace(raw)
	if raw == "" || raw == "{}" {
		return []string{}
	}
	raw = strings.TrimPrefix(raw, "{")
	raw = strings.TrimSuffix(raw, "}")
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		p = strings.Trim(p, `"`)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

type createAdminUserRequest struct {
	Email    string   `json:"email"`
	Name     string   `json:"name"`
	Role     string   `json:"role"`     // admin | brand_manager | store_manager | viewer
	StoreIDs []string `json:"store_ids,omitempty"`
	Password string   `json:"password,omitempty"` // optional; auto-generated if blank
}

type createAdminUserResponse struct {
	User             adminUserDTO `json:"user"`
	GeneratedPassword string      `json:"generated_password,omitempty"`
}

var validRoles = map[string]bool{
	"admin":          true,
	"brand_manager":  true,
	"store_manager":  true,
	"viewer":         true,
}

func (m *Module) handleAdminUserCreate(w http.ResponseWriter, r *http.Request) {
	orgID, ok, status, msg := m.requireHQAdmin(r, true)
	if !ok {
		response.Error(w, status, "FORBIDDEN", msg)
		return
	}
	var req createAdminUserRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	req.Name = strings.TrimSpace(req.Name)
	if req.Email == "" || !strings.Contains(req.Email, "@") {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "Invalid email")
		return
	}
	if req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "Name required")
		return
	}
	if !validRoles[req.Role] {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "Invalid role")
		return
	}

	plainPassword := strings.TrimSpace(req.Password)
	generated := ""
	if plainPassword == "" {
		var err error
		plainPassword, err = randomReadablePassword(14)
		if err != nil {
			response.Error(w, http.StatusInternalServerError, "INTERNAL", "Failed to generate password")
			return
		}
		generated = plainPassword
	}
	if len(plainPassword) < 6 {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "Password must be at least 6 characters")
		return
	}
	hash, err := crypto.HashPassword(plainPassword)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "INTERNAL", "Failed to hash password")
		return
	}

	storeIDs := req.StoreIDs
	if storeIDs == nil {
		storeIDs = []string{}
	}
	storeArr := pgArrayLiteral(storeIDs)

	var u adminUserDTO
	var lastLogin sql.NullTime
	var rawStoreIDs string
	err = m.db.QueryRowContext(r.Context(), `
		INSERT INTO admin_users (organization_id, email, name, role, password_hash, store_ids, status)
		VALUES ($1, $2, $3, $4, $5, $6::uuid[], 'active')
		RETURNING id, organization_id, email, name, role, COALESCE(store_ids, '{}'),
		          status, last_login_at, created_at, updated_at
	`, orgID, req.Email, req.Name, req.Role, hash, storeArr).Scan(
		&u.ID, &u.OrganizationID, &u.Email, &u.Name, &u.Role,
		&rawStoreIDs, &u.Status, &lastLogin, &u.CreatedAt, &u.UpdatedAt,
	)
	if err != nil {
		// duplicate email
		if strings.Contains(err.Error(), "admin_users_email_key") {
			response.Error(w, http.StatusConflict, "DUPLICATE", "Email already in use")
			return
		}
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create user")
		return
	}
	u.StoreIDs = parsePgUUIDArray(rawStoreIDs)
	response.JSON(w, http.StatusCreated, createAdminUserResponse{User: u, GeneratedPassword: generated})
}

func (m *Module) handleAdminUserGet(w http.ResponseWriter, r *http.Request) {
	orgID, ok, status, msg := m.requireHQAdmin(r, false)
	if !ok {
		response.Error(w, status, "FORBIDDEN", msg)
		return
	}
	id := r.PathValue("id")
	var u adminUserDTO
	var lastLogin sql.NullTime
	var rawStoreIDs string
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, organization_id, email, name, role, COALESCE(store_ids, '{}'),
		       status, last_login_at, created_at, updated_at
		  FROM admin_users
		 WHERE id = $1 AND organization_id = $2
	`, id, orgID).Scan(&u.ID, &u.OrganizationID, &u.Email, &u.Name, &u.Role,
		&rawStoreIDs, &u.Status, &lastLogin, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			response.Error(w, http.StatusNotFound, "NOT_FOUND", "User not found")
			return
		}
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load user")
		return
	}
	u.StoreIDs = parsePgUUIDArray(rawStoreIDs)
	if lastLogin.Valid {
		t := lastLogin.Time
		u.LastLoginAt = &t
	}
	response.JSON(w, http.StatusOK, u)
}

type updateAdminUserRequest struct {
	Name     *string   `json:"name,omitempty"`
	Role     *string   `json:"role,omitempty"`
	StoreIDs *[]string `json:"store_ids,omitempty"`
}

func (m *Module) handleAdminUserUpdate(w http.ResponseWriter, r *http.Request) {
	orgID, ok, status, msg := m.requireHQAdmin(r, true)
	if !ok {
		response.Error(w, status, "FORBIDDEN", msg)
		return
	}
	id := r.PathValue("id")
	var req updateAdminUserRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}

	sets := []string{}
	args := []any{}
	idx := 1
	if req.Name != nil {
		sets = append(sets, "name = $"+itoa(idx))
		args = append(args, strings.TrimSpace(*req.Name))
		idx++
	}
	if req.Role != nil {
		if !validRoles[*req.Role] {
			response.Error(w, http.StatusBadRequest, "VALIDATION", "Invalid role")
			return
		}
		sets = append(sets, "role = $"+itoa(idx))
		args = append(args, *req.Role)
		idx++
	}
	if req.StoreIDs != nil {
		sets = append(sets, "store_ids = $"+itoa(idx)+"::uuid[]")
		args = append(args, pgArrayLiteral(*req.StoreIDs))
		idx++
	}
	if len(sets) == 0 {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "Nothing to update")
		return
	}
	sets = append(sets, "updated_at = NOW()")
	args = append(args, id, orgID)

	q := "UPDATE admin_users SET " + strings.Join(sets, ", ") +
		" WHERE id = $" + itoa(idx) + " AND organization_id = $" + itoa(idx+1)
	res, err := m.db.ExecContext(r.Context(), q, args...)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update user")
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "User not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

func (m *Module) handleAdminUserDisable(w http.ResponseWriter, r *http.Request) {
	m.setStatus(w, r, "disabled")
}
func (m *Module) handleAdminUserEnable(w http.ResponseWriter, r *http.Request) {
	m.setStatus(w, r, "active")
}
func (m *Module) setStatus(w http.ResponseWriter, r *http.Request, newStatus string) {
	orgID, ok, status, msg := m.requireHQAdmin(r, true)
	if !ok {
		response.Error(w, status, "FORBIDDEN", msg)
		return
	}
	id := r.PathValue("id")
	res, err := m.db.ExecContext(r.Context(),
		`UPDATE admin_users SET status=$1, updated_at=NOW() WHERE id=$2 AND organization_id=$3`,
		newStatus, id, orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update status")
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "User not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"status": newStatus})
}

type resetPasswordResponse struct {
	GeneratedPassword string `json:"generated_password"`
}

func (m *Module) handleAdminUserResetPassword(w http.ResponseWriter, r *http.Request) {
	orgID, ok, status, msg := m.requireHQAdmin(r, true)
	if !ok {
		response.Error(w, status, "FORBIDDEN", msg)
		return
	}
	id := r.PathValue("id")
	plain, err := randomReadablePassword(14)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "INTERNAL", "Failed to generate password")
		return
	}
	hash, err := crypto.HashPassword(plain)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "INTERNAL", "Failed to hash password")
		return
	}
	res, err := m.db.ExecContext(r.Context(),
		`UPDATE admin_users SET password_hash=$1, updated_at=NOW()
		  WHERE id=$2 AND organization_id=$3`, hash, id, orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to reset password")
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "User not found")
		return
	}
	response.JSON(w, http.StatusOK, resetPasswordResponse{GeneratedPassword: plain})
}

func (m *Module) handleAdminUserDelete(w http.ResponseWriter, r *http.Request) {
	orgID, ok, status, msg := m.requireHQAdmin(r, true)
	if !ok {
		response.Error(w, status, "FORBIDDEN", msg)
		return
	}
	id := r.PathValue("id")
	// Don't let an admin delete themselves.
	caller := middleware.GetUserID(r.Context())
	if caller == id {
		response.Error(w, http.StatusBadRequest, "SELF_DELETE", "Cannot delete your own account")
		return
	}
	res, err := m.db.ExecContext(r.Context(),
		`DELETE FROM admin_users WHERE id=$1 AND organization_id=$2`, id, orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete user")
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "User not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

const passwordAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789"

func randomReadablePassword(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	out := make([]byte, n)
	for i, x := range b {
		out[i] = passwordAlphabet[int(x)%len(passwordAlphabet)]
	}
	return string(out), nil
}

func pgArrayLiteral(items []string) string {
	if len(items) == 0 {
		return "{}"
	}
	quoted := make([]string, len(items))
	for i, s := range items {
		quoted[i] = `"` + strings.ReplaceAll(s, `"`, `\"`) + `"`
	}
	return "{" + strings.Join(quoted, ",") + "}"
}

func itoa(i int) string {
	// Tiny, allocation-light int→string for small positive values.
	if i == 0 {
		return "0"
	}
	digits := []byte{}
	for i > 0 {
		digits = append([]byte{byte('0' + i%10)}, digits...)
		i /= 10
	}
	return string(digits)
}
