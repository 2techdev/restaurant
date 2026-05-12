package partner

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/auth"
	"github.com/gastrocore/server/internal/shared/crypto"
	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// Partner JWTs carry a small subset of the auth.Claims shape so the existing
// middleware can authenticate them. We stuff the partner_employees role into
// OrgRole as PARTNER_<role> so it never collides with admin_users.org_role
// (HQ_ADMIN, RESTAURANT_MANAGER, etc). Downstream `requirePartner` checks
// that prefix to gate /api/v1/partner/* routes.

const partnerRolePrefix = "PARTNER_"

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type employeeDTO struct {
	ID          string     `json:"id"`
	Email       string     `json:"email"`
	Name        string     `json:"name"`
	Role        string     `json:"role"`   // OPERATOR | BD | MANAGER | EMPLOYEE
	Status      string     `json:"status"` // active | disabled
	LastLoginAt *time.Time `json:"last_login_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
}

type loginResponse struct {
	AccessToken string      `json:"access_token"`
	ExpiresIn   int         `json:"expires_in"`
	TokenType   string      `json:"token_type"`
	User        employeeDTO `json:"user"`
}

func (m *Module) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	if req.Email == "" || req.Password == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "email and password are required")
		return
	}

	var (
		id, name, role, status, passwordHash string
		lastLogin                            sql.NullTime
		createdAt                            time.Time
	)
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, name, role, status, password_hash, last_login_at, created_at
		  FROM partner_employees
		 WHERE email = $1
	`, req.Email).Scan(&id, &name, &role, &status, &passwordHash, &lastLogin, &createdAt)
	if err == sql.ErrNoRows {
		// Dummy hash to keep constant-time
		crypto.VerifyPassword(req.Password, "pbkdf2$sha256$100000$AAAA$BBBB")
		response.Error(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Geçersiz e-posta veya şifre")
		return
	}
	if err != nil {
		slog.Error("partner: login query", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Login failed")
		return
	}
	if !crypto.VerifyPassword(req.Password, passwordHash) {
		response.Error(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Geçersiz e-posta veya şifre")
		return
	}
	if status != "active" {
		response.Error(w, http.StatusForbidden, "ACCOUNT_INACTIVE", "Hesap pasifleştirilmiş")
		return
	}

	_, _ = m.db.ExecContext(r.Context(), `UPDATE partner_employees SET last_login_at=NOW() WHERE id=$1`, id)

	token, err := m.jwt.GenerateToken(auth.Claims{
		UserID:  id,
		Role:    "partner",
		OrgRole: partnerRolePrefix + role,
	})
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "TOKEN_ERROR", "Failed to generate token")
		return
	}

	user := employeeDTO{
		ID: id, Email: req.Email, Name: name, Role: role, Status: status,
		CreatedAt: createdAt,
	}
	if lastLogin.Valid {
		t := lastLogin.Time
		user.LastLoginAt = &t
	}
	response.JSON(w, http.StatusOK, loginResponse{
		AccessToken: token,
		ExpiresIn:   int(m.cfg.JWTExpiry.Seconds()),
		TokenType:   "Bearer",
		User:        user,
	})
}

func (m *Module) handleMe(w http.ResponseWriter, r *http.Request) {
	id, ok := m.requirePartner(w, r, "")
	if !ok {
		return
	}
	var u employeeDTO
	var lastLogin sql.NullTime
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, email, name, role, status, last_login_at, created_at
		  FROM partner_employees WHERE id = $1
	`, id).Scan(&u.ID, &u.Email, &u.Name, &u.Role, &u.Status, &lastLogin, &u.CreatedAt)
	if err != nil {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "session expired")
		return
	}
	if lastLogin.Valid {
		t := lastLogin.Time
		u.LastLoginAt = &t
	}
	response.JSON(w, http.StatusOK, u)
}

// requirePartner extracts the partner_employees ID from the JWT context and
// (optionally) enforces a minimum role. Returns user_id + ok. Writes the
// 401/403 response itself when not ok so callers just `return`.
//
// minRole semantics:
//   ""          → any active partner employee
//   "EMPLOYEE"  → any active partner employee
//   "MANAGER"   → MANAGER or above
//   "BD"        → BD or above
//   "OPERATOR"  → OPERATOR only (god mode)
func (m *Module) requirePartner(w http.ResponseWriter, r *http.Request, minRole string) (string, bool) {
	// main.go's authGate already validates the bearer token and stuffs
	// claims into context. Pull the partner_employee user_id + role prefix.
	userID := middleware.GetUserID(r.Context())
	orgRole := middleware.GetOrgRole(r.Context())
	if userID == "" || !strings.HasPrefix(orgRole, partnerRolePrefix) {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Partner authentication required")
		return "", false
	}
	role := strings.TrimPrefix(orgRole, partnerRolePrefix)
	if !roleAtLeast(role, minRole) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Insufficient role")
		return "", false
	}
	return userID, true
}

var roleRank = map[string]int{
	"EMPLOYEE": 1,
	"MANAGER":  2,
	"BD":       3,
	"OPERATOR": 4,
}

func roleAtLeast(have, min string) bool {
	if min == "" || min == "EMPLOYEE" {
		return roleRank[have] >= 1
	}
	return roleRank[have] >= roleRank[min]
}
