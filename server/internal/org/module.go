// Package org implements HQ (headquarters) chain-restaurant logic:
// organization-level master menu, lock policies, version history,
// per-tenant inheritance, and cross-restaurant aggregate reports.
//
// Endpoints live under /api/v1/org/... and require an authenticated user
// whose users.organization_id matches the path :orgId. Mutating endpoints
// additionally require an HQ role (HQ_ADMIN or HQ_MANAGER).
package org

import (
	"database/sql"
	"net/http"

	gosync "github.com/gastrocore/server/internal/sync"
)

// Module wires the HQ endpoints. The optional sync hub is used to push
// real-time menu-published notifications to member restaurants. When nil,
// publishing still writes the version row but skips the WS broadcast.
type Module struct {
	db  *sql.DB
	hub *gosync.Hub
}

// NewModule constructs the org module.
func NewModule(db *sql.DB, hub *gosync.Hub) *Module {
	return &Module{db: db, hub: hub}
}

// RegisterRoutes mounts /api/v1/org/* on the supplied mux. JWT auth is
// applied by the global gateway in cmd/server/main.go; per-route role
// checks are inlined in handlers.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// Self
	mux.HandleFunc("GET /api/v1/org/me", m.handleMe)

	// Restaurants (members)
	mux.HandleFunc("GET /api/v1/org/{orgId}/restaurants", m.handleListRestaurants)
	mux.HandleFunc("POST /api/v1/org/{orgId}/restaurants", m.handleCreateRestaurant)
	mux.HandleFunc("DELETE /api/v1/org/{orgId}/restaurants/{restaurantId}", m.handleDetachRestaurant)

	// Master menu
	mux.HandleFunc("GET /api/v1/org/{orgId}/master-menu", m.handleGetMasterMenu)
	mux.HandleFunc("POST /api/v1/org/{orgId}/master-menu/categories", m.handleCreateMasterCategory)
	mux.HandleFunc("PUT /api/v1/org/{orgId}/master-menu/categories/{id}", m.handleUpdateMasterCategory)
	mux.HandleFunc("DELETE /api/v1/org/{orgId}/master-menu/categories/{id}", m.handleDeleteMasterCategory)
	mux.HandleFunc("POST /api/v1/org/{orgId}/master-menu/products", m.handleCreateMasterProduct)
	mux.HandleFunc("PUT /api/v1/org/{orgId}/master-menu/products/{id}", m.handleUpdateMasterProduct)
	mux.HandleFunc("DELETE /api/v1/org/{orgId}/master-menu/products/{id}", m.handleDeleteMasterProduct)
	mux.HandleFunc("POST /api/v1/org/{orgId}/master-menu/publish", m.handlePublishMasterMenu)

	// Policies
	mux.HandleFunc("GET /api/v1/org/{orgId}/policies", m.handleListPolicies)
	mux.HandleFunc("POST /api/v1/org/{orgId}/policies", m.handleCreatePolicy)
	mux.HandleFunc("PUT /api/v1/org/{orgId}/policies/{policyId}", m.handleUpdatePolicy)
	mux.HandleFunc("DELETE /api/v1/org/{orgId}/policies/{policyId}", m.handleDeletePolicy)

	// Reports
	mux.HandleFunc("GET /api/v1/org/{orgId}/reports/aggregate", m.handleAggregateReport)
	mux.HandleFunc("GET /api/v1/org/{orgId}/reports/by-restaurant", m.handleByRestaurantReport)
}
