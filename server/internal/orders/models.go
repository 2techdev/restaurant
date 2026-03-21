package orders

import "time"

// Ticket represents a customer order (called "ticket" in restaurant POS).
type Ticket struct {
	ID             string     `json:"id"`
	TenantID       string     `json:"tenant_id"`
	OrderNumber    int        `json:"order_number"`
	OrderType      string     `json:"order_type"` // dine_in, takeaway, delivery, online
	TableID        *string    `json:"table_id,omitempty"`
	WaiterID       *string    `json:"waiter_id,omitempty"`
	CustomerName   *string    `json:"customer_name,omitempty"`
	GuestCount     int        `json:"guest_count"`
	Status         string     `json:"status"` // open, items_added, sent_to_kitchen, partially_served, fully_served, bill_requested, partially_paid, fully_paid, closed, void
	Channel        string     `json:"channel"` // pos, waiter, qr, kiosk, web
	Subtotal       int64      `json:"subtotal"`        // cents
	TaxAmount      int64      `json:"tax_amount"`      // cents
	DiscountAmount int64      `json:"discount_amount"` // cents
	DiscountType   *string    `json:"discount_type,omitempty"` // percent, fixed
	DiscountValue  *float64   `json:"discount_value,omitempty"`
	Total          int64      `json:"total"` // cents
	Notes          *string    `json:"notes,omitempty"`
	OpenedAt       time.Time  `json:"opened_at"`
	ClosedAt       *time.Time `json:"closed_at,omitempty"`
	DeviceID       string     `json:"device_id"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
	IsDeleted      bool       `json:"is_deleted"`
}

// OrderItem represents a line item within an order.
type OrderItem struct {
	ID             string     `json:"id"`
	TenantID       string     `json:"tenant_id"`
	TicketID       string     `json:"ticket_id"`
	ProductID      string     `json:"product_id"`
	ProductName    string     `json:"product_name"` // denormalized snapshot
	Quantity       float64    `json:"quantity"`
	UnitPrice      int64      `json:"unit_price"`      // cents
	Subtotal       int64      `json:"subtotal"`        // cents
	TaxAmount      int64      `json:"tax_amount"`      // cents
	DiscountAmount int64      `json:"discount_amount"` // cents
	Status         string     `json:"status"` // ordered, sent, preparing, ready, served, void
	SentToKitchen  bool       `json:"sent_to_kitchen"`
	Notes          *string    `json:"notes,omitempty"`
	Course         int        `json:"course"`
	Modifiers      []OrderItemModifier `json:"modifiers,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
	IsDeleted      bool       `json:"is_deleted"`
}

// OrderItemModifier represents a modifier applied to an order item.
type OrderItemModifier struct {
	ID           string    `json:"id"`
	OrderItemID  string    `json:"order_item_id"`
	ModifierID   string    `json:"modifier_id"`
	ModifierName string    `json:"modifier_name"` // denormalized
	PriceDelta   int64     `json:"price_delta"`   // cents
	CreatedAt    time.Time `json:"created_at"`
}

// Bill represents a bill generated from an order.
type Bill struct {
	ID             string    `json:"id"`
	TenantID       string    `json:"tenant_id"`
	TicketID       string    `json:"ticket_id"`
	BillNumber     int       `json:"bill_number"`
	Subtotal       int64     `json:"subtotal"`        // cents
	TaxAmount      int64     `json:"tax_amount"`      // cents
	DiscountAmount int64     `json:"discount_amount"` // cents
	Total          int64     `json:"total"`           // cents
	Status         string    `json:"status"` // open, partially_paid, fully_paid, void
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
	IsDeleted      bool      `json:"is_deleted"`
}

// Payment represents a payment made against a bill.
type Payment struct {
	ID             string    `json:"id"`
	TenantID       string    `json:"tenant_id"`
	BillID         string    `json:"bill_id"`
	TicketID       string    `json:"ticket_id"`
	PaymentMethod  string    `json:"payment_method"` // cash, credit_card, debit_card, other
	Amount         int64     `json:"amount"`          // cents
	TipAmount      int64     `json:"tip_amount"`      // cents
	TenderedAmount int64     `json:"tendered_amount"` // cents
	ChangeAmount   int64     `json:"change_amount"`   // cents
	Reference      *string   `json:"reference,omitempty"`
	ReceivedBy     string    `json:"received_by"` // user_id
	PaidAt         time.Time `json:"paid_at"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
	IsDeleted      bool      `json:"is_deleted"`
}
