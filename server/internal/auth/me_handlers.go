package auth

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/gastrocore/server/internal/shared/crypto"
	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// /api/v1/me/* — operations on the currently signed-in admin user.

func (m *Module) registerMeRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/me/profile", m.handleMeProfile)
	mux.HandleFunc("PUT /api/v1/me/profile", m.handleMeProfileUpdate)
	mux.HandleFunc("PUT /api/v1/me/password", m.handleMePasswordChange)
}

type meProfileDTO struct {
	ID             string `json:"id"`
	OrganizationID string `json:"organization_id"`
	Email          string `json:"email"`
	Name           string `json:"name"`
	Role           string `json:"role"`
	OrgRole        string `json:"org_role"`
}

func (m *Module) handleMeProfile(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserID(r.Context())
	if uid == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Not signed in")
		return
	}
	var p meProfileDTO
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, organization_id, email, name, role
		  FROM admin_users WHERE id = $1
	`, uid).Scan(&p.ID, &p.OrganizationID, &p.Email, &p.Name, &p.Role)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			response.Error(w, http.StatusNotFound, "NOT_FOUND", "User not found")
			return
		}
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load profile")
		return
	}
	p.OrgRole = middleware.GetOrgRole(r.Context())
	response.JSON(w, http.StatusOK, p)
}

type updateProfileRequest struct {
	Name *string `json:"name,omitempty"`
}

func (m *Module) handleMeProfileUpdate(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserID(r.Context())
	if uid == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Not signed in")
		return
	}
	var req updateProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if req.Name == nil || strings.TrimSpace(*req.Name) == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "Name required")
		return
	}
	_, err := m.db.ExecContext(r.Context(),
		`UPDATE admin_users SET name=$1, updated_at=NOW() WHERE id=$2`,
		strings.TrimSpace(*req.Name), uid)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update profile")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

type changePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

func (m *Module) handleMePasswordChange(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserID(r.Context())
	if uid == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Not signed in")
		return
	}
	var req changePasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if len(req.NewPassword) < 6 {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "New password must be at least 6 characters")
		return
	}

	var currentHash string
	err := m.db.QueryRowContext(r.Context(),
		`SELECT password_hash FROM admin_users WHERE id=$1`, uid).Scan(&currentHash)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			response.Error(w, http.StatusNotFound, "NOT_FOUND", "User not found")
			return
		}
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load user")
		return
	}
	if !crypto.VerifyPassword(req.CurrentPassword, currentHash) {
		response.Error(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Current password is incorrect")
		return
	}
	newHash, err := crypto.HashPassword(req.NewPassword)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "INTERNAL", "Failed to hash password")
		return
	}
	if _, err := m.db.ExecContext(r.Context(),
		`UPDATE admin_users SET password_hash=$1, updated_at=NOW() WHERE id=$2`,
		newHash, uid); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update password")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"status": "changed"})
}
