// Package online provides public HTTP endpoints for the GastroCore Online
// Ordering system. These endpoints require NO authentication — they are
// called by customers scanning a QR code at their table.
package online

import (
	"database/sql"
	"net/http"
)

// KDSNotifier is a narrow interface so that the online module can notify the
// KDS hub about new orders without importing the kds package directly.
type KDSNotifier interface {
	// NotifyNewOrder signals that a new order ticket was created.
	NotifyNewOrder(tenantID, ticketID string, orderNumber int)
}

// Module is the online-ordering module.
type Module struct {
	db         *sql.DB
	kdsNotify  KDSNotifier // optional; nil means no KDS notification
}

// NewModule creates a new online ordering module.
// kdsNotify may be nil if KDS integration is not needed.
func NewModule(db *sql.DB, kdsNotify KDSNotifier) *Module {
	return &Module{db: db, kdsNotify: kdsNotify}
}

// RegisterRoutes registers all public online ordering routes.
// Routes are under /api/v1/online/ — no auth middleware applied.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// Standalone demo page — no backend required, fully self-contained HTML.
	mux.HandleFunc("GET /demo", handleDemo)
	mux.HandleFunc("GET /demo/", handleDemo)

	// Public menu (no auth)
	mux.HandleFunc("GET /api/v1/online/menu/{restaurantId}", m.handleGetMenu)

	// Order placement (no auth — restaurant_id in body)
	mux.HandleFunc("POST /api/v1/online/orders", m.handlePlaceOrder)

	// Order status polling (no auth)
	mux.HandleFunc("GET /api/v1/online/orders/{orderId}/status", m.handleGetOrderStatus)
}
