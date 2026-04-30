package audit

import (
	"database/sql"
	"net/http"
)

// Module exposes /api/v1/audit-log: paginated read access to the audit_log
// table, with optional filters by date range, user_id and action.
type Module struct {
	db *sql.DB
}

func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/audit-log", m.handleList)
}
