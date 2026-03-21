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

// StripeConfig holds Stripe credentials loaded from environment variables.
type StripeConfig struct {
	SecretKey      string
	WebhookSecret  string
	SuccessURLBase string
}

// Module is the online-ordering module.
type Module struct {
	db        *sql.DB
	kdsNotify KDSNotifier // optional; nil means no KDS notification
	wsHub     *OnlineHub  // optional; nil means no real-time WS push
	stripeCfg StripeConfig
}

// NewModule creates a new online ordering module.
// kdsNotify and wsHub may be nil if those integrations are not needed.
func NewModule(db *sql.DB, kdsNotify KDSNotifier, wsHub *OnlineHub) *Module {
	return &Module{db: db, kdsNotify: kdsNotify, wsHub: wsHub}
}

// NewModuleWithStripe creates a new online ordering module with Stripe support.
func NewModuleWithStripe(db *sql.DB, kdsNotify KDSNotifier, wsHub *OnlineHub, stripe StripeConfig) *Module {
	return &Module{db: db, kdsNotify: kdsNotify, wsHub: wsHub, stripeCfg: stripe}
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

	// Order status update (called by POS staff)
	mux.HandleFunc("PUT /api/v1/online/orders/{orderId}/status", m.handleUpdateOrderStatus)

	// Real-time WebSocket for order updates
	if m.wsHub != nil {
		mux.HandleFunc("GET /ws/online/orders/live", m.wsHub.serveWS)
	}

	// Stripe payment (no auth — validated by order_id + restaurant_id)
	mux.HandleFunc("POST /api/v1/online/payment/checkout", m.handleCreateCheckout)

	// Stripe webhook (signature verified internally)
	mux.HandleFunc("POST /api/v1/online/payment/webhook", m.handleStripeWebhook)
}
