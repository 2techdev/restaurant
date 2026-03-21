package kds

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// handleListTickets returns open kitchen tickets for the tenant.
// GET /api/v1/kds/tickets?status=pending,preparing
func (m *Module) handleListTickets(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	// Return tickets with at least one non-served/non-ready item.
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT t.id, t.order_number, t.order_type,
		       t.table_id, t.channel, COALESCE(t.notes,''), t.status,
		       t.opened_at, t.updated_at
		FROM tickets t
		WHERE t.tenant_id = $1
		  AND t.is_deleted = false
		  AND t.status NOT IN ('closed','fully_paid','voided')
		  AND EXISTS (
		        SELECT 1 FROM order_items oi
		        WHERE oi.ticket_id = t.id
		          AND oi.is_deleted = false
		          AND oi.kds_status IN ('pending','preparing')
		      )
		ORDER BY t.opened_at ASC
		LIMIT 50
	`, tenantID)
	if err != nil {
		slog.Error("kds: list tickets", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch tickets")
		return
	}
	defer rows.Close()

	tickets := []KDSTicket{}
	for rows.Next() {
		var tkt KDSTicket
		var tableID sql.NullInt64
		if err := rows.Scan(
			&tkt.ID, &tkt.OrderNumber, &tkt.OrderType,
			&tableID, &tkt.Channel, &tkt.Notes, &tkt.Status,
			&tkt.OpenedAt, &tkt.UpdatedAt,
		); err != nil {
			continue
		}
		if tableID.Valid {
			n := int(tableID.Int64)
			tkt.TableNumber = &n
		}
		tkt.Items = m.fetchKDSItems(r, tkt.ID)
		tickets = append(tickets, tkt)
	}

	response.JSON(w, http.StatusOK, tickets)
}

// fetchKDSItems loads non-served order items for a ticket.
func (m *Module) fetchKDSItems(r *http.Request, ticketID string) []KDSItem {
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, product_name, quantity,
		       COALESCE(notes,''), kds_status, course
		FROM order_items
		WHERE ticket_id = $1
		  AND is_deleted = false
		  AND kds_status NOT IN ('served')
		ORDER BY course ASC, created_at ASC
	`, ticketID)
	if err != nil {
		return nil
	}
	defer rows.Close()

	var items []KDSItem
	for rows.Next() {
		var item KDSItem
		if err := rows.Scan(
			&item.ID, &item.ProductName, &item.Quantity,
			&item.Notes, &item.KDSStatus, &item.Course,
		); err == nil {
			items = append(items, item)
		}
	}
	return items
}

// handleUpdateItemStatus updates the kds_status of an order item.
// PUT /api/v1/kds/items/{id}/status
func (m *Module) handleUpdateItemStatus(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	itemID := r.PathValue("id")
	if itemID == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_ID", "item id is required")
		return
	}

	var req UpdateItemStatusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	validStatuses := map[string]bool{"preparing": true, "ready": true, "served": true}
	if !validStatuses[req.Status] {
		response.Error(w, http.StatusBadRequest, "INVALID_STATUS", "status must be preparing, ready, or served")
		return
	}

	res, err := m.db.ExecContext(r.Context(), `
		UPDATE order_items
		SET kds_status = $1, updated_at = NOW()
		WHERE id = $2 AND tenant_id = $3 AND is_deleted = false
	`, req.Status, itemID, tenantID)
	if err != nil {
		slog.Error("kds: update item status", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update item")
		return
	}

	n, _ := res.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Item not found")
		return
	}

	// Notify connected KDS devices about the status change.
	m.hub.Notify(KDSNotification{
		Type:     "status_update",
		TenantID: tenantID,
		ItemID:   itemID,
		Status:   req.Status,
	})

	response.JSON(w, http.StatusOK, map[string]string{
		"item_id": itemID,
		"status":  req.Status,
	})
}

// handleUpdateTicketStatus marks a full ticket as ready or done.
// PUT /api/v1/kds/tickets/{id}/status
func (m *Module) handleUpdateTicketStatus(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	ticketID := r.PathValue("id")
	if ticketID == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_ID", "ticket id is required")
		return
	}

	var req struct {
		Status string `json:"status"` // preparing | fully_served
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	// Update all pending items to the same status.
	if _, err := m.db.ExecContext(r.Context(), `
		UPDATE order_items
		SET kds_status = $1, updated_at = NOW()
		WHERE ticket_id = $2 AND tenant_id = $3 AND is_deleted = false
		  AND kds_status NOT IN ('served')
	`, req.Status, ticketID, tenantID); err != nil {
		slog.Error("kds: bulk update items", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update ticket")
		return
	}

	response.JSON(w, http.StatusOK, map[string]string{
		"ticket_id": ticketID,
		"status":    req.Status,
	})
}
