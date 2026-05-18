// Package bexio exposes the Bexio (Swiss accounting SaaS) integration
// admin endpoints. Route stubs only — the real OAuth + sync workers land
// in a parallel session.
package bexio

import (
	"database/sql"
	"net/http"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

type Module struct {
	db *sql.DB
}

func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

// RegisterRoutes wires admin-only Bexio integration routes. All require
// the owner role: connecting accounting is sensitive.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /admin/integrations/bexio/status", m.stub("status"))
	mux.HandleFunc("POST /admin/integrations/bexio/connect", m.stub("connect_init"))
	mux.HandleFunc("GET /admin/integrations/bexio/callback", m.stubPublic("oauth_callback"))
	mux.HandleFunc("POST /admin/integrations/bexio/disconnect", m.stub("disconnect"))
	mux.HandleFunc("POST /admin/integrations/bexio/sync/run", m.stub("manual_sync"))
	mux.HandleFunc("GET /admin/integrations/bexio/sync/history", m.stub("sync_history"))
	mux.HandleFunc("GET /admin/integrations/bexio/mappings", m.stub("list_mappings"))
	mux.HandleFunc("PUT /admin/integrations/bexio/mappings", m.stub("update_mappings"))
}

func (m *Module) stub(op string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if middleware.GetTenantID(r.Context()) == "" {
			response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
			return
		}
		role := middleware.GetRole(r.Context())
		if role != "owner" && role != "admin" {
			response.Error(w, http.StatusForbidden, "FORBIDDEN", "Admin/owner role required")
			return
		}
		response.ErrorWithDetails(w, http.StatusNotImplemented, "NOT_IMPLEMENTED",
			"Bexio endpoint not yet implemented",
			map[string]string{"module": "bexio", "op": op})
	}
}

// stubPublic is used for the OAuth callback which arrives without a JWT
// (Bexio redirects the user's browser with a code parameter). The state
// param will carry the tenant binding; real handler validates that.
func (m *Module) stubPublic(op string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		response.ErrorWithDetails(w, http.StatusNotImplemented, "NOT_IMPLEMENTED",
			"Bexio OAuth callback not yet implemented",
			map[string]string{"module": "bexio", "op": op})
	}
}
