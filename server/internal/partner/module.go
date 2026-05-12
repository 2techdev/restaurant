// Package partner exposes the operator-facing routes under /api/v1/partner/*
// that power partner.gastrocore.ch. Auth lives in this module (its own
// partner_employees table — separate identities from admin_users) and the
// CRUD surface for dealers, editions, brands (organizations), stores
// (tenants), partner employees, and app_versions lives here too.
//
// Backend modules in internal/auth, internal/org, internal/stores already
// own the customer-facing tenant/org logic; this module is purely the
// gastrocore-staff operator surface and reuses lower-level helpers.
package partner

import (
	"database/sql"
	"net/http"

	"github.com/gastrocore/server/internal/auth"
	"github.com/gastrocore/server/internal/shared/config"
)

type Module struct {
	db  *sql.DB
	cfg *config.Config
	jwt *auth.JWTService
}

func NewModule(db *sql.DB, cfg *config.Config) *Module {
	return &Module{
		db:  db,
		cfg: cfg,
		jwt: auth.NewJWTService(cfg.JWTSecret, cfg.JWTExpiry),
	}
}

func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// Auth — public (no Bearer required)
	mux.HandleFunc("POST /api/v1/partner/auth/login", m.handleLogin)
	mux.HandleFunc("POST /api/v1/partner/auth/me", m.handleMe)

	// Dashboard
	mux.HandleFunc("GET /api/v1/partner/dashboard", m.handleDashboard)

	// Brands (organizations table)
	mux.HandleFunc("GET /api/v1/partner/brands", m.handleBrandList)
	mux.HandleFunc("POST /api/v1/partner/brands", m.handleBrandCreate)
	mux.HandleFunc("PUT /api/v1/partner/brands/{id}", m.handleBrandUpdate)
	mux.HandleFunc("DELETE /api/v1/partner/brands/{id}", m.handleBrandDelete)

	// Stores (tenants table)
	mux.HandleFunc("GET /api/v1/partner/stores", m.handleStoreList)
	mux.HandleFunc("POST /api/v1/partner/stores", m.handleStoreCreate)
	mux.HandleFunc("GET /api/v1/partner/stores/{id}", m.handleStoreGet)
	mux.HandleFunc("PUT /api/v1/partner/stores/{id}", m.handleStoreUpdate)
	mux.HandleFunc("DELETE /api/v1/partner/stores/{id}", m.handleStoreDelete)

	// Editions
	mux.HandleFunc("GET /api/v1/partner/editions", m.handleEditionList)
	mux.HandleFunc("POST /api/v1/partner/editions", m.handleEditionCreate)
	mux.HandleFunc("PUT /api/v1/partner/editions/{id}", m.handleEditionUpdate)
	mux.HandleFunc("DELETE /api/v1/partner/editions/{id}", m.handleEditionDelete)

	// Partner employees
	mux.HandleFunc("GET /api/v1/partner/employees", m.handleEmployeeList)
	mux.HandleFunc("POST /api/v1/partner/employees", m.handleEmployeeCreate)
	mux.HandleFunc("PUT /api/v1/partner/employees/{id}", m.handleEmployeeUpdate)
	mux.HandleFunc("DELETE /api/v1/partner/employees/{id}", m.handleEmployeeDelete)
	mux.HandleFunc("POST /api/v1/partner/employees/{id}/reset-password", m.handleEmployeeResetPassword)
}
