package online

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

// validOrderStatuses is the set of recognised order status strings.
var validOrderStatuses = map[string]bool{
	"open": true, "items_added": true, "sent_to_kitchen": true,
	"preparing": true, "partially_served": true, "fully_served": true,
	"bill_requested": true, "partially_paid": true, "fully_paid": true,
	"closed": true, "void": true,
}

// handleGetMenu returns the public menu for online ordering.
// GET /api/v1/online/menu/{restaurantId}
// No authentication required.
func (m *Module) handleGetMenu(w http.ResponseWriter, r *http.Request) {
	restaurantID := r.PathValue("restaurantId")
	if restaurantID == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_RESTAURANT_ID", "restaurant_id is required")
		return
	}

	// Fetch restaurant / tenant info
	var rest MenuRestaurant
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, name, COALESCE(description,''), COALESCE(logo_url,''), COALESCE(cover_image_url,''), is_open
		FROM tenants
		WHERE id = $1 AND is_deleted = false
	`, restaurantID).Scan(
		&rest.ID, &rest.Name, &rest.Description,
		&rest.LogoURL, &rest.CoverImageURL, &rest.IsOpen,
	)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "RESTAURANT_NOT_FOUND", "Restaurant not found")
		return
	}
	if err != nil {
		slog.Error("online: fetch restaurant", "error", err)
		// Fallback: return stub so frontend can still render
		rest = MenuRestaurant{
			ID:                   restaurantID,
			Name:                 "Restaurant",
			IsOpen:               true,
			EstimatedWaitMinutes: 20,
		}
	}
	rest.EstimatedWaitMinutes = 20

	// Fetch categories
	catRows, err := m.db.QueryContext(r.Context(), `
		SELECT id, name, display_order, COALESCE(color,''), COALESCE(icon,'')
		FROM categories
		WHERE tenant_id = $1 AND is_active = true AND is_deleted = false
		ORDER BY display_order ASC
	`, restaurantID)
	categories := []MenuCategory{}
	if err == nil {
		defer catRows.Close()
		for catRows.Next() {
			var c MenuCategory
			if err := catRows.Scan(&c.ID, &c.Name, &c.DisplayOrder, &c.Color, &c.Icon); err == nil {
				categories = append(categories, c)
			}
		}
	}

	// Fetch products
	prodRows, err := m.db.QueryContext(r.Context(), `
		SELECT id, category_id, name, COALESCE(description,''), price,
		       tax_group, COALESCE(image_path,''), is_active, display_order,
		       prep_time_minutes
		FROM products
		WHERE tenant_id = $1 AND is_active = true AND is_deleted = false
		  AND COALESCE(stock_status,'in_stock') != 'delisted'
		ORDER BY display_order ASC
	`, restaurantID)
	products := []MenuProduct{}
	if err == nil {
		defer prodRows.Close()
		for prodRows.Next() {
			var p MenuProduct
			var prepTime sql.NullInt64
			if err := prodRows.Scan(
				&p.ID, &p.CategoryID, &p.Name, &p.Description, &p.Price,
				&p.TaxGroup, &p.ImageURL, &p.IsAvailable, &p.DisplayOrder,
				&prepTime,
			); err == nil {
				if prepTime.Valid {
					v := int(prepTime.Int64)
					p.PrepTimeMinutes = &v
				}
				p.ModifierGroups = m.fetchModifierGroups(r, p.ID)
				products = append(products, p)
			}
		}
	}

	menu := MenuResponse{
		Restaurant: rest,
		Categories: categories,
		Products:   products,
	}
	response.JSON(w, http.StatusOK, menu)
}

// fetchModifierGroups loads modifier groups for a product.
func (m *Module) fetchModifierGroups(r *http.Request, productID string) []MenuModifierGroup {
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT mg.id, mg.name, mg.selection_type, mg.min_selections,
		       mg.max_selections, mg.is_required, mg.display_order
		FROM modifier_groups mg
		JOIN product_modifier_groups pmg ON pmg.modifier_group_id = mg.id
		WHERE pmg.product_id = $1 AND mg.is_deleted = false
		ORDER BY pmg.display_order ASC, mg.display_order ASC
	`, productID)
	if err != nil {
		return nil
	}
	defer rows.Close()

	var groups []MenuModifierGroup
	for rows.Next() {
		var g MenuModifierGroup
		if err := rows.Scan(
			&g.ID, &g.Name, &g.SelectionType,
			&g.MinSelections, &g.MaxSelections,
			&g.IsRequired, &g.DisplayOrder,
		); err == nil {
			g.Modifiers = m.fetchModifiers(r, g.ID)
			groups = append(groups, g)
		}
	}
	return groups
}

// fetchModifiers loads modifiers for a group.
func (m *Module) fetchModifiers(r *http.Request, groupID string) []MenuModifier {
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, group_id, name, price_delta, is_default, display_order
		FROM modifiers
		WHERE group_id = $1 AND is_deleted = false
		ORDER BY display_order ASC
	`, groupID)
	if err != nil {
		return nil
	}
	defer rows.Close()

	var mods []MenuModifier
	for rows.Next() {
		var mod MenuModifier
		if err := rows.Scan(
			&mod.ID, &mod.GroupID, &mod.Name,
			&mod.PriceDelta, &mod.IsDefault, &mod.DisplayOrder,
		); err == nil {
			mods = append(mods, mod)
		}
	}
	return mods
}

// handlePlaceOrder creates a new order from the online ordering app.
// POST /api/v1/online/orders
// No authentication required.
func (m *Module) handlePlaceOrder(w http.ResponseWriter, r *http.Request) {
	var req PlaceOnlineOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	if req.RestaurantID == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_RESTAURANT_ID", "restaurant_id is required")
		return
	}
	if len(req.Items) == 0 {
		response.Error(w, http.StatusBadRequest, "NO_ITEMS", "Order must have at least one item")
		return
	}

	// Generate IDs
	orderID := uuid.New()
	now := time.Now().UTC()

	// Calculate totals (cents)
	var subtotal int64
	for _, item := range req.Items {
		lineTotal := item.UnitPrice * int64(item.Quantity)
		for _, mod := range item.Modifiers {
			lineTotal += mod.PriceDelta * int64(item.Quantity)
		}
		subtotal += lineTotal
	}

	// Determine VAT rate based on order type
	var vatRate float64
	if req.OrderType == "takeaway" {
		vatRate = 2.6
	} else {
		vatRate = 8.1
	}
	taxAmount := int64(float64(subtotal)*vatRate/100.0 + 0.5)

	// Get next order number (simple sequence from existing orders)
	var orderNumber int
	err := m.db.QueryRowContext(r.Context(), `
		SELECT COALESCE(MAX(order_number), 0) + 1
		FROM tickets
		WHERE tenant_id = $1
	`, req.RestaurantID).Scan(&orderNumber)
	if err != nil {
		orderNumber = 1
	}

	// Channel defaults
	channel := req.Channel
	if channel == "" {
		channel = "qr"
	}

	// Insert ticket
	_, err = m.db.ExecContext(r.Context(), `
		INSERT INTO tickets (
			id, tenant_id, order_number, order_type, table_id,
			customer_name, guest_count, status, channel,
			subtotal, tax_amount, discount_amount, total,
			notes, opened_at, device_id, created_at, updated_at, is_deleted
		) VALUES (
			$1, $2, $3, $4, $5,
			$6, 1, 'open', $7,
			$8, $9, 0, $10,
			$11, $12, 'online', $12, $12, false
		)
	`,
		orderID, req.RestaurantID, orderNumber, req.OrderType, req.TableNumber,
		nullString(req.CustomerName), channel,
		subtotal, taxAmount, subtotal+taxAmount,
		nullString(req.Notes), now,
	)
	if err != nil {
		slog.Error("online: insert ticket", "error", err)
		response.Error(w, http.StatusInternalServerError, "ORDER_FAILED", "Could not save order")
		return
	}

	// Insert order items
	for _, item := range req.Items {
		itemID := uuid.New()
		lineSubtotal := item.UnitPrice * int64(item.Quantity)

		_, err = m.db.ExecContext(r.Context(), `
			INSERT INTO order_items (
				id, tenant_id, ticket_id, product_id, product_name,
				quantity, unit_price, subtotal, tax_amount, discount_amount,
				status, sent_to_kitchen, notes, course, created_at, updated_at, is_deleted
			) VALUES (
				$1, $2, $3, $4, $5,
				$6, $7, $8, 0, 0,
				'ordered', false, $9, 1, $10, $10, false
			)
		`,
			itemID, req.RestaurantID, orderID, item.ProductID, item.ProductName,
			item.Quantity, item.UnitPrice, lineSubtotal,
			nullString(item.Notes), now,
		)
		if err != nil {
			slog.Error("online: insert order item", "error", err, "product_id", item.ProductID)
		}

		// Insert modifiers
		for _, mod := range item.Modifiers {
			modID := uuid.New()
			_, _ = m.db.ExecContext(r.Context(), `
				INSERT INTO order_item_modifiers (
					id, order_item_id, modifier_id, modifier_name, price_delta, created_at
				) VALUES ($1, $2, $3, $4, $5, $6)
			`, modID, itemID, mod.ModifierID, mod.ModifierName, mod.PriceDelta, now)
		}
	}

	slog.Info("online: order placed",
		"order_id", orderID,
		"order_number", orderNumber,
		"restaurant_id", req.RestaurantID,
		"items", len(req.Items),
	)

	// Notify KDS about the new ticket (if hub is wired).
	if m.kdsNotify != nil {
		m.kdsNotify.NotifyNewOrder(req.RestaurantID, orderID, orderNumber)
	}

	resp := PlaceOnlineOrderResponse{
		ID:                   orderID,
		OrderNumber:          orderNumber,
		Status:               "received",
		EstimatedWaitMinutes: 20,
		CreatedAt:            now,
	}
	response.Created(w, resp)
}

// handleGetOrderStatus returns the current status of an online order.
// GET /api/v1/online/orders/{orderId}/status
// No authentication required.
func (m *Module) handleGetOrderStatus(w http.ResponseWriter, r *http.Request) {
	orderID := r.PathValue("orderId")
	if orderID == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_ORDER_ID", "order_id is required")
		return
	}

	var status OrderStatusResponse
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, order_number, status
		FROM tickets
		WHERE id = $1 AND is_deleted = false
	`, orderID).Scan(&status.OrderID, &status.OrderNumber, &status.Status)

	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "ORDER_NOT_FOUND", "Order not found")
		return
	}
	if err != nil {
		slog.Error("online: fetch order status", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Could not fetch order status")
		return
	}

	status.EstimatedWaitMinutes = estimatedWaitForStatus(status.Status)
	response.JSON(w, http.StatusOK, status)
}

// estimatedWaitForStatus returns an approximate wait time in minutes based on order status.
func estimatedWaitForStatus(status string) int {
	switch status {
	case "open", "items_added":
		return 20
	case "sent_to_kitchen", "preparing":
		return 12
	case "partially_served":
		return 5
	case "fully_served", "closed", "fully_paid":
		return 0
	default:
		return 20
	}
}

// handleUpdateOrderStatus updates the status of an online order.
// PUT /api/v1/online/orders/{orderId}/status
func (m *Module) handleUpdateOrderStatus(w http.ResponseWriter, r *http.Request) {
	orderID := r.PathValue("orderId")
	if orderID == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_ORDER_ID", "order_id is required")
		return
	}

	var req struct {
		Status string `json:"status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Status == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "valid status is required")
		return
	}
	if !validOrderStatuses[req.Status] {
		response.Error(w, http.StatusBadRequest, "INVALID_STATUS", "unknown order status")
		return
	}

	_, err := m.db.ExecContext(r.Context(),
		`UPDATE tickets SET status = $1, updated_at = $2 WHERE id = $3`,
		req.Status, time.Now().UTC(), orderID,
	)
	if err != nil {
		slog.Error("handleUpdateOrderStatus: db error", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "failed to update status")
		return
	}

	if m.wsHub != nil {
		m.wsHub.Broadcast(OnlineWSMessage{
			Type:    "order_status_changed",
			OrderID: orderID,
			Data:    map[string]string{"status": req.Status},
		})
	}
	response.JSON(w, http.StatusOK, map[string]string{"status": req.Status})
}

// nullString returns a *string (nil for empty strings).
func nullString(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}

