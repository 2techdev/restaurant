package orders

import (
	"net/http"

	"github.com/gastrocore/server/internal/shared/response"
)

// handleListOrders returns orders with filters for date, status, and branch.
// GET /api/v1/orders
func (m *Module) handleListOrders(w http.ResponseWriter, r *http.Request) {
	// TODO: Extract tenant_id from context
	// TODO: Parse query params: date_from, date_to, status, branch_id, cursor, limit
	// TODO: Query tickets with filters and pagination

	_ = r.URL.Query().Get("status")
	_ = r.URL.Query().Get("date_from")
	_ = r.URL.Query().Get("date_to")

	response.Paginated(w, []Ticket{}, "", false)
}

// handleGetOrder returns a single order with its items, bills, and payments.
// GET /api/v1/orders/{id}
func (m *Module) handleGetOrder(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	_ = id

	// TODO: Fetch ticket by ID and tenant
	// TODO: Fetch order items with modifiers
	// TODO: Fetch bills and payments
	// TODO: Return composed response

	response.JSON(w, http.StatusOK, map[string]any{
		"ticket":   nil,
		"items":    []any{},
		"bills":    []any{},
		"payments": []any{},
	})
}

// handleOrderSummary returns aggregated order statistics.
// GET /api/v1/orders/summary
func (m *Module) handleOrderSummary(w http.ResponseWriter, r *http.Request) {
	// TODO: Parse date range from query params
	// TODO: Aggregate order totals, counts, averages

	response.JSON(w, http.StatusOK, map[string]any{
		"total_orders":    0,
		"total_revenue":   0,
		"average_order":   0,
		"orders_by_type":  map[string]int{},
		"orders_by_status": map[string]int{},
	})
}
