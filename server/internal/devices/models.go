package devices

import "time"

// Device represents a registered POS terminal or display.
type Device struct {
	ID           string              `json:"id"`
	TenantID     string              `json:"tenant_id"`
	Name         string              `json:"name"`
	DeviceType   string              `json:"device_type"` // pos, kds, kiosk, waiter
	Status       string              `json:"status"`      // active, inactive, suspended
	TokenHash    string              `json:"-"`           // never expose in API
	AppVersion   string              `json:"app_version,omitempty"`
	OSVersion    string              `json:"os_version,omitempty"`
	Capabilities *DeviceCapabilities `json:"capabilities,omitempty"`
	LastSeenAt   *time.Time          `json:"last_seen_at,omitempty"`
	CreatedAt    time.Time           `json:"created_at"`
	UpdatedAt    time.Time           `json:"updated_at"`
	IsDeleted    bool                `json:"is_deleted"`
}

// DeviceCapabilities describes what a device can do.
type DeviceCapabilities struct {
	HasPrinter       bool   `json:"has_printer"`
	HasCashDrawer    bool   `json:"has_cash_drawer"`
	HasScanner       bool   `json:"has_scanner"`
	HasCustomerDisplay bool `json:"has_customer_display"`
	PrinterType      string `json:"printer_type,omitempty"` // thermal, impact, none
	ScreenSize       string `json:"screen_size,omitempty"`  // small, medium, large
	SupportsNFC      bool   `json:"supports_nfc"`
}
