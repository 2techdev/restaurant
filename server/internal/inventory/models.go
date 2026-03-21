package inventory

import "time"

// InventoryItem represents a stockable ingredient or product unit.
type InventoryItem struct {
	ID          string    `json:"id"`
	TenantID    string    `json:"tenant_id"`
	Name        string    `json:"name"`
	SKU         *string   `json:"sku,omitempty"`
	Unit        string    `json:"unit"`          // unit, kg, litre, portion …
	CurrentQty  float64   `json:"current_qty"`   // current stock level
	MinQty      float64   `json:"min_qty"`       // low-stock alert threshold
	MaxQty      *float64  `json:"max_qty,omitempty"`
	CostPerUnit *int64    `json:"cost_per_unit,omitempty"` // cents
	Supplier    *string   `json:"supplier,omitempty"`
	Notes       *string   `json:"notes,omitempty"`
	IsActive    bool      `json:"is_active"`
	IsLow       bool      `json:"is_low"` // computed: current_qty <= min_qty
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// StockMovement is a single ledger entry for a quantity change.
// movement_type: stock_in | stock_out | waste | restock | adjustment
type StockMovement struct {
	ID           string    `json:"id"`
	TenantID     string    `json:"tenant_id"`
	ItemID       string    `json:"item_id"`
	ItemName     string    `json:"item_name,omitempty"` // joined for convenience
	MovementType string    `json:"movement_type"`
	Qty          float64   `json:"qty"`
	QtyBefore    float64   `json:"qty_before"`
	QtyAfter     float64   `json:"qty_after"`
	Reference    *string   `json:"reference,omitempty"`
	Notes        *string   `json:"notes,omitempty"`
	PerformedBy  *string   `json:"performed_by,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}

// isDeduction returns true for movement types that subtract from stock.
func isDeduction(movementType string) bool {
	switch movementType {
	case "stock_out", "waste":
		return true
	default:
		return false
	}
}
