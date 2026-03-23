package pos

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/gastrocore/server/internal/shared/response"
)

// Module provides the POS WebSocket hub and online-order management endpoints.
type Module struct {
	db  *sql.DB
	hub *Hub
}

// NewModule creates a new POS module. hub must already be running (go hub.Run()).
func NewModule(db *sql.DB, hub *Hub) *Module {
	return &Module{db: db, hub: hub}
}

// RegisterRoutes registers the POS WebSocket and REST routes.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// WebSocket endpoint for POS terminals.
	mux.HandleFunc("GET /ws/pos", m.hub.serveWS)

	// Online order accept / reject (staff-authenticated by middleware chain).
	mux.HandleFunc("PUT /api/v1/online/orders/{id}/accept", m.handleAcceptOrder)
	mux.HandleFunc("PUT /api/v1/online/orders/{id}/reject", m.handleRejectOrder)
}

// handleAcceptOrder marks an online order as accepted (sent to kitchen).
// PUT /api/v1/online/orders/{id}/accept
func (m *Module) handleAcceptOrder(w http.ResponseWriter, r *http.Request) {
	orderID := r.PathValue("id")
	if orderID == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_ID", "order id is required")
		return
	}

	result, err := m.db.ExecContext(r.Context(), `
		UPDATE tickets
		SET status = 'sent_to_kitchen', updated_at = NOW()
		WHERE id = $1 AND is_deleted = false
	`, orderID)
	if err != nil {
		slog.Error("pos: accept order", "error", err, "id", orderID)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Could not accept order")
		return
	}

	n, _ := result.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "ORDER_NOT_FOUND", "Order not found")
		return
	}

	m.broadcastStatusChange(r, orderID, "sent_to_kitchen")
	response.JSON(w, http.StatusOK, map[string]string{"status": "accepted"})
}

// handleRejectOrder marks an online order as cancelled with an optional reason.
// PUT /api/v1/online/orders/{id}/reject
func (m *Module) handleRejectOrder(w http.ResponseWriter, r *http.Request) {
	orderID := r.PathValue("id")
	if orderID == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_ID", "order id is required")
		return
	}

	var req struct {
		Reason string `json:"reason"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Reason == "" {
		req.Reason = "rejected by staff"
	}

	result, err := m.db.ExecContext(r.Context(), `
		UPDATE tickets
		SET status = 'cancelled', cancel_reason = $2, updated_at = NOW()
		WHERE id = $1 AND is_deleted = false
	`, orderID, req.Reason)
	if err != nil {
		slog.Error("pos: reject order", "error", err, "id", orderID)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Could not reject order")
		return
	}

	n, _ := result.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "ORDER_NOT_FOUND", "Order not found")
		return
	}

	m.broadcastStatusChange(r, orderID, "cancelled")
	response.JSON(w, http.StatusOK, map[string]string{"status": "rejected"})
}

// broadcastStatusChange fires a "order_status_update" WS notification to all
// POS terminals of the owning tenant.
func (m *Module) broadcastStatusChange(r *http.Request, orderID, status string) {
	var orderNumber int
	var tenantID string
	if err := m.db.QueryRowContext(r.Context(), `
		SELECT order_number, tenant_id FROM tickets WHERE id = $1
	`, orderID).Scan(&orderNumber, &tenantID); err != nil {
		slog.Warn("pos: could not fetch ticket for status broadcast", "id", orderID, "error", err)
		return
	}

	payload, _ := json.Marshal(POSOrderStatusPayload{
		OrderID:     orderID,
		OrderNumber: orderNumber,
		Status:      status,
	})
	m.hub.Notify(POSNotification{
		Type:     "order_status_update",
		TenantID: tenantID,
		Payload:  payload,
	})
}
