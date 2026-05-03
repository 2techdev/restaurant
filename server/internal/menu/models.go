package menu

import "time"

// Translations is a {locale -> string} map persisted as JSONB. Empty / null
// in the DB roundtrips to an empty map, never nil — handlers can iterate
// without nil checks. Wire format is the same JSON object PostgreSQL stores.
type Translations map[string]string

// Category represents a menu category (e.g., Drinks, Main Course).
type Category struct {
	ID               string       `json:"id"`
	TenantID         string       `json:"tenant_id"`
	Name             string       `json:"name"`
	NameTranslations Translations `json:"name_translations,omitempty"`
	DisplayOrder     int          `json:"display_order"`
	Color            *string      `json:"color,omitempty"`     // hex string e.g. "#FF5733"
	Icon             *string      `json:"icon,omitempty"`      // icon name or emoji
	ParentID         *string      `json:"parent_id,omitempty"` // self-reference for subcategories
	IsActive         bool         `json:"is_active"`
	CreatedAt        time.Time    `json:"created_at"`
	UpdatedAt        time.Time    `json:"updated_at"`
	IsDeleted        bool         `json:"is_deleted"`
}

// Product represents a menu item.
type Product struct {
	ID                      string       `json:"id"`
	TenantID                string       `json:"tenant_id"`
	CategoryID              string       `json:"category_id"`
	Name                    string       `json:"name"`
	NameTranslations        Translations `json:"name_translations,omitempty"`
	Description             *string      `json:"description,omitempty"`
	DescriptionTranslations Translations `json:"description_translations,omitempty"`
	Price                   int64        `json:"price"`      // cents: 1500 = CHF 15.00
	CostPrice               int64        `json:"cost_price"` // cents
	TaxGroup                string       `json:"tax_group"`
	ImagePath               *string      `json:"image_path,omitempty"`
	Barcode                 *string      `json:"barcode,omitempty"`
	IsActive                bool         `json:"is_active"`
	DisplayOrder            int          `json:"display_order"`
	PrepTimeMinutes         *int         `json:"prep_time_minutes,omitempty"`
	PrinterGroup            string       `json:"printer_group"`
	DefaultGang             *int         `json:"default_gang,omitempty"` // 1, 2, or 3; null = no default course hint
	CreatedAt               time.Time    `json:"created_at"`
	UpdatedAt               time.Time    `json:"updated_at"`
	IsDeleted               bool         `json:"is_deleted"`
}

// ModifierGroup represents a group of modifiers (e.g., "Size", "Toppings").
type ModifierGroup struct {
	ID            string     `json:"id"`
	TenantID      string     `json:"tenant_id"`
	Name          string     `json:"name"`
	SelectionType string     `json:"selection_type"` // single, multiple
	MinSelections int        `json:"min_selections"`
	MaxSelections int        `json:"max_selections"`
	IsRequired    bool       `json:"is_required"`
	DisplayOrder  int        `json:"display_order"`
	Modifiers     []Modifier `json:"modifiers,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
	IsDeleted     bool       `json:"is_deleted"`
}

// Modifier represents a single modifier option within a group.
type Modifier struct {
	ID           string    `json:"id"`
	TenantID     string    `json:"tenant_id"`
	GroupID      string    `json:"group_id"`
	Name         string    `json:"name"`
	PriceDelta   int64     `json:"price_delta"` // cents
	IsDefault    bool      `json:"is_default"`
	DisplayOrder int       `json:"display_order"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
	IsDeleted    bool      `json:"is_deleted"`
}

// ProductModifierGroup is the join table linking products to modifier groups.
type ProductModifierGroup struct {
	ID              string `json:"id"`
	ProductID       string `json:"product_id"`
	ModifierGroupID string `json:"modifier_group_id"`
	DisplayOrder    int    `json:"display_order"`
}
