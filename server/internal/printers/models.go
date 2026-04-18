package printers

import "time"

// PrinterConfig is a single physical printer (kitchen, bar, or receipt)
// assigned to one store. Up to two rows per (store, target) may exist —
// at most one primary and one backup — enforced by partial unique indexes
// on the printer_configs table.
type PrinterConfig struct {
	ID          string    `json:"id"`
	TenantID    string    `json:"tenant_id"`
	StoreID     string    `json:"store_id"`
	Target      string    `json:"target"` // kitchen | bar | receipt
	Name        string    `json:"name"`
	Type        string    `json:"type"` // ethernet | usb
	IP          string    `json:"ip"`
	Port        int       `json:"port"`
	USBPath     string    `json:"usb_path,omitempty"`
	PaperWidth  string    `json:"paper_width"` // 58mm | 80mm
	Enabled     bool      `json:"enabled"`
	IsBackup    bool      `json:"is_backup"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// StorePrintersPayload is what GET/PUT /api/v1/stores/{id}/printers accepts
// and returns. The full set replaces the existing rows inside a transaction
// (PUT-as-replace semantics), keeping the clients' config load path a
// single request.
type StorePrintersPayload struct {
	StoreID  string          `json:"store_id"`
	Printers []PrinterConfig `json:"printers"`
}
