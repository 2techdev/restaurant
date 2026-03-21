package reports

import (
	"database/sql"
	"net/http"
)

// Module is the reports module handling sales reports, product performance,
// staff performance, shift summaries, and MWST breakdowns.
type Module struct {
	db *sql.DB
}

// NewModule creates a new reports module.
func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

// RegisterRoutes registers all report routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/reports/daily", m.handleDailyReport)
	mux.HandleFunc("GET /api/v1/reports/products", m.handleProductReport)
	mux.HandleFunc("GET /api/v1/reports/staff", m.handleStaffReport)
	mux.HandleFunc("GET /api/v1/reports/shifts", m.handleShiftReport)
	mux.HandleFunc("GET /api/v1/reports/sales", m.handleSalesReport)
	mux.HandleFunc("GET /api/v1/reports/mwst", m.handleMWSTReport)
}
