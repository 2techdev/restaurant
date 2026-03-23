package pos

import (
	"encoding/json"
	"time"
)

// POSNotification is the WebSocket message pushed to POS terminals.
type POSNotification struct {
	Type     string          `json:"type"`      // "new_order" | "order_status_update"
	TenantID string          `json:"tenant_id"`
	Payload  json.RawMessage `json:"payload"`
}

// POSOrderPayload is the full order payload for a new online order pushed to POS.
type POSOrderPayload struct {
	ID                   string         `json:"id"`
	OrderNumber          int            `json:"order_number"`
	OrderType            string         `json:"order_type"`            // dine_in | takeaway | delivery
	Channel              string         `json:"channel"`               // qr | web | kiosk
	CustomerName         string         `json:"customer_name,omitempty"`
	TableNumber          *int           `json:"table_number,omitempty"`
	Notes                string         `json:"notes,omitempty"`
	Subtotal             int64          `json:"subtotal"`              // cents
	TaxAmount            int64          `json:"tax_amount"`            // cents
	Total                int64          `json:"total"`                 // cents
	Items                []POSOrderItem `json:"items"`
	Status               string         `json:"status"`
	EstimatedWaitMinutes int            `json:"estimated_wait_minutes"`
	CreatedAt            time.Time      `json:"created_at"`
}

// POSOrderItem is a line item in the POS order payload.
type POSOrderItem struct {
	ID          string             `json:"id"`
	ProductID   string             `json:"product_id"`
	ProductName string             `json:"product_name"`
	Quantity    int                `json:"quantity"`
	UnitPrice   int64              `json:"unit_price"` // cents
	Subtotal    int64              `json:"subtotal"`   // cents
	Notes       string             `json:"notes,omitempty"`
	Modifiers   []POSOrderModifier `json:"modifiers,omitempty"`
}

// POSOrderModifier is a modifier applied to a line item in the POS order payload.
type POSOrderModifier struct {
	ModifierID   string `json:"modifier_id"`
	ModifierName string `json:"modifier_name"`
	PriceDelta   int64  `json:"price_delta"` // cents
}

// POSOrderStatusPayload is sent when an order status changes (accept / reject).
type POSOrderStatusPayload struct {
	OrderID     string `json:"order_id"`
	OrderNumber int    `json:"order_number"`
	Status      string `json:"status"`
}
