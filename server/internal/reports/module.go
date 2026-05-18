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
	mux.HandleFunc("GET /api/v1/reports/weekly", m.handleWeeklyReport)
	mux.HandleFunc("GET /api/v1/reports/monthly", m.handleMonthlyReport)
	mux.HandleFunc("GET /api/v1/reports/products", m.handleProductReport)
	mux.HandleFunc("GET /api/v1/reports/staff", m.handleStaffReport)
	mux.HandleFunc("GET /api/v1/reports/shifts", m.handleShiftReport)

	// Coverage extension (016): top-sellers, hourly, MWST, CSV export.
	mux.HandleFunc("GET /api/v1/reports/top-sellers", m.handleTopSellers)
	mux.HandleFunc("GET /api/v1/reports/hourly", m.handleHourlyReport)
	mux.HandleFunc("GET /api/v1/reports/mwst", m.handleMWSTReport)
	mux.HandleFunc("GET /api/v1/reports/export", m.handleExport)

	// Sales Dashboard Suite (2026-05-17) — Lightspeed-style aggregated
	// dashboard endpoints. Each returns a single envelope so the
	// front-end can render a full page in one round-trip.
	mux.HandleFunc("GET /api/v1/reports/sales-summary", m.HandleSalesSummary)
	mux.HandleFunc("GET /api/v1/reports/sales-hourly", m.HandleSalesHourly)
	mux.HandleFunc("GET /api/v1/reports/staff-performance", m.HandleStaffPerformance)
}
