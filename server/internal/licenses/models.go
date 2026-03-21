package licenses

import "time"

// License represents a license key and its metadata.
type License struct {
	ID          string     `json:"id"`
	LicenseKey  string     `json:"license_key"`
	Plan        string     `json:"plan"` // starter, professional, enterprise
	MaxDevices  int        `json:"max_devices"`
	IsActive    bool       `json:"is_active"`
	IssuedAt    time.Time  `json:"issued_at"`
	ExpiresAt   *time.Time `json:"expires_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// Subscription links a license to a tenant.
type Subscription struct {
	ID          string     `json:"id"`
	TenantID    string     `json:"tenant_id"`
	LicenseID   string     `json:"license_id"`
	Plan        string     `json:"plan"`
	Status      string     `json:"status"` // active, trial, expired, cancelled
	StartDate   time.Time  `json:"start_date"`
	EndDate     *time.Time `json:"end_date,omitempty"`
	TrialEndsAt *time.Time `json:"trial_ends_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// FeatureFlags determines which features are available for a subscription plan.
type FeatureFlags struct {
	MaxDevices        int  `json:"max_devices"`
	MaxUsers          int  `json:"max_users"`
	CloudSync         bool `json:"cloud_sync"`
	CloudReports      bool `json:"cloud_reports"`
	MultiFloor        bool `json:"multi_floor"`
	KitchenDisplay    bool `json:"kitchen_display"`
	CustomerDisplay   bool `json:"customer_display"`
	ERPNextBridge     bool `json:"erpnext_bridge"`
	FiscalIntegration bool `json:"fiscal_integration"`
	APIAccess         bool `json:"api_access"`
	WhiteLabel        bool `json:"white_label"`
}
