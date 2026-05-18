// Package order_profiles exposes the order-profile endpoints (saved
// item-combination profiles a cashier can reuse — e.g. "Tagesmenü
// Mittwoch"). Route stubs only; real implementation lands in a parallel
// session.
package order_profiles

import (
	"database/sql"
	"net/http"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// Module is the order_profiles HTTP module.
type Module struct {
	db *sql.DB
}

// NewModule builds the module.
func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

// RegisterRoutes wires order-profile routes.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/order-profiles", m.stub("list"))
	mux.HandleFunc("GET /api/v1/order-profiles/{id}", m.stub("get"))
	mux.HandleFunc("POST /api/v1/order-profiles", m.stub("create"))
	mux.HandleFunc("PUT /api/v1/order-profiles/{id}", m.stub("update"))
	mux.HandleFunc("DELETE /api/v1/order-profiles/{id}", m.stub("delete"))
	mux.HandleFunc("POST /api/v1/order-profiles/{id}/apply", m.stub("apply"))
}

func (m *Module) stub(op string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if middleware.GetTenantID(r.Context()) == "" {
			response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
			return
		}
		response.ErrorWithDetails(w, http.StatusNotImplemented, "NOT_IMPLEMENTED",
			"Order-profile endpoint not yet implemented",
			map[string]string{"module": "order_profiles", "op": op})
	}
}
