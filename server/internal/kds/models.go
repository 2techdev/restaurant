// Package kds implements the Kitchen Display System module.
// KDS devices connect via WebSocket (/ws/kds) and receive real-time
// ticket notifications.  REST endpoints allow marking items as done.
package kds

import "time"

// ---------------------------------------------------------------------------
// Domain models
// ---------------------------------------------------------------------------

// KDSTicket is the kitchen view of an open order.
type KDSTicket struct {
	ID          string     `json:"id"`
	OrderNumber int        `json:"order_number"`
	OrderType   string     `json:"order_type"`   // dine_in | takeaway | delivery
	TableNumber *int       `json:"table_number,omitempty"`
	Channel     string     `json:"channel"`      // pos | qr | web | kiosk
	Notes       string     `json:"notes,omitempty"`
	Status      string     `json:"status"`
	Items       []KDSItem  `json:"items"`
	OpenedAt    time.Time  `json:"opened_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// KDSItem is a single line in the kitchen ticket.
type KDSItem struct {
	ID          string `json:"id"`
	ProductName string `json:"product_name"`
	Quantity    int    `json:"quantity"`
	Notes       string `json:"notes,omitempty"`
	KDSStatus   string `json:"kds_status"` // pending | preparing | ready | served
	Course      int    `json:"course"`
}

// ---------------------------------------------------------------------------
// WebSocket notification types
// ---------------------------------------------------------------------------

// KDSNotification is the message sent to connected KDS devices.
type KDSNotification struct {
	Type     string     `json:"type"`               // new_ticket | status_update | ticket_closed
	TenantID string     `json:"tenant_id"`
	Ticket   *KDSTicket `json:"ticket,omitempty"`
	ItemID   string     `json:"item_id,omitempty"`
	Status   string     `json:"status,omitempty"`
}

// ---------------------------------------------------------------------------
// Request/response for REST endpoints
// ---------------------------------------------------------------------------

// UpdateItemStatusRequest is the PUT /api/v1/kds/items/{id}/status body.
type UpdateItemStatusRequest struct {
	Status string `json:"status"` // preparing | ready | served
}
