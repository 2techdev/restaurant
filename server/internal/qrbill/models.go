// Package qrbill implements Swiss QR-Bill generation (ISO 20022 / Swiss
// Payment Standards 2.0) for B2B invoice payments.
package qrbill

import "time"

// ---------------------------------------------------------------------------
// Request
// ---------------------------------------------------------------------------

// QRBillRequest is the POST body for POST /api/invoices/qrbill.
type QRBillRequest struct {
	// Creditor (payee)
	IBAN            string `json:"iban"`
	CreditorName    string `json:"creditor_name"`
	CreditorStreet  string `json:"creditor_street"`
	CreditorZip     string `json:"creditor_zip"`
	CreditorCity    string `json:"creditor_city"`
	CreditorCountry string `json:"creditor_country"` // default "CH"

	// Amount (optional – 0 means "no amount")
	Amount   float64 `json:"amount"`   // e.g. 150.50
	Currency string  `json:"currency"` // "CHF" or "EUR"; default "CHF"

	// Reference
	// ReferenceType: "NON" (no ref), "QRR" (QR Reference), "SCOR" (Creditor Ref)
	ReferenceType string `json:"reference_type"`
	Reference     string `json:"reference,omitempty"` // required when type is QRR/SCOR

	// Debtor (payer, optional)
	DebtorName    string `json:"debtor_name,omitempty"`
	DebtorStreet  string `json:"debtor_street,omitempty"`
	DebtorZip     string `json:"debtor_zip,omitempty"`
	DebtorCity    string `json:"debtor_city,omitempty"`
	DebtorCountry string `json:"debtor_country,omitempty"` // default "CH"

	// Extra
	Message   string `json:"message,omitempty"`    // unstructured message
	InvoiceID string `json:"invoice_id,omitempty"` // shown on slip for reference
}

// ---------------------------------------------------------------------------
// Response
// ---------------------------------------------------------------------------

// QRBillResponse is returned by POST /api/invoices/qrbill.
type QRBillResponse struct {
	// QRData is the raw data string to encode in the Swiss QR code.
	// Encode this with a QR-code library (error-correction level M, UTF-8).
	QRData string `json:"qr_data"`

	// Human-readable fields for the payment slip UI.
	IBAN            string `json:"iban"`
	AmountFormatted string `json:"amount_formatted"` // e.g. "CHF 150.50"
	Currency        string `json:"currency"`
	ReferenceType   string `json:"reference_type"`
	Reference       string `json:"reference,omitempty"`
	CreditorName    string `json:"creditor_name"`
	CreditorAddress string `json:"creditor_address"` // one-line address
	DebtorName      string `json:"debtor_name,omitempty"`
	DebtorAddress   string `json:"debtor_address,omitempty"`
	Message         string `json:"message,omitempty"`
	InvoiceID       string `json:"invoice_id,omitempty"`
	GeneratedAt     time.Time `json:"generated_at"`
}
