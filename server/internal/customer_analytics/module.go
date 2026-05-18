// Package customer_analytics exposes admin endpoints for customer
// segmentation + targeted campaigns. Route stubs only — real query
// runner + scheduler land in a parallel session.
package customer_analytics

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

func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// Segments — saved query definitions.
	mux.HandleFunc("GET /admin/segments", m.stub("list_segments"))
	mux.HandleFunc("POST /admin/segments", m.stub("create_segment"))
	mux.HandleFunc("GET /admin/segments/{id}", m.stub("get_segment"))
	mux.HandleFunc("PUT /admin/segments/{id}", m.stub("update_segment"))
	mux.HandleFunc("DELETE /admin/segments/{id}", m.stub("delete_segment"))
	mux.HandleFunc("POST /admin/segments/{id}/run", m.stub("run_segment"))
	mux.HandleFunc("GET /admin/segments/{id}/members", m.stub("segment_members"))

	// Campaigns — targeted promo blasts to segments.
	mux.HandleFunc("GET /admin/campaigns", m.stub("list_campaigns"))
	mux.HandleFunc("POST /admin/campaigns", m.stub("create_campaign"))
	mux.HandleFunc("GET /admin/campaigns/{id}", m.stub("get_campaign"))
	mux.HandleFunc("PUT /admin/campaigns/{id}", m.stub("update_campaign"))
	mux.HandleFunc("DELETE /admin/campaigns/{id}", m.stub("delete_campaign"))
	mux.HandleFunc("POST /admin/campaigns/{id}/send", m.stub("send_campaign"))
	mux.HandleFunc("GET /admin/campaigns/{id}/results", m.stub("campaign_results"))
}

func (m *Module) stub(op string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if middleware.GetTenantID(r.Context()) == "" {
			response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
			return
		}
		role := middleware.GetRole(r.Context())
		if role != "admin" && role != "owner" && role != "manager" {
			response.Error(w, http.StatusForbidden, "FORBIDDEN", "Manager role or higher required")
			return
		}
		response.ErrorWithDetails(w, http.StatusNotImplemented, "NOT_IMPLEMENTED",
			"Customer-analytics endpoint not yet implemented",
			map[string]string{"module": "customer_analytics", "op": op})
	}
}
