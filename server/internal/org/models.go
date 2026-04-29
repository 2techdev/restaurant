package org

import (
	"encoding/json"
	"time"
)

// Role constants — HQ chain restaurant roles. Stored on `users.org_role`.
const (
	RoleHQAdmin            = "HQ_ADMIN"
	RoleHQManager          = "HQ_MANAGER"
	RoleRestaurantManager  = "RESTAURANT_MANAGER"
	RoleRestaurantStaff    = "RESTAURANT_STAFF"
	RolePOSOperator        = "POS_OPERATOR"
)

// LockType values for menu_policies.lock_type.
const (
	LockTypeFullyLocked = "FULLY_LOCKED"
	LockTypePriceLocked = "PRICE_LOCKED"
	LockTypeFlexible    = "FLEXIBLE"
)

// ValidLockTypes is the canonical set used for input validation.
var ValidLockTypes = map[string]bool{
	LockTypeFullyLocked: true,
	LockTypePriceLocked: true,
	LockTypeFlexible:    true,
}

// Organization mirrors the organizations table at HQ-API level.
type Organization struct {
	ID           string          `json:"id"`
	Name         string          `json:"name"`
	OwnerUserID  *string         `json:"owner_user_id,omitempty"`
	Settings     json.RawMessage `json:"settings_json,omitempty"`
	CreatedAt    time.Time       `json:"created_at"`
	UpdatedAt    time.Time       `json:"updated_at"`
}

// Membership represents one tenant attached to an organization.
type Membership struct {
	OrganizationID string    `json:"organization_id"`
	TenantID       string    `json:"tenant_id"`
	JoinedAt       time.Time `json:"joined_at"`
	IsMaster       bool      `json:"is_master"`
}

// MemberRestaurant is the listing shape returned by GET /restaurants.
type MemberRestaurant struct {
	TenantID       string     `json:"tenant_id"`
	Name           string     `json:"name"`
	IsMaster       bool       `json:"is_master"`
	JoinedAt       time.Time  `json:"joined_at"`
	LastActivityAt *time.Time `json:"last_activity_at,omitempty"`
	TodayRevenue   int64      `json:"today_revenue"` // cents
}

// MenuPolicy mirrors the menu_policies table.
type MenuPolicy struct {
	ID                  string    `json:"id"`
	OrganizationID      string    `json:"organization_id"`
	ProductID           string    `json:"product_id"`
	LockType            string    `json:"lock_type"`
	AllowLocalAdditions bool      `json:"allow_local_additions"`
	AllowLocalDisable   bool      `json:"allow_local_disable"`
	CreatedAt           time.Time `json:"created_at"`
	UpdatedAt           time.Time `json:"updated_at"`
}

// MasterMenu represents the published-pointer row for an org.
type MasterMenu struct {
	OrganizationID string    `json:"organization_id"`
	CurrentVersion int       `json:"current_version"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// MasterMenuVersion is one immutable HQ snapshot.
type MasterMenuVersion struct {
	ID             string          `json:"id"`
	OrganizationID string          `json:"organization_id"`
	Version        int             `json:"version"`
	Snapshot       json.RawMessage `json:"snapshot"`
	PublishedAt    time.Time       `json:"published_at"`
	PublishedBy    *string         `json:"published_by,omitempty"`
}

// MenuSnapshot is the canonical, JSON-serializable shape of a published menu.
//
// HQ snapshots include OrganizationID + Version. Restaurant (per-tenant)
// snapshots inherit those fields when source = "master".
type MenuSnapshot struct {
	OrganizationID string                  `json:"organization_id,omitempty"`
	Version        int                     `json:"version"`
	Source         string                  `json:"source"` // "local" | "master"
	MasterVersion  *int                    `json:"master_version,omitempty"`
	Categories     []SnapshotCategory      `json:"categories"`
	Products       []SnapshotProduct       `json:"products"`
	ModifierGroups []SnapshotModifierGroup `json:"modifier_groups"`
	GeneratedAt    time.Time               `json:"generated_at"`
}

type SnapshotCategory struct {
	ID           string  `json:"id"`
	Name         string  `json:"name"`
	DisplayOrder int     `json:"display_order"`
	Color        *string `json:"color,omitempty"`
	Icon         *string `json:"icon,omitempty"`
	ParentID     *string `json:"parent_id,omitempty"`
	IsActive     bool    `json:"is_active"`
}

type SnapshotProduct struct {
	ID              string  `json:"id"`
	CategoryID      string  `json:"category_id"`
	Name            string  `json:"name"`
	Description     *string `json:"description,omitempty"`
	Price           int64   `json:"price"`
	CostPrice       int64   `json:"cost_price"`
	TaxGroup        string  `json:"tax_group"`
	ImagePath       *string `json:"image_path,omitempty"`
	Barcode         *string `json:"barcode,omitempty"`
	IsActive        bool    `json:"is_active"`
	DisplayOrder    int     `json:"display_order"`
	PrepTimeMinutes *int    `json:"prep_time_minutes,omitempty"`
	PrinterGroup    string  `json:"printer_group"`
	DefaultGang     *int    `json:"default_gang,omitempty"`

	// Inheritance / lock fields (only set when source="master" or merged).
	LockType  string `json:"lock_type,omitempty"`  // FULLY_LOCKED / PRICE_LOCKED / FLEXIBLE
	IsMaster  bool   `json:"is_master,omitempty"`  // true if originated from HQ
	LocalOnly bool   `json:"local_only,omitempty"` // true if added by the restaurant
}

type SnapshotModifier struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	PriceDelta   int64  `json:"price_delta"`
	IsDefault    bool   `json:"is_default"`
	DisplayOrder int    `json:"display_order"`
}

type SnapshotModifierGroup struct {
	ID            string             `json:"id"`
	Name          string             `json:"name"`
	SelectionType string             `json:"selection_type"`
	MinSelections int                `json:"min_selections"`
	MaxSelections int                `json:"max_selections"`
	IsRequired    bool               `json:"is_required"`
	DisplayOrder  int                `json:"display_order"`
	Modifiers     []SnapshotModifier `json:"modifiers"`
}

// AggregateReport is the cross-restaurant rollup.
type AggregateReport struct {
	OrganizationID string         `json:"organization_id"`
	From           time.Time      `json:"from"`
	To             time.Time      `json:"to"`
	TotalRevenue   int64          `json:"total_revenue"`
	OrderCount     int64          `json:"order_count"`
	AvgTicket      int64          `json:"avg_ticket"`
	RestaurantCnt  int            `json:"restaurant_count"`
	TopProducts    []TopProduct   `json:"top_products"`
	Comparison     []RestaurantKV `json:"comparison"`
}

type TopProduct struct {
	ProductID   string  `json:"product_id"`
	ProductName string  `json:"product_name"`
	Quantity    float64 `json:"quantity"`
	Revenue     int64   `json:"revenue"`
}

type RestaurantKV struct {
	TenantID string `json:"tenant_id"`
	Name     string `json:"name"`
	Value    int64  `json:"value"` // revenue
}

// ByRestaurantReport — per-tenant breakdown.
type ByRestaurantReport struct {
	OrganizationID string                 `json:"organization_id"`
	From           time.Time              `json:"from"`
	To             time.Time              `json:"to"`
	Restaurants    []ByRestaurantRow      `json:"restaurants"`
}

type ByRestaurantRow struct {
	TenantID    string      `json:"tenant_id"`
	Name        string      `json:"name"`
	Revenue     int64       `json:"revenue"`
	OrderCount  int64       `json:"order_count"`
	AvgTicket   int64       `json:"avg_ticket"`
	TopProduct  *TopProduct `json:"top_product,omitempty"`
}
