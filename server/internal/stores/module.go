package stores

import (
	"database/sql"
	"net/http"

	"github.com/gastrocore/server/internal/shared/config"
)

// Module is the stores module handling organization, brand, store, and employee management.
type Module struct {
	db  *sql.DB
	cfg *config.Config
}

// NewModule creates a new stores module.
func NewModule(db *sql.DB, cfg *config.Config) *Module {
	return &Module{
		db:  db,
		cfg: cfg,
	}
}

// RegisterRoutes registers all store management routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// ── Tenant-scoped store API (uses JWT brand/store context) ──────────────
	mux.HandleFunc("GET /api/v1/stores", m.handleTenantListStores)
	mux.HandleFunc("POST /api/v1/stores", m.handleTenantCreateStore)
	mux.HandleFunc("GET /api/v1/stores/{id}", m.handleTenantGetStore)
	mux.HandleFunc("PUT /api/v1/stores/{id}", m.handleTenantUpdateStore)
	mux.HandleFunc("GET /api/v1/stores/{id}/settings", m.handleGetSettings)
	mux.HandleFunc("PUT /api/v1/stores/{id}/settings", m.handleUpdateSettings)
	mux.HandleFunc("GET /api/v1/stores/{id}/users", m.handleTenantListUsers)
	mux.HandleFunc("POST /api/v1/stores/{id}/users", m.handleTenantCreateUser)
	mux.HandleFunc("DELETE /api/v1/stores/{id}/users/{uid}", m.handleTenantDeleteUser)
	mux.HandleFunc("GET /api/v1/stores/{id}/sync", m.handleTenantSyncFull)
	mux.HandleFunc("POST /api/v1/stores/{id}/sync", m.handleTenantSyncPush)
	mux.HandleFunc("GET /api/v1/stores/{id}/sync/delta", m.handleTenantSyncDelta)
	// Organization
	mux.HandleFunc("GET /api/v1/admin/organizations", m.handleListOrganizations)
	mux.HandleFunc("GET /api/v1/admin/organization", m.handleGetOrganization)
	mux.HandleFunc("PUT /api/v1/admin/organization", m.handleUpdateOrganization)

	// Brands
	mux.HandleFunc("GET /api/v1/admin/brands", m.handleListBrands)
	mux.HandleFunc("POST /api/v1/admin/brands", m.handleCreateBrand)
	mux.HandleFunc("PUT /api/v1/admin/brands/{id}", m.handleUpdateBrand)
	mux.HandleFunc("DELETE /api/v1/admin/brands/{id}", m.handleDeleteBrand)

	// Stores
	mux.HandleFunc("GET /api/v1/admin/stores", m.handleListStores)
	mux.HandleFunc("POST /api/v1/admin/stores", m.handleCreateStore)
	mux.HandleFunc("GET /api/v1/admin/stores/{id}", m.handleGetStore)
	mux.HandleFunc("PUT /api/v1/admin/stores/{id}", m.handleUpdateStore)
	mux.HandleFunc("DELETE /api/v1/admin/stores/{id}", m.handleDeleteStore)
	mux.HandleFunc("GET /api/v1/admin/stores/{id}/stats", m.handleGetStoreStats)

	// Admin Users (web dashboard users) — superseded by internal/auth's
	// admin_user_crud.go which adds HQ_ADMIN/HQ_MANAGER RBAC and the
	// disable/enable/reset-password endpoints. The legacy handlers in this
	// package are kept (handleListAdminUsers etc.) so callers wiring custom
	// muxes can still reach them, but we no longer register them globally.
	_ = m.handleListAdminUsers
	_ = m.handleCreateAdminUser
	_ = m.handleUpdateAdminUser
	_ = m.handleDeleteAdminUser

	// Employees (POS staff per store)
	mux.HandleFunc("GET /api/v1/admin/stores/{id}/employees", m.handleListEmployees)
	mux.HandleFunc("POST /api/v1/admin/stores/{id}/employees", m.handleCreateEmployee)
	mux.HandleFunc("PUT /api/v1/admin/employees/{id}", m.handleUpdateEmployee)
	mux.HandleFunc("DELETE /api/v1/admin/employees/{id}", m.handleDeleteEmployee)

	// Dashboard
	mux.HandleFunc("GET /api/v1/admin/dashboard", m.handleDashboard)
	mux.HandleFunc("GET /api/v1/admin/dashboard/store/{id}", m.handleStoreDashboard)
}
