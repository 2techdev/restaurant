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
	// Organization
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

	// Admin Users (web dashboard users)
	mux.HandleFunc("GET /api/v1/admin/users", m.handleListAdminUsers)
	mux.HandleFunc("POST /api/v1/admin/users", m.handleCreateAdminUser)
	mux.HandleFunc("PUT /api/v1/admin/users/{id}", m.handleUpdateAdminUser)
	mux.HandleFunc("DELETE /api/v1/admin/users/{id}", m.handleDeleteAdminUser)

	// Employees (POS staff per store)
	mux.HandleFunc("GET /api/v1/admin/stores/{id}/employees", m.handleListEmployees)
	mux.HandleFunc("POST /api/v1/admin/stores/{id}/employees", m.handleCreateEmployee)
	mux.HandleFunc("PUT /api/v1/admin/employees/{id}", m.handleUpdateEmployee)
	mux.HandleFunc("DELETE /api/v1/admin/employees/{id}", m.handleDeleteEmployee)

	// Dashboard
	mux.HandleFunc("GET /api/v1/admin/dashboard", m.handleDashboard)
	mux.HandleFunc("GET /api/v1/admin/dashboard/store/{id}", m.handleStoreDashboard)
}
