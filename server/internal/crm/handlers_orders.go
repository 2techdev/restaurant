package crm

import (
	"database/sql"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// handleCustomerOrders returns the order history for a customer.
//
// We don't have a direct customer_id column on tickets, so we resolve via the
// loyalty_transactions ledger (every redeem/earn carries the ticket_id). For
// customers without loyalty activity we fall back to matching on
// tickets.customer_name (case-insensitive).
//
// GET /api/v1/customers/{id}/orders?limit=50
func (m *Module) handleCustomerOrders(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		tenantID = r.URL.Query().Get("tenant_id")
	}
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	limit := 50
	if l := r.URL.Query().Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 && n <= 200 {
			limit = n
		}
	}

	// Pull customer name to support the fallback match.
	var customerName string
	if err := m.db.QueryRowContext(r.Context(),
		`SELECT name FROM customers WHERE id = $1 AND tenant_id = $2 AND is_deleted = false`,
		id, tenantID).Scan(&customerName); err != nil {
		if err == sql.ErrNoRows {
			response.Error(w, http.StatusNotFound, "NOT_FOUND", "Customer not found")
			return
		}
		slog.Error("crm: load customer", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load customer")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		WITH from_loyalty AS (
			SELECT DISTINCT ticket_id
			FROM loyalty_transactions
			WHERE tenant_id = $1 AND customer_id = $2 AND ticket_id IS NOT NULL
		)
		SELECT t.id::TEXT, t.created_at, t.status, COALESCE(t.channel,''),
		       COALESCE(t.subtotal,0), COALESCE(t.tax_amount,0),
		       COALESCE(t.discount_amount,0), COALESCE(t.total,0)
		FROM tickets t
		WHERE t.tenant_id::TEXT = $1
		  AND t.is_deleted = FALSE
		  AND (
		        t.id::TEXT IN (SELECT ticket_id FROM from_loyalty)
		        OR LOWER(COALESCE(t.customer_name,'')) = LOWER($3)
		      )
		ORDER BY t.created_at DESC
		LIMIT $4
	`, tenantID, id, customerName, limit)
	if err != nil {
		slog.Error("crm: customer orders", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to query orders")
		return
	}
	defer rows.Close()

	type Order struct {
		ID             string    `json:"id"`
		CreatedAt      time.Time `json:"created_at"`
		Status         string    `json:"status"`
		Channel        string    `json:"channel"`
		SubtotalCents  int64     `json:"subtotal_cents"`
		TaxCents       int64     `json:"tax_cents"`
		DiscountCents  int64     `json:"discount_cents"`
		TotalCents     int64     `json:"total_cents"`
	}
	out := make([]Order, 0)
	for rows.Next() {
		var o Order
		if err := rows.Scan(&o.ID, &o.CreatedAt, &o.Status, &o.Channel,
			&o.SubtotalCents, &o.TaxCents, &o.DiscountCents, &o.TotalCents); err == nil {
			out = append(out, o)
		}
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"customer_id": id,
		"count":       len(out),
		"orders":      out,
	})
}
