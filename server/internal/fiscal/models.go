// Package fiscal provides German KassenSichV (§146a AO) fiscal compliance
// via the Fiskaly SIGN DE middleware API v2.
package fiscal

import "time"

// ---------------------------------------------------------------------------
// Fiskaly API request/response types
// ---------------------------------------------------------------------------

// AuthRequest is the body sent to POST /api/v2/auth.
type AuthRequest struct {
	APIKey    string `json:"api_key"`
	APISecret string `json:"api_secret"`
}

// AuthResponse is returned by POST /api/v2/auth.
type AuthResponse struct {
	AccessToken                  string `json:"access_token"`
	AccessTokenExpiresInSeconds  int    `json:"access_token_expires_in_seconds"`
	RefreshToken                 string `json:"refresh_token"`
}

// TSSState represents the lifecycle state of a TSS (Technical Security System).
type TSSState string

const (
	TSSStateCreated     TSSState = "CREATED"
	TSSStateInitialized TSSState = "INITIALIZED"
	TSSStateActive      TSSState = "ACTIVE"
	TSSStateDisabled    TSSState = "DISABLED"
)

// TSSInfo is the response from GET /api/v2/tss/{tss_id}.
type TSSInfo struct {
	ID                 string    `json:"_id"`
	State              TSSState  `json:"state"`
	Description        string    `json:"description"`
	SerialNumber       string    `json:"serial_number"`
	SignatureAlgorithm string    `json:"signature_algorithm"`
	SignatureCounter   int64     `json:"signature_counter"`
	TimeCreation       time.Time `json:"time_creation"`
}

// CreateTSSRequest is the body for PUT /api/v2/tss/{tss_id}.
type CreateTSSRequest struct {
	Description string `json:"description,omitempty"`
}

// UpdateTSSRequest is the body for PATCH /api/v2/tss/{tss_id}.
type UpdateTSSRequest struct {
	State    TSSState `json:"state"`
	AdminPin string   `json:"admin_pin,omitempty"`
}

// ClientRegistrationRequest is the body for PUT /api/v2/tss/{tss_id}/client/{client_id}.
type ClientRegistrationRequest struct {
	SerialNumber string `json:"serial_number"`
}

// TransactionState represents the state of a Fiskaly transaction.
type TransactionState string

const (
	TransactionStateActive   TransactionState = "ACTIVE"
	TransactionStateFinished TransactionState = "FINISHED"
)

// StartTransactionRequest is the body for PUT /api/v2/tss/{tss_id}/tx/{tx_id}?tx_revision=1.
type StartTransactionRequest struct {
	State    TransactionState `json:"state"`
	ClientID string           `json:"client_id"`
}

// AmountPerVatRate holds the VAT breakdown for one tax rate.
type AmountPerVatRate struct {
	VatRate string `json:"vat_rate"` // e.g. "19.00", "7.00", "NULL"
	Amount  string `json:"amount"`   // EUR amount as string e.g. "12.50"
}

// AmountPerPaymentType holds the payment breakdown.
type AmountPerPaymentType struct {
	PaymentType string `json:"payment_type"` // e.g. "Bar", "Unbar"
	Amount      string `json:"amount"`
}

// ReceiptSchema is the DSFinV-K receipt schema embedded in finish transaction.
type ReceiptSchema struct {
	ReceiptType           string                 `json:"receipt_type"` // "RECEIPT"
	AmountsPerVatRate     []AmountPerVatRate     `json:"amounts_per_vat_rate"`
	AmountsPerPaymentType []AmountPerPaymentType `json:"amounts_per_payment_type"`
}

// StandardV1Schema is the Fiskaly standard_v1 schema.
type StandardV1Schema struct {
	Receipt ReceiptSchema `json:"receipt"`
}

// TransactionSchema is the schema field in FinishTransactionRequest.
type TransactionSchema struct {
	StandardV1 StandardV1Schema `json:"standard_v1"`
}

// FinishTransactionRequest is the body for PUT /api/v2/tss/{tss_id}/tx/{tx_id}?tx_revision=N.
type FinishTransactionRequest struct {
	State    TransactionState  `json:"state"`
	ClientID string            `json:"client_id"`
	Schema   TransactionSchema `json:"schema"`
}

// TransactionSignature holds the signature block in a finished transaction.
type TransactionSignature struct {
	Value            string `json:"value"`            // Base64 signature
	SignatureCounter int64  `json:"signature_counter"` // cumulative counter
	Algorithm        string `json:"algorithm"`
}

// TransactionTSE holds TSE metadata in a finished transaction.
type TransactionTSE struct {
	SerialNumber       string `json:"serial_number"`
	SignatureAlgorithm string `json:"signature_algorithm"`
	PublicKey          string `json:"public_key"`
}

// TransactionResponse is returned after starting or finishing a transaction.
type TransactionResponse struct {
	ID                string               `json:"_id"`
	TransactionNumber int64                `json:"transaction_number"`
	State             TransactionState     `json:"state"`
	TimeStart         time.Time            `json:"time_start"`
	TimeEnd           *time.Time           `json:"time_end,omitempty"`
	ProcessType       string               `json:"process_type"`
	ProcessData       string               `json:"process_data"`
	Signature         TransactionSignature `json:"signature"`
	TSE               TransactionTSE       `json:"tse"`
}

// ExportState is the state of a TAR/DSFinV-K export job.
type ExportState string

const (
	ExportStatePending   ExportState = "PENDING"
	ExportStateWorking   ExportState = "WORKING"
	ExportStateCompleted ExportState = "COMPLETED"
	ExportStateFailed    ExportState = "FAILED"
)

// ExportTriggerRequest is the body for POST /api/v2/tss/{tss_id}/export.
type ExportTriggerRequest struct {
	StartDate *time.Time `json:"start_date,omitempty"`
	EndDate   *time.Time `json:"end_date,omitempty"`
}

// ExportResponse is returned by POST or GET /api/v2/tss/{tss_id}/export[/{id}].
type ExportResponse struct {
	ID          string      `json:"_id"`
	State       ExportState `json:"state"`
	Href        string      `json:"href,omitempty"`
	TimeStart   *time.Time  `json:"time_start,omitempty"`
	TimeEnd     *time.Time  `json:"time_end,omitempty"`
	Error       string      `json:"error,omitempty"`
}

// ---------------------------------------------------------------------------
// REST API request/response types (GastroCore server endpoints)
// ---------------------------------------------------------------------------

// InitTSERequest is the body for POST /api/fiscal/tse/init.
type InitTSERequest struct {
	TSEID       string `json:"tse_id"`        // UUID for the TSE
	ClientID    string `json:"client_id"`     // UUID for this terminal
	Description string `json:"description"`
	AdminPin    string `json:"admin_pin"`
}

// InitTSEResponse is returned after TSE initialization.
type InitTSEResponse struct {
	TSEID      string   `json:"tse_id"`
	ClientID   string   `json:"client_id"`
	State      TSSState `json:"state"`
	SerialNumber string `json:"serial_number"`
}

// SignTransactionRequest is the body for POST /api/fiscal/transaction/sign.
type SignTransactionRequest struct {
	TransactionID    string             `json:"transaction_id"`
	TSEID            string             `json:"tse_id"`
	ClientID         string             `json:"client_id"`
	AmountsPerVatRate []AmountPerVatRate `json:"amounts_per_vat_rate"`
	PaymentType      string             `json:"payment_type"`
	PaymentAmount    string             `json:"payment_amount"`
}

// SignTransactionResponse is returned after signing a transaction.
type SignTransactionResponse struct {
	TransactionNumber int64                `json:"transaction_number"`
	SignatureCounter  int64                `json:"signature_counter"`
	StartTime         time.Time            `json:"start_time"`
	EndTime           time.Time            `json:"end_time"`
	SignatureValue    string               `json:"signature_value"`
	TSESerialNumber   string               `json:"tse_serial_number"`
	Algorithm         string               `json:"algorithm"`
	PublicKey         string               `json:"public_key"`
	ProcessType       string               `json:"process_type"`
	ProcessData       string               `json:"process_data"`
}

// DSFinVKExportRequest is the query params for GET /api/fiscal/export/dsfinvk.
type DSFinVKExportRequest struct {
	TSEID     string     `json:"tse_id"`
	StartDate *time.Time `json:"start_date,omitempty"`
	EndDate   *time.Time `json:"end_date,omitempty"`
}
