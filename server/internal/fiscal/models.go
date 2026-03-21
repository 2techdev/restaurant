package fiscal

import "time"

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

// AuthRequest is the payload for the Fiskaly /auth endpoint.
type AuthRequest struct {
	APIKey    string `json:"api_key"`
	APISecret string `json:"api_secret"`
}

// AuthResponse is the Fiskaly /auth response.
type AuthResponse struct {
	AccessToken                string `json:"access_token"`
	AccessTokenExpiresInSeconds int64  `json:"access_token_expires_in_seconds"`
}

// ---------------------------------------------------------------------------
// TSS
// ---------------------------------------------------------------------------

// TSSState represents the lifecycle state of a TSS.
type TSSState string

const (
	TSSStateCreated      TSSState = "CREATED"
	TSSStateInitialized  TSSState = "INITIALIZED"
	TSSStateActive       TSSState = "ACTIVE"
	TSSStateDeactivated  TSSState = "DEACTIVATED"
	TSSStateDisabled     TSSState = "DISABLED"
)

// TSSInfo represents the state of a Technical Security System (TSS) from Fiskaly.
type TSSInfo struct {
	TSSID        string   `json:"_id"`
	State        TSSState `json:"state"`
	Description  string   `json:"description"`
	SerialNumber string   `json:"serial_number,omitempty"`
	PublicKey    string   `json:"public_key,omitempty"`
}

// CreateTSSRequest is the payload for creating/updating a TSS.
type CreateTSSRequest struct {
	Description string `json:"description"`
}

// UpdateTSSRequest is the payload for transitioning a TSS state.
type UpdateTSSRequest struct {
	State    TSSState `json:"state"`
	AdminPin string   `json:"admin_puk,omitempty"`
}

// ClientRegistrationRequest is the payload for registering a POS client.
type ClientRegistrationRequest struct {
	SerialNumber string `json:"serial_number"`
}

// ---------------------------------------------------------------------------
// Transactions
// ---------------------------------------------------------------------------

// TransactionState represents the lifecycle state of a transaction.
type TransactionState string

const (
	TransactionStateActive   TransactionState = "ACTIVE"
	TransactionStateFinished TransactionState = "FINISHED"
	TransactionStateFailed   TransactionState = "FAILED"
)

// AmountPerVatRate represents an amount broken down by VAT rate.
type AmountPerVatRate struct {
	VATRate string  `json:"vat_rate"`
	Amount  string  `json:"amount"`
}

// AmountPerPaymentType represents an amount broken down by payment type.
type AmountPerPaymentType struct {
	PaymentType string `json:"payment_type"`
	Amount      string `json:"amount"`
}

// ReceiptSchema is the DSFinV-K receipt process data.
type ReceiptSchema struct {
	ReceiptType           string                 `json:"receipt_type"`
	AmountsPerVatRate     []AmountPerVatRate     `json:"amounts_per_vat_rate"`
	AmountsPerPaymentType []AmountPerPaymentType `json:"amounts_per_payment_type"`
}

// StandardV1Schema wraps the receipt for the standard_v1 schema.
type StandardV1Schema struct {
	Receipt ReceiptSchema `json:"receipt"`
}

// TransactionSchema is the schema field in a finish-transaction request.
type TransactionSchema struct {
	StandardV1 StandardV1Schema `json:"standard_v1"`
}

// StartTransactionRequest is the payload to open a transaction (revision 1).
type StartTransactionRequest struct {
	State    TransactionState `json:"state"`
	ClientID string           `json:"client_id"`
}

// FinishTransactionRequest is the payload to close and sign a transaction.
type FinishTransactionRequest struct {
	State    TransactionState  `json:"state"`
	ClientID string            `json:"client_id"`
	Schema   TransactionSchema `json:"schema"`
}

// TransactionResponse is the Fiskaly API response for a transaction operation.
type TransactionResponse struct {
	TransactionID      string           `json:"_id"`
	State              TransactionState `json:"state"`
	LatestRevision     int              `json:"latest_revision"`
	StartDate          int64            `json:"time_start,omitempty"`
	EndDate            int64            `json:"time_end,omitempty"`
	SignatureAlgorithm string           `json:"signature_algorithm,omitempty"`
	Signature          string           `json:"signature,omitempty"`
	LogTimeFormat      string           `json:"log_time_format,omitempty"`
	TransactionNumber  int64            `json:"transaction_number,omitempty"`
}

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

// ExportTriggerRequest is the payload for triggering a DSFinV-K export.
type ExportTriggerRequest struct {
	StartDate *time.Time `json:"start_date,omitempty"`
	EndDate   *time.Time `json:"end_date,omitempty"`
}

// ExportResponse is the Fiskaly API response for a DSFinV-K export operation.
type ExportResponse struct {
	ExportID  string `json:"_id"`
	State     string `json:"state"`
	StartDate int64  `json:"time_start,omitempty"`
	EndDate   int64  `json:"time_end,omitempty"`
	URL       string `json:"url,omitempty"`
}
