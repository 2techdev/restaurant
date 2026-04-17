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

// handleList returns all app_users for the tenant (across all stores).
// GET /api/v1/users
func (m *Module) handleList(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if !uuid.IsValid(orgID) {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, COALESCE(display_name, COALESCE(email,'')) AS name,
		       email, role, is_active, store_id::TEXT, last_login
		FROM app_users
		WHERE organization_id = $1
		ORDER BY role, display_name
	`, orgID)
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
	orgID := middleware.GetTenantID(r.Context())
	if !uuid.IsValid(orgID) {
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
	if req.Role == "" {
		req.Role = "waiter"
	}
	if !validRole(req.Role) {
		response.Error(w, http.StatusBadRequest, "INVALID_ROLE", "unknown role")
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
	orgID := middleware.GetTenantID(r.Context())
	id := r.PathValue("id")
	if !uuid.IsValid(orgID) || !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid tenant or id")
		return
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
		WHERE id = $1 AND organization_id = $2
	`, id, orgID, req.Name, emailParam, req.Role, req.IsActive, passwordHash, pinHash)
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
	orgID := middleware.GetTenantID(r.Context())
	id := r.PathValue("id")
	if !uuid.IsValid(orgID) || !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid tenant or id")
		return
	}
	result, err := m.db.ExecContext(r.Context(), `
		UPDATE app_users SET is_active = FALSE, updated_at = NOW()
		WHERE id = $1 AND organization_id = $2
	`, id, orgID)
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
	orgID := middleware.GetTenantID(r.Context())
	id := r.PathValue("id")
	if !uuid.IsValid(orgID) || !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid tenant or id")
		return
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
	`, id, orgID, h)
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
	"super_admin":    true,
	"org_admin":      true,
	"owner":          true,
	"brand_manager":  true,
	"store_manager":  true,
	"manager":        true,
	"cashier":        true,
	"waiter":         true,
	"kitchen":        true,
	"kds":            true,
	"kiosk":          true,
}

func validRole(role string) bool {
	return knownRoles[role]
}
