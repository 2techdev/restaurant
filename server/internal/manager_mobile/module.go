// Package manager_mobile exposes the manager mobile-app endpoints
// (dashboard, notifications, realtime WS). Route stubs only — real
// dashboard aggregation + push lands in a parallel session.
package manager_mobile

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

// RegisterRoutes wires manager-app routes. All require the manager,
// admin, or owner role.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/manager/dashboard", m.stub("dashboard"))
	mux.HandleFunc("GET /api/v1/manager/notifications", m.stub("list_notifications"))
	mux.HandleFunc("POST /api/v1/manager/notifications/{id}/ack", m.stub("ack_notification"))
	mux.HandleFunc("GET /api/v1/manager/alerts", m.stub("list_alerts"))
	mux.HandleFunc("GET /api/v1/manager/realtime", m.stub("ws_realtime"))
}

func (m *Module) stub(op string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if middleware.GetTenantID(r.Context()) == "" {
			response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
			return
		}
		role := middleware.GetRole(r.Context())
		if role != "manager" && role != "admin" && role != "owner" {
			response.Error(w, http.StatusForbidden, "FORBIDDEN", "Manager role or higher required")
			return
		}
		response.ErrorWithDetails(w, http.StatusNotImplemented, "NOT_IMPLEMENTED",
			"Manager-mobile endpoint not yet implemented",
			map[string]string{"module": "manager_mobile", "op": op})
	}
}
