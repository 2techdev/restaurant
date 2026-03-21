package dashboard

import (
	"database/sql"
	"net/http"
)

// Module handles dashboard statistics and revenue analytics for the admin panel.
type Module struct {
	db *sql.DB
}

// NewModule creates a new dashboard module.
func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

// RegisterRoutes registers dashboard routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/dashboard/stats", m.handleStats)
	mux.HandleFunc("GET /api/v1/dashboard/revenue", m.handleRevenue)
}
