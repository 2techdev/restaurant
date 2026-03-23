package orders

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// handleListOrders returns orders with filters for date, status, and branch.
// GET /api/v1/orders
func (m *Module) handleListOrders(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}

	q := r.URL.Query()
	status := q.Get("status")
	dateFrom := q.Get("date_from")
	dateTo := q.Get("date_to")
	limitStr := q.Get("limit")
	cursor := q.Get("cursor") // order ID cursor for keyset pagination

	limit := 50
	if limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 && l <= 200 {
			limit = l
		}
	}

	// Build dynamic query
	args := []any{tenantID}
	where := "t.tenant_id = $1 AND t.is_deleted = FALSE"
	idx := 2

	if status != "" {
		where += " AND t.status = $" + strconv.Itoa(idx)
		args = append(args, status)
		idx++
	}
	if dateFrom != "" {
		if ts, err := time.Parse("2006-01-02", dateFrom); err == nil {
			where += " AND t.created_at >= $" + strconv.Itoa(idx)
			args = append(args, ts)
			idx++
		}
	}
	if dateTo != "" {
		if ts, err := time.Parse("2006-01-02", dateTo); err == nil {
			// Include the full day
			ts = ts.Add(24*time.Hour - time.Nanosecond)
			where += " AND t.created_at <= $" + strconv.Itoa(idx)
			args = append(args, ts)
			idx++
		}
	}
	if cursor != "" {
		where += " AND t.id < $" + strconv.Itoa(idx)
		args = append(args, cursor)
		idx++
	}

	_ = idx // suppress unused warning

	query := `
		SELECT t.id, t.tenant_id, t.order_number, t.order_type,
		       t.table_id, t.waiter_id, t.customer_name, t.guest_count,
		       t.status, t.channel, t.subtotal, t.tax_amount,
		       t.discount_amount, t.discount_type, t.discount_value,
		       t.total, t.notes, t.opened_at, t.closed_at,
		       t.device_id, t.created_at, t.updated_at, t.is_deleted
		FROM tickets t
		WHERE ` + where + `
		ORDER BY t.created_at DESC, t.id DESC
		LIMIT $` + strconv.Itoa(len(args)+1)

	args = append(args, limit+1) // fetch one extra to detect next page

	rows, err := m.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to query orders")
		return
	}
	defer rows.Close()

	tickets := make([]Ticket, 0, limit)
	for rows.Next() {
		var t Ticket
		if err := rows.Scan(
			&t.ID, &t.TenantID, &t.OrderNumber, &t.OrderType,
			&t.TableID, &t.WaiterID, &t.CustomerName, &t.GuestCount,
			&t.Status, &t.Channel, &t.Subtotal, &t.TaxAmount,
			&t.DiscountAmount, &t.DiscountType, &t.DiscountValue,
			&t.Total, &t.Notes, &t.OpenedAt, &t.ClosedAt,
			&t.DeviceID, &t.CreatedAt, &t.UpdatedAt, &t.IsDeleted,
		); err != nil {
			response.Error(w, http.StatusInternalServerError, "SCAN_ERROR", "Failed to scan order row")
			return
		}
		tickets = append(tickets, t)
	}
	if err := rows.Err(); err != nil {
		response.Error(w, http.StatusInternalServerError, "ROWS_ERROR", "Row iteration failed")
		return
	}

	hasMore := len(tickets) > limit
	if hasMore {
		tickets = tickets[:limit]
	}

	nextCursor := ""
	if hasMore && len(tickets) > 0 {
		nextCursor = tickets[len(tickets)-1].ID
	}

	response.Paginated(w, tickets, nextCursor, hasMore)
}

// handleGetOrder returns a single order with its items, bills, and payments.
// GET /api/v1/orders/{id}
func (m *Module) handleGetOrder(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}

	id := r.PathValue("id")
	if id == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "order id is required")
		return
	}

	// Fetch ticket
	var t Ticket
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, order_number, order_type,
		       table_id, waiter_id, customer_name, guest_count,
		       status, channel, subtotal, tax_amount,
		       discount_amount, discount_type, discount_value,
		       total, notes, opened_at, closed_at,
		       device_id, created_at, updated_at, is_deleted
		FROM tickets
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = FALSE
	`, id, tenantID).Scan(
		&t.ID, &t.TenantID, &t.OrderNumber, &t.OrderType,
		&t.TableID, &t.WaiterID, &t.CustomerName, &t.GuestCount,
		&t.Status, &t.Channel, &t.Subtotal, &t.TaxAmount,
		&t.DiscountAmount, &t.DiscountType, &t.DiscountValue,
		&t.Total, &t.Notes, &t.OpenedAt, &t.ClosedAt,
		&t.DeviceID, &t.CreatedAt, &t.UpdatedAt, &t.IsDeleted,
	)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Order not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch order")
		return
	}

	// Fetch order items
	itemRows, err := m.db.QueryContext(r.Context(), `
		SELECT oi.id, oi.tenant_id, oi.ticket_id, oi.product_id, oi.product_name,
		       oi.quantity, oi.unit_price, oi.subtotal, oi.tax_amount, oi.discount_amount,
		       oi.status, oi.sent_to_kitchen, oi.notes, oi.course, oi.created_at, oi.updated_at
		FROM order_items oi
		WHERE oi.ticket_id = $1 AND oi.tenant_id = $2 AND oi.is_deleted = FALSE
		ORDER BY oi.created_at ASC
	`, id, tenantID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch order items")
		return
	}
	defer itemRows.Close()

	items := make([]OrderItem, 0)
	itemIDs := make([]string, 0)
	for itemRows.Next() {
		var item OrderItem
		if err := itemRows.Scan(
			&item.ID, &item.TenantID, &item.TicketID, &item.ProductID, &item.ProductName,
			&item.Quantity, &item.UnitPrice, &item.Subtotal, &item.TaxAmount, &item.DiscountAmount,
			&item.Status, &item.SentToKitchen, &item.Notes, &item.Course, &item.CreatedAt, &item.UpdatedAt,
		); err != nil {
			response.Error(w, http.StatusInternalServerError, "SCAN_ERROR", "Failed to scan item")
			return
		}
		items = append(items, item)
		itemIDs = append(itemIDs, item.ID)
	}

	// Fetch modifiers for all items (if any items exist)
	modifiersByItemID := make(map[string][]OrderItemModifier)
	if len(itemIDs) > 0 {
		// Build IN clause
		inClause := "$1"
		modArgs := []any{itemIDs[0]}
		for i, itemID := range itemIDs[1:] {
			inClause += ", $" + strconv.Itoa(i+2)
			modArgs = append(modArgs, itemID)
		}
		modRows, err := m.db.QueryContext(r.Context(), `
			SELECT id, order_item_id, modifier_id, modifier_name, price_delta, created_at
			FROM order_item_modifiers
			WHERE order_item_id IN (`+inClause+`)
			ORDER BY created_at ASC
		`, modArgs...)
		if err == nil {
			defer modRows.Close()
			for modRows.Next() {
				var mod OrderItemModifier
				if err := modRows.Scan(
					&mod.ID, &mod.OrderItemID, &mod.ModifierID,
					&mod.ModifierName, &mod.PriceDelta, &mod.CreatedAt,
				); err == nil {
					modifiersByItemID[mod.OrderItemID] = append(modifiersByItemID[mod.OrderItemID], mod)
				}
			}
		}
	}

	// Attach modifiers to items
	for i := range items {
		if mods, ok := modifiersByItemID[items[i].ID]; ok {
			items[i].Modifiers = mods
		}
	}

	// Fetch bills
	billRows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, ticket_id, bill_number, subtotal, tax_amount,
		       discount_amount, total, status, created_at, updated_at
		FROM bills
		WHERE ticket_id = $1 AND tenant_id = $2 AND is_deleted = FALSE
		ORDER BY bill_number ASC
	`, id, tenantID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch bills")
		return
	}
	defer billRows.Close()

	bills := make([]Bill, 0)
	billIDs := make([]string, 0)
	for billRows.Next() {
		var b Bill
		if err := billRows.Scan(
			&b.ID, &b.TenantID, &b.TicketID, &b.BillNumber, &b.Subtotal,
			&b.TaxAmount, &b.DiscountAmount, &b.Total, &b.Status, &b.CreatedAt, &b.UpdatedAt,
		); err != nil {
			response.Error(w, http.StatusInternalServerError, "SCAN_ERROR", "Failed to scan bill")
			return
		}
		bills = append(bills, b)
		billIDs = append(billIDs, b.ID)
	}

	// Fetch payments
	payments := make([]Payment, 0)
	if len(billIDs) > 0 {
		payRows, err := m.db.QueryContext(r.Context(), `
			SELECT id, tenant_id, bill_id, ticket_id, payment_method,
			       amount, tip_amount, tendered_amount, change_amount,
			       reference, received_by, paid_at, created_at, updated_at
			FROM payments
			WHERE ticket_id = $1 AND tenant_id = $2 AND is_deleted = FALSE
			ORDER BY paid_at ASC
		`, id, tenantID)
		if err == nil {
			defer payRows.Close()
			for payRows.Next() {
				var p Payment
				if err := payRows.Scan(
					&p.ID, &p.TenantID, &p.BillID, &p.TicketID, &p.PaymentMethod,
					&p.Amount, &p.TipAmount, &p.TenderedAmount, &p.ChangeAmount,
					&p.Reference, &p.ReceivedBy, &p.PaidAt, &p.CreatedAt, &p.UpdatedAt,
				); err == nil {
					payments = append(payments, p)
				}
			}
		}
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"ticket":   t,
		"items":    items,
		"bills":    bills,
		"payments": payments,
	})
}

// handleOrderSummary returns aggregated order statistics.
// GET /api/v1/orders/summary
func (m *Module) handleOrderSummary(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}

	q := r.URL.Query()
	dateFrom := q.Get("date_from")
	dateTo := q.Get("date_to")

	// Default to today if not specified
	now := time.Now()
	from := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	to := from.Add(24*time.Hour - time.Nanosecond)

	if dateFrom != "" {
		if ts, err := time.Parse("2006-01-02", dateFrom); err == nil {
			from = ts
		}
	}
	if dateTo != "" {
		if ts, err := time.Parse("2006-01-02", dateTo); err == nil {
			to = ts.Add(24*time.Hour - time.Nanosecond)
		}
	}

	// Aggregate totals
	var totalOrders int
	var totalRevenue, averageOrder int64
	err := m.db.QueryRowContext(r.Context(), `
		SELECT COUNT(*), COALESCE(SUM(total), 0),
		       COALESCE(AVG(total)::BIGINT, 0)
		FROM tickets
		WHERE tenant_id = $1
		  AND is_deleted = FALSE
		  AND status NOT IN ('void', 'open')
		  AND created_at >= $2
		  AND created_at <= $3
	`, tenantID, from, to).Scan(&totalOrders, &totalRevenue, &averageOrder)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to aggregate orders")
		return
	}

	// Orders by type
	typeRows, err := m.db.QueryContext(r.Context(), `
		SELECT order_type, COUNT(*)
		FROM tickets
		WHERE tenant_id = $1
		  AND is_deleted = FALSE
		  AND status NOT IN ('void', 'open')
		  AND created_at >= $2 AND created_at <= $3
		GROUP BY order_type
	`, tenantID, from, to)
	ordersByType := map[string]int{}
	if err == nil {
		defer typeRows.Close()
		for typeRows.Next() {
			var ot string
			var cnt int
			if typeRows.Scan(&ot, &cnt) == nil {
				ordersByType[ot] = cnt
			}
		}
	}

	// Orders by status
	statusRows, err := m.db.QueryContext(r.Context(), `
		SELECT status, COUNT(*)
		FROM tickets
		WHERE tenant_id = $1
		  AND is_deleted = FALSE
		  AND created_at >= $2 AND created_at <= $3
		GROUP BY status
	`, tenantID, from, to)
	ordersByStatus := map[string]int{}
	if err == nil {
		defer statusRows.Close()
		for statusRows.Next() {
			var st string
			var cnt int
			if statusRows.Scan(&st, &cnt) == nil {
				ordersByStatus[st] = cnt
			}
		}
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"date_from":       from.Format("2006-01-02"),
		"date_to":         to.Format("2006-01-02"),
		"total_orders":    totalOrders,
		"total_revenue":   totalRevenue,
		"average_order":   averageOrder,
		"orders_by_type":  ordersByType,
		"orders_by_status": ordersByStatus,
	})
}

// handleCreateOrder creates a new ticket (order) from an external channel (online, kiosk API).
// POST /api/v1/orders
func (m *Module) handleCreateOrder(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}

	var req struct {
		OrderType    string  `json:"order_type"`
		Channel      string  `json:"channel"`
		TableID      *string `json:"table_id"`
		CustomerName *string `json:"customer_name"`
		GuestCount   int     `json:"guest_count"`
		Notes        *string `json:"notes"`
		DeviceID     string  `json:"device_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	if req.Channel == "" {
		req.Channel = "pos"
	}
	if req.OrderType == "" {
		req.OrderType = "dine_in"
	}
	if req.GuestCount == 0 {
		req.GuestCount = 1
	}
	if req.DeviceID == "" {
		req.DeviceID = middleware.GetDeviceID(r.Context())
	}

	// Get next order number for this tenant
	var nextOrderNum int
	err := m.db.QueryRowContext(r.Context(), `
		SELECT COALESCE(MAX(order_number), 0) + 1
		FROM tickets
		WHERE tenant_id = $1
	`, tenantID).Scan(&nextOrderNum)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to generate order number")
		return
	}

	var ticket Ticket
	err = m.db.QueryRowContext(r.Context(), `
		INSERT INTO tickets (
			tenant_id, order_number, order_type, table_id, customer_name,
			guest_count, status, channel, subtotal, tax_amount,
			discount_amount, total, notes, device_id
		) VALUES (
			$1, $2, $3, $4, $5,
			$6, 'open', $7, 0, 0,
			0, 0, $8, $9
		)
		RETURNING id, tenant_id, order_number, order_type, table_id, waiter_id,
		          customer_name, guest_count, status, channel,
		          subtotal, tax_amount, discount_amount, discount_type, discount_value,
		          total, notes, opened_at, closed_at, device_id, created_at, updated_at, is_deleted
	`, tenantID, nextOrderNum, req.OrderType, req.TableID, req.CustomerName,
		req.GuestCount, req.Channel, req.Notes, req.DeviceID,
	).Scan(
		&ticket.ID, &ticket.TenantID, &ticket.OrderNumber, &ticket.OrderType,
		&ticket.TableID, &ticket.WaiterID, &ticket.CustomerName, &ticket.GuestCount,
		&ticket.Status, &ticket.Channel, &ticket.Subtotal, &ticket.TaxAmount,
		&ticket.DiscountAmount, &ticket.DiscountType, &ticket.DiscountValue,
		&ticket.Total, &ticket.Notes, &ticket.OpenedAt, &ticket.ClosedAt,
		&ticket.DeviceID, &ticket.CreatedAt, &ticket.UpdatedAt, &ticket.IsDeleted,
	)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create order")
		return
	}

	response.Created(w, ticket)
}
