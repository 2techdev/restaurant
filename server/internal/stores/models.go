package stores

import "time"

// Organization represents a company or franchise owner at the top of the hierarchy.
// For a single restaurant: 1 org, 1 brand, 1 store.
// For a chain: 1 org, 1+ brands, many stores.
type Organization struct {
	ID          string     `json:"id"`
	Name        string     `json:"name"`
	LegalName   string     `json:"legal_name"`
	TaxID       string     `json:"tax_id"`        // UID/VAT number
	Country     string     `json:"country"`        // CH, DE, AT
	Address     string     `json:"address"`
	Phone       string     `json:"phone"`
	Email       string     `json:"email"`
	Logo        string     `json:"logo,omitempty"`
	Plan        string     `json:"plan"`   // starter, professional, enterprise
	Status      string     `json:"status"` // active, suspended, trial
	TrialEndsAt *time.Time `json:"trial_ends_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// Brand groups stores under a common identity within an organization.
type Brand struct {
	ID             string    `json:"id"`
	OrganizationID string    `json:"organization_id"`
	Name           string    `json:"name"`
	Logo           string    `json:"logo,omitempty"`
	Description    string    `json:"description,omitempty"`
	Status         string    `json:"status"` // active, inactive
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// Store represents a physical restaurant branch.
type Store struct {
	ID             string     `json:"id"`
	BrandID        string     `json:"brand_id"`
	OrganizationID string     `json:"organization_id"`
	StoreCode      string     `json:"store_code"` // CH00000060
	Name           string     `json:"name"`
	LegalName      string     `json:"legal_name"`
	Country        string     `json:"country"`
	Address        string     `json:"address"`
	City           string     `json:"city"`
	PostalCode     string     `json:"postal_code"`
	Phone          string     `json:"phone"`
	Email          string     `json:"email"`
	Timezone       string     `json:"timezone"` // Europe/Zurich
	Currency       string     `json:"currency"`  // CHF, EUR
	TaxRate        float64    `json:"tax_rate"`
	ProductCount   int        `json:"product_count"`
	TableCount     int        `json:"table_count"`
	DeviceCount    int        `json:"device_count"`
	ManagerName    string     `json:"manager_name"`
	Status         string     `json:"status"` // active, inactive, suspended
	ExpiresAt      *time.Time `json:"expires_at,omitempty"`
	BusinessHours  string     `json:"business_hours,omitempty"` // JSON string
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
}

// AdminUser represents a web dashboard user with organization-level access.
type AdminUser struct {
	ID             string     `json:"id"`
	OrganizationID string     `json:"organization_id"`
	Email          string     `json:"email"`
	Name           string     `json:"name"`
	Role           string     `json:"role"` // super_admin, org_admin, store_manager, viewer
	StoreIDs       []string   `json:"store_ids,omitempty"`
	Status         string     `json:"status"`
	LastLoginAt    *time.Time `json:"last_login_at,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
}

// Employee represents POS staff within a specific store (separate from admin users).
type Employee struct {
	ID             string    `json:"id"`
	StoreID        string    `json:"store_id"`
	OrganizationID string    `json:"organization_id"`
	Name           string    `json:"name"`
	PIN            string    `json:"pin,omitempty"` // hashed, never returned in API responses
	Role           string    `json:"role"`          // admin, manager, waiter, cashier, kitchen
	IsActive       bool      `json:"is_active"`
	Phone          string    `json:"phone,omitempty"`
	Email          string    `json:"email,omitempty"`
	Avatar         string    `json:"avatar,omitempty"`
	Permissions    string    `json:"permissions,omitempty"` // JSON string
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// --- Response types for dashboard and stats ---

// DashboardResponse contains aggregated metrics for the admin dashboard.
type DashboardResponse struct {
	Sales               int64                 `json:"sales"`
	NetSales            int64                 `json:"net_sales"`
	Orders              int                   `json:"orders"`
	SalesVsYesterday    int                   `json:"sales_vs_yesterday"`
	NetSalesVsYesterday int                   `json:"net_sales_vs_yesterday"`
	OrdersVsYesterday   int                   `json:"orders_vs_yesterday"`
	SalesBreakdown      SalesBreakdown        `json:"sales_breakdown"`
	SalesByPayment      []PaymentMethodSales  `json:"sales_by_payment_method"`
	SalesByOrderType    []OrderTypeSales      `json:"sales_by_order_type"`
	HourlySales         []int64               `json:"hourly_sales"`
}

// SalesBreakdown contains the components of total sales.
type SalesBreakdown struct {
	DiscountAmount int64 `json:"discount_amount"`
	Tax            int64 `json:"tax"`
	TotalSales     int64 `json:"total_sales"`
}

// PaymentMethodSales shows revenue per payment method.
type PaymentMethodSales struct {
	Method     string `json:"method"`
	Amount     int64  `json:"amount"`
	Percentage int    `json:"percentage"`
}

// OrderTypeSales shows revenue per order type.
type OrderTypeSales struct {
	Type       string `json:"type"`
	Amount     int64  `json:"amount"`
	Percentage int    `json:"percentage"`
}

// StoreStats holds aggregated statistics for a single store.
type StoreStats struct {
	StoreID       string `json:"store_id"`
	StoreName     string `json:"store_name"`
	TodaySales    int64  `json:"today_sales"`
	TodayOrders   int    `json:"today_orders"`
	WeekSales     int64  `json:"week_sales"`
	WeekOrders    int    `json:"week_orders"`
	MonthSales    int64  `json:"month_sales"`
	MonthOrders   int    `json:"month_orders"`
	ActiveDevices int    `json:"active_devices"`
	ActiveStaff   int    `json:"active_staff"`
}
