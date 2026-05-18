// Package loyalty exposes the customer loyalty endpoints (accounts, earn,
// redeem, tiers). This file ships route stubs only — handlers return 501
// Not Implemented so parallel work on the model/business layer can land
// without breaking the build. A follow-up commit (parallel session) will
// replace each notImplemented handler with the real query/mutation.
//
// Route shape was pinned ahead of time so the backoffice + Flutter clients
// can stub against the contract.
package loyalty

import (
	"database/sql"
	"net/http"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// Module is the loyalty HTTP module. Holds the *sql.DB for the real
// handlers added by the model session.
type Module struct {
	db *sql.DB
}

// NewModule builds the module.
func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

// RegisterRoutes wires the loyalty routes onto the given mux. All routes
// require a tenant-scoped JWT (the main auth gate enforces that for
// /api/v1/*); the handler additionally checks the role where appropriate.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// Customer-facing read.
	mux.HandleFunc("GET /api/v1/loyalty/accounts/{customer_id}", m.stub("get_account"))
	mux.HandleFunc("GET /api/v1/loyalty/accounts/{customer_id}/history", m.stub("get_history"))
	mux.HandleFunc("GET /api/v1/loyalty/tiers", m.stub("list_tiers"))

	// Earn / redeem mutations.
	mux.HandleFunc("POST /api/v1/loyalty/accounts/{customer_id}/earn", m.stub("earn"))
	mux.HandleFunc("POST /api/v1/loyalty/accounts/{customer_id}/redeem", m.stub("redeem"))
	mux.HandleFunc("POST /api/v1/loyalty/accounts/{customer_id}/adjust", m.stub("adjust"))

	// Admin (tier + ruleset config).
	mux.HandleFunc("POST /admin/loyalty/tiers", m.stubAdmin("admin_create_tier"))
	mux.HandleFunc("PUT /admin/loyalty/tiers/{id}", m.stubAdmin("admin_update_tier"))
	mux.HandleFunc("DELETE /admin/loyalty/tiers/{id}", m.stubAdmin("admin_delete_tier"))
	mux.HandleFunc("GET /admin/loyalty/rules", m.stubAdmin("admin_list_rules"))
	mux.HandleFunc("PUT /admin/loyalty/rules", m.stubAdmin("admin_update_rules"))
}

// stub returns a 501 Not Implemented JSON response with the operation tag
// so the client side can wire mocks/feature flags against a stable code.
func (m *Module) stub(op string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if middleware.GetTenantID(r.Context()) == "" {
			response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
			return
		}
		response.ErrorWithDetails(w, http.StatusNotImplemented, "NOT_IMPLEMENTED",
			"Loyalty endpoint not yet implemented",
			map[string]string{"module": "loyalty", "op": op})
	}
}

// stubAdmin adds an admin-only role check on top of stub.
func (m *Module) stubAdmin(op string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if middleware.GetTenantID(r.Context()) == "" {
			response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
			return
		}
		role := middleware.GetRole(r.Context())
		if role != "admin" && role != "owner" {
			response.Error(w, http.StatusForbidden, "FORBIDDEN", "Admin role required")
			return
		}
		response.ErrorWithDetails(w, http.StatusNotImplemented, "NOT_IMPLEMENTED",
			"Loyalty admin endpoint not yet implemented",
			map[string]string{"module": "loyalty", "op": op})
	}
}
