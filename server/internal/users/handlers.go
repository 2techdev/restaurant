package users

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/crypto"
	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

type AppUser struct {
	ID          string     `json:"id"`
	Name        string     `json:"name"`
	Email       *string    `json:"email,omitempty"`
	Role        string     `json:"role"`
	IsActive    bool       `json:"is_active"`
	StoreID     *string    `json:"store_id,omitempty"`
	LastLogin   *time.Time `json:"last_login,omitempty"`
	LastLoginAt *time.Time `json:"last_login_at,omitempty"`
}

// handleList returns app_users scoped to the caller's tenant context.
//
// HQ_ADMIN / HQ_MANAGER / super admin see every staff member in the active
// tenant context (driven by X-Tenant-ID — middleware will swap tenant_id
// for them). RESTAURANT_MANAGER and lower roles are pinned to the JWT-stamped
// tenant_id by middleware, so the same query naturally scopes to their store.
//
// GET /api/v1/users
func (m *Module) handleList(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	orgID := middleware.GetOrganizationID(r.Context())
	if !uuid.IsValid(tenantID) {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	// Decide query scope: if tenantID == orgID, it's an HQ-wide listing;
	// otherwise it's a single-restaurant slice. Backwards compatible —
	// when middleware can't distinguish (e.g. token without org claim)
	// we fall through to org-wide.
	queryOrg := orgID
	if queryOrg == "" {
		queryOrg = tenantID
	}
	storeFilter := ""
	if tenantID != queryOrg {
		storeFilter = tenantID
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, COALESCE(display_name, COALESCE(email,'')) AS name,
		       email, role, is_active, store_id::TEXT, last_login
		FROM app_users
		WHERE organization_id = $1
		  AND ($2 = '' OR store_id::TEXT = $2)
		ORDER BY role, display_name
	`, queryOrg, storeFilter)
	if err != nil {
		slog.Error("users: list", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list users")
		return
	}
	defer rows.Close()

	out := make([]AppUser, 0)
	for rows.Next() {
		var u AppUser
		var email, storeID sql.NullString
		var lastLogin sql.NullTime
		if err := rows.Scan(&u.ID, &u.Name, &email, &u.Role, &u.IsActive, &storeID, &lastLogin); err != nil {
			continue
		}
		if email.Valid {
			s := email.String
			u.Email = &s
		}
		if storeID.Valid {
			s := storeID.String
			u.StoreID = &s
		}
		if lastLogin.Valid {
			t := lastLogin.Time
			u.LastLogin = &t
			u.LastLoginAt = &t
		}
		out = append(out, u)
	}
	response.JSON(w, http.StatusOK, out)
}

type upsertRequest struct {
	Name     string  `json:"name"`
	Email    *string `json:"email"`
	Role     string  `json:"role"`
	PIN      *string `json:"pin"`
	Password *string `json:"password"`
	IsActive *bool   `json:"is_active"`
	StoreID  *string `json:"store_id"`
}

// handleCreate inserts a new app_user scoped to the tenant. If StoreID is
// unset, the first active store of the tenant is used.
// POST /api/v1/users
func (m *Module) handleCreate(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	orgID := middleware.GetOrganizationID(r.Context())
	orgRole := middleware.GetOrgRole(r.Context())
	if !uuid.IsValid(tenantID) {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	if orgID == "" {
		orgID = tenantID
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
	if req.Role == "" {
		req.Role = "waiter"
	}
	if !validRole(req.Role) {
		response.Error(w, http.StatusBadRequest, "INVALID_ROLE", "unknown role")
		return
	}
	// Role hierarchy: only HQ-tier accounts may mint HQ-tier app_users rows.
	// A RESTAURANT_MANAGER (or any non-HQ caller) is capped to POS staff.
	if !isHQTier(orgRole) && !posCreatableRoles[req.Role] {
		response.Error(w, http.StatusForbidden, "ROLE_NOT_ALLOWED",
			"Bu rolü oluşturma yetkiniz yok. Yalnızca POS personeli (müdür, kasiyer, garson, mutfak, kiosk) oluşturabilirsiniz.")
		return
	}
	pass := ""
	if req.Password != nil {
		pass = *req.Password
	}
	pin := ""
	if req.PIN != nil {
		pin = *req.PIN
	}
	if pass == "" && pin == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "password or pin required")
		return
	}

	// Non-HQ callers cannot specify a foreign store_id: ignore whatever the
	// client sent and pin to the JWT-stamped tenant (== caller's own store).
	if !isHQTier(orgRole) {
		t := tenantID
		req.StoreID = &t
	}
	storeID, err := resolveStoreID(r, m.db, orgID, req.StoreID)
	if err != nil {
		response.Error(w, http.StatusBadRequest, "NO_STORE", "No store available for tenant")
		return
	}

	// If password empty, hash the PIN and reuse for password_hash to satisfy
	// NOT NULL constraint; PIN-login still works via pin_hash.
	passwordSource := pass
	if passwordSource == "" {
		passwordSource = pin
	}
	passwordHash, err := crypto.HashPassword(passwordSource)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "HASH_ERROR", "Failed to process password")
		return
	}
	var pinHash *string
	if pin != "" {
		h, err := crypto.HashPIN(pin)
		if err != nil {
			response.Error(w, http.StatusInternalServerError, "HASH_ERROR", "Failed to process PIN")
			return
		}
		pinHash = &h
	}

	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}
	id := uuid.New()
	var emailParam any
	if req.Email != nil && *req.Email != "" {
		emailParam = *req.Email
	} else {
		emailParam = nil
	}
	_, err = m.db.ExecContext(r.Context(), `
		INSERT INTO app_users (
			id, organization_id, store_id, email, username,
			password_hash, pin_hash, role, display_name, is_active
		) VALUES ($1,$2,$3,$4,NULL,$5,$6,$7,$8,$9)
	`, id, orgID, storeID, emailParam, passwordHash, pinHash, req.Role, req.Name, isActive)
	if err != nil {
		slog.Error("users: create", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create user")
		return
	}
	m.writeOne(w, r, orgID, id)
}

// handleUpdate updates an existing app_user (name/email/role/active/pin/password).
// PUT /api/v1/users/{id}
func (m *Module) handleUpdate(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	orgID := middleware.GetOrganizationID(r.Context())
	orgRole := middleware.GetOrgRole(r.Context())
	id := r.PathValue("id")
	if !uuid.IsValid(tenantID) || !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid tenant or id")
		return
	}
	if orgID == "" {
		orgID = tenantID
	}
	var req upsertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.Role != "" && !validRole(req.Role) {
		response.Error(w, http.StatusBadRequest, "INVALID_ROLE", "unknown role")
		return
	}
	if req.Role != "" && !isHQTier(orgRole) && !posCreatableRoles[req.Role] {
		response.Error(w, http.StatusForbidden, "ROLE_NOT_ALLOWED",
			"Bu role atama yetkiniz yok.")
		return
	}
	// Tenant-scope ownership check: non-HQ callers may only touch users in
	// their own store. The UPDATE WHERE clause adds the store filter so a
	// hand-crafted PUT cannot reach across tenants.
	storeFilter := ""
	if !isHQTier(orgRole) {
		storeFilter = tenantID
	}

	// Build optional password/pin hashes.
	var passwordHash *string
	if req.Password != nil && *req.Password != "" {
		h, err := crypto.HashPassword(*req.Password)
		if err != nil {
			response.Error(w, http.StatusInternalServerError, "HASH_ERROR", "Failed to process password")
			return
		}
		passwordHash = &h
	}
	var pinHash *string
	if req.PIN != nil && *req.PIN != "" {
		h, err := crypto.HashPIN(*req.PIN)
		if err != nil {
			response.Error(w, http.StatusInternalServerError, "HASH_ERROR", "Failed to process PIN")
			return
		}
		pinHash = &h
	}

	var emailParam any
	if req.Email != nil {
		if *req.Email == "" {
			emailParam = sql.NullString{}
		} else {
			emailParam = *req.Email
		}
	}

	result, err := m.db.ExecContext(r.Context(), `
		UPDATE app_users SET
			display_name = CASE WHEN $3 = '' THEN display_name ELSE $3 END,
			email = CASE
				WHEN $4::TEXT IS NULL THEN email
				WHEN $4::TEXT = '' THEN NULL
				ELSE $4::TEXT
			END,
			role = CASE WHEN $5 = '' THEN role ELSE $5 END,
			is_active = COALESCE($6, is_active),
			password_hash = COALESCE($7, password_hash),
			pin_hash = COALESCE($8, pin_hash),
			updated_at = NOW()
		WHERE id = $1
		  AND organization_id = $2
		  AND ($9 = '' OR store_id::TEXT = $9)
	`, id, orgID, req.Name, emailParam, req.Role, req.IsActive, passwordHash, pinHash, storeFilter)
	if err != nil {
		slog.Error("users: update", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update user")
		return
	}
	if n, _ := result.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "User not found")
		return
	}
	m.writeOne(w, r, orgID, id)
}

// handleDelete soft-deletes by setting is_active=FALSE.
// DELETE /api/v1/users/{id}
func (m *Module) handleDelete(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	orgID := middleware.GetOrganizationID(r.Context())
	orgRole := middleware.GetOrgRole(r.Context())
	id := r.PathValue("id")
	if !uuid.IsValid(tenantID) || !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid tenant or id")
		return
	}
	if orgID == "" {
		orgID = tenantID
	}
	storeFilter := ""
	if !isHQTier(orgRole) {
		storeFilter = tenantID
	}
	result, err := m.db.ExecContext(r.Context(), `
		UPDATE app_users SET is_active = FALSE, updated_at = NOW()
		WHERE id = $1 AND organization_id = $2
		  AND ($3 = '' OR store_id::TEXT = $3)
	`, id, orgID, storeFilter)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete user")
		return
	}
	if n, _ := result.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "User not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handleResetPin resets the PIN for a user.
// POST /api/v1/users/{id}/pin
func (m *Module) handleResetPin(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	orgID := middleware.GetOrganizationID(r.Context())
	orgRole := middleware.GetOrgRole(r.Context())
	id := r.PathValue("id")
	if !uuid.IsValid(tenantID) || !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid tenant or id")
		return
	}
	if orgID == "" {
		orgID = tenantID
	}
	storeFilter := ""
	if !isHQTier(orgRole) {
		storeFilter = tenantID
	}
	var req struct {
		PIN string `json:"pin"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if len(req.PIN) < 4 || len(req.PIN) > 6 {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "pin must be 4-6 digits")
		return
	}
	h, err := crypto.HashPIN(req.PIN)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "HASH_ERROR", "Failed to hash pin")
		return
	}
	result, err := m.db.ExecContext(r.Context(), `
		UPDATE app_users SET pin_hash = $3, updated_at = NOW()
		WHERE id = $1 AND organization_id = $2
		  AND ($4 = '' OR store_id::TEXT = $4)
	`, id, orgID, h, storeFilter)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to reset pin")
		return
	}
	if n, _ := result.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "User not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (m *Module) writeOne(w http.ResponseWriter, r *http.Request, orgID, id string) {
	var u AppUser
	var email, storeID sql.NullString
	var lastLogin sql.NullTime
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, COALESCE(display_name, COALESCE(email,'')) AS name,
		       email, role, is_active, store_id::TEXT, last_login
		FROM app_users WHERE id = $1 AND organization_id = $2
	`, id, orgID).Scan(&u.ID, &u.Name, &email, &u.Role, &u.IsActive, &storeID, &lastLogin)
	if err != nil {
		slog.Error("users: writeOne", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load user")
		return
	}
	if email.Valid {
		s := email.String
		u.Email = &s
	}
	if storeID.Valid {
		s := storeID.String
		u.StoreID = &s
	}
	if lastLogin.Valid {
		t := lastLogin.Time
		u.LastLogin = &t
		u.LastLoginAt = &t
	}
	response.JSON(w, http.StatusOK, u)
}

func resolveStoreID(r *http.Request, db *sql.DB, orgID string, reqStoreID *string) (string, error) {
	if reqStoreID != nil && uuid.IsValid(*reqStoreID) {
		return *reqStoreID, nil
	}
	var id string
	err := db.QueryRowContext(r.Context(),
		`SELECT id::TEXT FROM stores WHERE organization_id = $1 AND is_active = TRUE ORDER BY created_at ASC LIMIT 1`,
		orgID).Scan(&id)
	if err != nil {
		return "", err
	}
	return id, nil
}

var knownRoles = map[string]bool{
	"super_admin":   true,
	"org_admin":     true,
	"owner":         true,
	"brand_manager": true,
	"store_manager": true,
	"manager":       true,
	"cashier":       true,
	"waiter":        true,
	"kitchen":       true,
	"kds":           true,
	"kiosk":         true,
}

// posCreatableRoles is the subset of app_users.role values that a
// RESTAURANT_MANAGER (or any non-HQ caller) is allowed to mint or assign.
// HQ-tier roles must be created through admin_users by an HQ admin.
var posCreatableRoles = map[string]bool{
	"manager": true,
	"cashier": true,
	"waiter":  true,
	"kitchen": true,
	"kds":     true,
	"kiosk":   true,
}

func validRole(role string) bool {
	return knownRoles[role]
}

// isHQTier reports whether the caller carries an HQ-level org_role claim.
// Used by tenant-scope guards in the team CRUD handlers.
func isHQTier(orgRole string) bool {
	return orgRole == "HQ_ADMIN" || orgRole == "HQ_MANAGER"
}
