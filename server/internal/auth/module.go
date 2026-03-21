package auth

import (
	"database/sql"
	"net/http"

	"github.com/gastrocore/server/internal/shared/config"
)

// Module is the auth module handling device registration, user PIN auth,
// JWT token generation, and cloud admin login.
type Module struct {
	db  *sql.DB
	cfg *config.Config
	jwt *JWTService
}

// NewModule creates a new auth module.
func NewModule(db *sql.DB, cfg *config.Config) *Module {
	return &Module{
		db:  db,
		cfg: cfg,
		jwt: NewJWTService(cfg.JWTSecret, cfg.JWTExpiry),
	}
}

// RegisterRoutes registers all auth routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/auth/device/register", m.handleDeviceRegister)
	mux.HandleFunc("POST /api/v1/auth/device/token", m.handleDeviceToken)
	mux.HandleFunc("POST /api/v1/auth/admin/login", m.handleAdminLogin)
	mux.HandleFunc("POST /api/v1/auth/token/refresh", m.handleTokenRefresh)
}

// ValidateToken exposes the JWT validation for use by middleware.
func (m *Module) ValidateToken(token string) (map[string]string, error) {
	return m.jwt.ValidateToken(token)
}
