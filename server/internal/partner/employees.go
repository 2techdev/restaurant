package partner

import (
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/crypto"
	"github.com/gastrocore/server/internal/shared/response"
)

func (m *Module) handleEmployeeList(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, "MANAGER"); !ok {
		return
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, email, name, role, status, last_login_at, created_at
		  FROM partner_employees
		 ORDER BY created_at DESC
	`)
	if err != nil {
		slog.Error("partner: employee list", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list")
		return
	}
	defer rows.Close()
	out := []employeeDTO{}
	for rows.Next() {
		var e employeeDTO
		var last sql.NullTime
		if err := rows.Scan(&e.ID, &e.Email, &e.Name, &e.Role, &e.Status, &last, &e.CreatedAt); err != nil {
			continue
		}
		if last.Valid {
			t := last.Time
			e.LastLoginAt = &t
		}
		out = append(out, e)
	}
	response.JSON(w, http.StatusOK, map[string]any{"data": out})
}

type employeeUpsertRequest struct {
	Email    string  `json:"email"`
	Name     string  `json:"name"`
	Role     string  `json:"role"`
	Password *string `json:"password,omitempty"`
	Status   *string `json:"status,omitempty"`
}

func (m *Module) handleEmployeeCreate(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, "OPERATOR"); !ok {
		return
	}
	var req employeeUpsertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
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
	if !validPartnerRole(req.Role) {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "Invalid role")
		return
	}
	plain := ""
	if req.Password != nil {
		plain = strings.TrimSpace(*req.Password)
	}
	generated := ""
	if plain == "" {
		p, err := randomPassword(14)
		if err != nil {
			response.Error(w, http.StatusInternalServerError, "INTERNAL", "Failed to generate password")
			return
		}
		plain = p
		generated = p
	}
	if len(plain) < 6 {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "Password must be at least 6 characters")
		return
	}
	hash, err := crypto.HashPassword(plain)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "INTERNAL", "Failed to hash password")
		return
	}
	var id string
	err = m.db.QueryRowContext(r.Context(), `
		INSERT INTO partner_employees (email, name, password_hash, role)
		VALUES ($1, $2, $3, $4)
		RETURNING id
	`, req.Email, req.Name, hash, req.Role).Scan(&id)
	if err != nil {
		if strings.Contains(err.Error(), "partner_employees_email_key") {
			response.Error(w, http.StatusConflict, "DUPLICATE", "Email already in use")
			return
		}
		slog.Error("partner: employee create", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create")
		return
	}
	response.JSON(w, http.StatusCreated, map[string]any{
		"id":                 id,
		"email":              req.Email,
		"generated_password": generated, // empty when caller supplied a password
	})
}

func (m *Module) handleEmployeeUpdate(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, "OPERATOR"); !ok {
		return
	}
	id := r.PathValue("id")
	var req employeeUpsertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	if req.Role != "" && !validPartnerRole(req.Role) {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "Invalid role")
		return
	}
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE partner_employees SET
		  name       = COALESCE(NULLIF($2,''), name),
		  role       = COALESCE(NULLIF($3,''), role),
		  status     = COALESCE(NULLIF($4,''), status),
		  updated_at = NOW()
		WHERE id = $1
	`, id, strings.TrimSpace(req.Name), req.Role, deref(req.Status))
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Employee not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

func (m *Module) handleEmployeeDelete(w http.ResponseWriter, r *http.Request) {
	callerID, ok := m.requirePartner(w, r, "OPERATOR")
	if !ok {
		return
	}
	id := r.PathValue("id")
	if id == callerID {
		response.Error(w, http.StatusBadRequest, "SELF_DELETE", "Cannot delete your own account")
		return
	}
	res, err := m.db.ExecContext(r.Context(), `DELETE FROM partner_employees WHERE id=$1`, id)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Employee not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func (m *Module) handleEmployeeResetPassword(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, "OPERATOR"); !ok {
		return
	}
	id := r.PathValue("id")
	plain, err := randomPassword(14)
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
		`UPDATE partner_employees SET password_hash=$1, updated_at=NOW() WHERE id=$2`, hash, id)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to reset")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Employee not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"generated_password": plain})
}

// suppress unused
var _ = time.Time{}

const passwordAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789"

func randomPassword(n int) (string, error) {
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

func validPartnerRole(role string) bool {
	switch role {
	case "OPERATOR", "BD", "MANAGER", "EMPLOYEE":
		return true
	}
	return false
}
