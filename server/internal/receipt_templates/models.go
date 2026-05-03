package receipt_templates

import "time"

// Template represents a printable receipt layout for a tenant.
type Template struct {
	ID         string    `json:"id"`
	TenantID   string    `json:"tenant_id"`
	Name       string    `json:"name"`
	Language   string    `json:"language"`    // de | fr | it | en | tr
	WidthMM    int       `json:"width_mm"`    // 58 or 80
	IsDefault  bool      `json:"is_default"`
	Header     string    `json:"header"`
	BodyFormat string    `json:"body_format"`
	Footer     string    `json:"footer"`
	PaperCut   bool      `json:"paper_cut"`
	OpenDrawer bool      `json:"open_drawer"`
	Copies     int       `json:"copies"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type upsertReq struct {
	Name       string `json:"name"`
	Language   string `json:"language"`
	WidthMM    int    `json:"width_mm"`
	IsDefault  bool   `json:"is_default"`
	Header     string `json:"header"`
	BodyFormat string `json:"body_format"`
	Footer     string `json:"footer"`
	PaperCut   *bool  `json:"paper_cut"`
	OpenDrawer *bool  `json:"open_drawer"`
	Copies     *int   `json:"copies"`
}

// TestPrintReq carries the inputs for /test-print — a server-side render
// preview returning the resolved text. Real ESC/POS dispatch happens on the
// POS device; the backoffice only needs to verify variable substitution.
type TestPrintReq struct {
	PrinterID string         `json:"printer_id,omitempty"` // optional, future use
	Sample    *SampleContext `json:"sample,omitempty"`
}

// RenderResp returned by /test-print: the resolved text the operator would see.
type RenderResp struct {
	Text     string `json:"text"`
	WidthMM  int    `json:"width_mm"`
	Language string `json:"language"`
}

// SampleContext is the full set of values used to render a template.
// Allows the backoffice to override defaults for a fully realistic preview.
type SampleContext struct {
	TenantName    string `json:"tenant_name"`
	TenantAddress string `json:"tenant_address"`
	TenantPhone   string `json:"tenant_phone"`
	TenantUID     string `json:"tenant_uid"`
	TenantIBAN    string `json:"tenant_iban"`
	TenantWebsite string `json:"tenant_website"`

	OrderNo         string `json:"order_no"`
	DateCH          string `json:"date_ch"`
	TimeCH          string `json:"time_ch"`
	TableOrTakeaway string `json:"table_or_takeaway"`
	CashierName     string `json:"cashier_name"`
	CustomerName    string `json:"customer_name"`

	Items []SampleItem `json:"items"`

	DiscountAmount float64 `json:"discount_amount"`
	TipAmount      float64 `json:"tip_amount"`

	PaymentMethod string `json:"payment_method"` // Bargeld | Karte | TWINT
	IsCash        bool   `json:"is_cash"`

	FiskalySignature string `json:"fiskaly_signature"`
	TSRSerial        string `json:"tsr_serial"`
}

type SampleItem struct {
	Qty       int     `json:"qty"`
	Name      string  `json:"name"`
	UnitPrice float64 `json:"unit_price"`
	VATRate   float64 `json:"vat_rate"` // 8.1, 2.6, 3.8, 0
}
