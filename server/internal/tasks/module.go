// Package tasks exposes the task / HACCP-checklist endpoints (recurring
// task templates + scheduled task_instances). Route stubs only.
package tasks

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

// RegisterRoutes wires:
//   - Staff-facing /api/v1/tasks/* — list today's assigned tasks, complete one.
//   - Admin /admin/tasks/* — template CRUD + assignment.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/tasks", m.stub("list_assigned"))
	mux.HandleFunc("GET /api/v1/tasks/{id}", m.stub("get_instance"))
	mux.HandleFunc("POST /api/v1/tasks/{id}/complete", m.stub("complete_instance"))
	mux.HandleFunc("POST /api/v1/tasks/{id}/skip", m.stub("skip_instance"))

	mux.HandleFunc("GET /admin/tasks/templates", m.stubAdmin("admin_list_templates"))
	mux.HandleFunc("POST /admin/tasks/templates", m.stubAdmin("admin_create_template"))
	mux.HandleFunc("PUT /admin/tasks/templates/{id}", m.stubAdmin("admin_update_template"))
	mux.HandleFunc("DELETE /admin/tasks/templates/{id}", m.stubAdmin("admin_delete_template"))
	mux.HandleFunc("GET /admin/tasks/instances", m.stubAdmin("admin_list_instances"))
	mux.HandleFunc("GET /admin/tasks/haccp/report", m.stubAdmin("admin_haccp_report"))
}

func (m *Module) stub(op string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if middleware.GetTenantID(r.Context()) == "" {
			response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
			return
		}
		response.ErrorWithDetails(w, http.StatusNotImplemented, "NOT_IMPLEMENTED",
			"Tasks endpoint not yet implemented",
			map[string]string{"module": "tasks", "op": op})
	}
}

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
			"Tasks admin endpoint not yet implemented",
			map[string]string{"module": "tasks", "op": op})
	}
}
