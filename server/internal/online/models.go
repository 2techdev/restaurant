package online

import "time"

// ---------------------------------------------------------------------------
// Payment models
// ---------------------------------------------------------------------------

// CreateCheckoutRequest is the POST body for POST /api/v1/online/payment/checkout.
type CreateCheckoutRequest struct {
	OrderID      string `json:"order_id"`
	RestaurantID string `json:"restaurant_id"`
	AmountCents  int64  `json:"amount_cents"` // e.g. 2350 for CHF 23.50
	Currency     string `json:"currency"`     // "chf" (default) or "eur"
	Description  string `json:"description,omitempty"`
}

// CreateCheckoutResponse is returned after creating a Stripe Checkout Session.
type CreateCheckoutResponse struct {
	CheckoutURL string `json:"checkout_url"` // Redirect the customer here
	SessionID   string `json:"session_id"`
	OrderID     string `json:"order_id"`
}

// ---------------------------------------------------------------------------
// Menu response models (public, no auth)
// ---------------------------------------------------------------------------

// MenuRestaurant is the public restaurant info sent to online ordering.
type MenuRestaurant struct {
	ID                    string `json:"id"`
	Name                  string `json:"name"`
	Description           string `json:"description,omitempty"`
	LogoURL               string `json:"logo_url,omitempty"`
	CoverImageURL         string `json:"cover_image_url,omitempty"`
	IsOpen                bool   `json:"is_open"`
	ClosedMessage         string `json:"closed_message,omitempty"`
	EstimatedWaitMinutes  int    `json:"estimated_wait_minutes"`
}

// MenuCategory is a public menu category.
type MenuCategory struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	DisplayOrder int    `json:"display_order"`
	Color        string `json:"color,omitempty"`
	Icon         string `json:"icon,omitempty"`
}

// MenuModifier is a single modifier option.
type MenuModifier struct {
	ID           string `json:"id"`
	GroupID      string `json:"group_id"`
	Name         string `json:"name"`
	PriceDelta   int64  `json:"price_delta"` // cents
	IsDefault    bool   `json:"is_default"`
	DisplayOrder int    `json:"display_order"`
}

// MenuModifierGroup is a group of modifier options.
type MenuModifierGroup struct {
	ID            string         `json:"id"`
	Name          string         `json:"name"`
	SelectionType string         `json:"selection_type"` // single | multiple
	MinSelections int            `json:"min_selections"`
	MaxSelections int            `json:"max_selections"`
	IsRequired    bool           `json:"is_required"`
	DisplayOrder  int            `json:"display_order"`
	Modifiers     []MenuModifier `json:"modifiers"`
}

// MenuProduct is a public product with its modifier groups.
type MenuProduct struct {
	ID              string              `json:"id"`
	CategoryID      string              `json:"category_id"`
	Name            string              `json:"name"`
	Description     string              `json:"description,omitempty"`
	Price           int64               `json:"price"`       // cents
	TaxGroup        string              `json:"tax_group"`
	ImageURL        string              `json:"image_url,omitempty"`
	IsAvailable     bool                `json:"is_available"`
	DisplayOrder    int                 `json:"display_order"`
	PrepTimeMinutes *int                `json:"prep_time_minutes,omitempty"`
	ModifierGroups  []MenuModifierGroup `json:"modifier_groups"`
}

// MenuResponse is the full public menu payload.
type MenuResponse struct {
	Restaurant MenuRestaurant `json:"restaurant"`
	Categories []MenuCategory `json:"categories"`
	Products   []MenuProduct  `json:"products"`
}

// ---------------------------------------------------------------------------
// Order submission models
// ---------------------------------------------------------------------------

// OnlineOrderModifier is a modifier applied to an order item.
type OnlineOrderModifier struct {
	ModifierID   string `json:"modifier_id"`
	ModifierName string `json:"modifier_name"`
	PriceDelta   int64  `json:"price_delta"` // cents
}

// OnlineOrderItem is a line item in the online order request.
type OnlineOrderItem struct {
	ProductID   string                `json:"product_id"`
	ProductName string                `json:"product_name"`
	Quantity    int                   `json:"quantity"`
	UnitPrice   int64                 `json:"unit_price"`  // cents
	Notes       string                `json:"notes,omitempty"`
	Modifiers   []OnlineOrderModifier `json:"modifiers,omitempty"`
}

// PlaceOnlineOrderRequest is the POST body for /api/v1/online/orders.
type PlaceOnlineOrderRequest struct {
	RestaurantID string            `json:"restaurant_id"`
	OrderType    string            `json:"order_type"`   // dine_in | takeaway
	TableNumber  *int              `json:"table_number,omitempty"`
	CustomerName string            `json:"customer_name,omitempty"`
	Notes        string            `json:"notes,omitempty"`
	Channel      string            `json:"channel"`      // qr | web | kiosk
	Items        []OnlineOrderItem `json:"items"`
}

// PlaceOnlineOrderResponse is returned after a successful order.
type PlaceOnlineOrderResponse struct {
	ID                   string    `json:"id"`
	OrderNumber          int       `json:"order_number"`
	Status               string    `json:"status"`
	EstimatedWaitMinutes int       `json:"estimated_wait_minutes"`
	CreatedAt            time.Time `json:"created_at"`
}

// ---------------------------------------------------------------------------
// Order status
// ---------------------------------------------------------------------------

// OrderStatusResponse is returned by GET /api/v1/online/orders/{id}/status.
type OrderStatusResponse struct {
	OrderID              string `json:"order_id"`
	OrderNumber          int    `json:"order_number"`
	Status               string `json:"status"`
	EstimatedWaitMinutes int    `json:"estimated_wait_minutes"`
}

// OnlineWSMessage is broadcast over the WebSocket hub to connected clients.
type OnlineWSMessage struct {
	Type         string `json:"type"`          // e.g. "new_order", "order_status_changed"
	RestaurantID string `json:"restaurant_id"` // routes to correct subscribers
	OrderID      string `json:"order_id,omitempty"`
	Data         any    `json:"data,omitempty"`
}
