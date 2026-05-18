// Package osd exposes the Order Status Display endpoints — public
// per-restaurant page that shows the "now serving" / "preparing" ticket
// list for customers waiting at the counter. No JWT required; tenant
// scoped by slug.
package osd

import (
	"database/sql"
	"net/http"

	"github.com/gastrocore/server/internal/shared/response"
)

type Module struct {
	db *sql.DB
}

func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

// RegisterRoutes wires public OSD endpoints. These bypass the JWT gate
// because the OSD screen runs from a public URL.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/osd/{slug}/active-tickets", m.stub("active_tickets"))
	mux.HandleFunc("GET /api/v1/osd/{slug}/now-serving", m.stub("now_serving"))
	mux.HandleFunc("GET /api/v1/osd/{slug}/realtime", m.stub("ws_realtime"))
}

func (m *Module) stub(op string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		slug := r.PathValue("slug")
		if slug == "" {
			response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "slug is required")
			return
		}
		response.ErrorWithDetails(w, http.StatusNotImplemented, "NOT_IMPLEMENTED",
			"OSD endpoint not yet implemented",
			map[string]string{"module": "osd", "op": op, "slug": slug})
	}
}
