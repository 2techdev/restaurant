package orders

import (
	"database/sql"
	"net/http"
)

// Module is the orders module handling order storage, query, and aggregation.
type Module struct {
	db *sql.DB
}

// NewModule creates a new orders module.
func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

// RegisterRoutes registers all order routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/orders", m.handleListOrders)
	mux.HandleFunc("POST /api/v1/orders", m.handleCreateOrder)
	mux.HandleFunc("GET /api/v1/orders/summary", m.handleOrderSummary)
	mux.HandleFunc("GET /api/v1/orders/{id}", m.handleGetOrder)
}
