package fiscal

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"
)

const fiskalyBaseURL = "https://kassensichv-middleware.fiskaly.com/api/v2"

// FiskalyClient is an HTTP client for the Fiskaly SIGN DE middleware API v2.
//
// It caches JWT tokens in-memory and refreshes them automatically
// before expiry. All methods are safe for concurrent use.
type FiskalyClient struct {
	apiKey    string
	apiSecret string
	baseURL   string
	httpClient *http.Client

	mu          sync.Mutex
	accessToken string
	tokenExpiry time.Time
}

// NewFiskalyClient creates a new FiskalyClient.
func NewFiskalyClient(apiKey, apiSecret string) *FiskalyClient {
	return &FiskalyClient{
		apiKey:    apiKey,
		apiSecret: apiSecret,
		baseURL:   fiskalyBaseURL,
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}
}

// ---------------------------------------------------------------------------
// Authentication
// ---------------------------------------------------------------------------

// Authenticate obtains (or returns a cached) JWT access token.
// The token is refreshed automatically 5 minutes before expiry.
func (c *FiskalyClient) Authenticate() (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.accessToken != "" && time.Now().Before(c.tokenExpiry.Add(-5*time.Minute)) {
		return c.accessToken, nil
	}

	reqBody := AuthRequest{
		APIKey:    c.apiKey,
		APISecret: c.apiSecret,
	}
	var resp AuthResponse
	if err := c.doRequest(http.MethodPost, "/auth", nil, reqBody, &resp); err != nil {
		return "", fmt.Errorf("fiskaly authenticate: %w", err)
	}

	c.accessToken = resp.AccessToken
	expiry := resp.AccessTokenExpiresInSeconds
	if expiry <= 0 {
		expiry = 3600
	}
	c.tokenExpiry = time.Now().Add(time.Duration(expiry) * time.Second)
	return c.accessToken, nil
}

// ---------------------------------------------------------------------------
// TSS management
// ---------------------------------------------------------------------------

// CreateTSS creates or updates a TSS by UUID. Idempotent.
func (c *FiskalyClient) CreateTSS(tssID, description string) (*TSSInfo, error) {
	token, err := c.Authenticate()
	if err != nil {
		return nil, err
	}
	req := CreateTSSRequest{Description: description}
	var info TSSInfo
	if err := c.doRequest(http.MethodPut, "/tss/"+tssID, &token, req, &info); err != nil {
		return nil, fmt.Errorf("fiskaly createTSS: %w", err)
	}
	return &info, nil
}

// GetTSSInfo returns the current state and metadata of a TSS.
func (c *FiskalyClient) GetTSSInfo(tssID string) (*TSSInfo, error) {
	token, err := c.Authenticate()
	if err != nil {
		return nil, err
	}
	var info TSSInfo
	if err := c.doRequest(http.MethodGet, "/tss/"+tssID, &token, nil, &info); err != nil {
		return nil, fmt.Errorf("fiskaly getTSSInfo: %w", err)
	}
	return &info, nil
}

// InitializeTSS transitions the TSS to INITIALIZED state (sets admin PIN).
func (c *FiskalyClient) InitializeTSS(tssID, adminPin string) (*TSSInfo, error) {
	token, err := c.Authenticate()
	if err != nil {
		return nil, err
	}
	req := UpdateTSSRequest{State: TSSStateInitialized, AdminPin: adminPin}
	var info TSSInfo
	if err := c.doRequest(http.MethodPatch, "/tss/"+tssID, &token, req, &info); err != nil {
		return nil, fmt.Errorf("fiskaly initializeTSS: %w", err)
	}
	return &info, nil
}

// ActivateTSS transitions the TSS to ACTIVE state.
func (c *FiskalyClient) ActivateTSS(tssID, adminPin string) (*TSSInfo, error) {
	token, err := c.Authenticate()
	if err != nil {
		return nil, err
	}
	req := UpdateTSSRequest{State: TSSStateActive, AdminPin: adminPin}
	var info TSSInfo
	if err := c.doRequest(http.MethodPatch, "/tss/"+tssID, &token, req, &info); err != nil {
		return nil, fmt.Errorf("fiskaly activateTSS: %w", err)
	}
	return &info, nil
}

// RegisterClient registers a POS terminal client with the TSS.
func (c *FiskalyClient) RegisterClient(tssID, clientID, serialNumber string) error {
	token, err := c.Authenticate()
	if err != nil {
		return err
	}
	req := ClientRegistrationRequest{SerialNumber: serialNumber}
	var result map[string]any
	if err := c.doRequest(http.MethodPut, "/tss/"+tssID+"/client/"+clientID, &token, req, &result); err != nil {
		return fmt.Errorf("fiskaly registerClient: %w", err)
	}
	return nil
}

// RunSelfTest triggers the TSS self-test (BSI TR-03153 §4.6.2).
func (c *FiskalyClient) RunSelfTest(tssID string) (*TSSInfo, error) {
	token, err := c.Authenticate()
	if err != nil {
		return nil, err
	}
	var info TSSInfo
	if err := c.doRequest(http.MethodPost, "/tss/"+tssID+"/self_test", &token, nil, &info); err != nil {
		return nil, fmt.Errorf("fiskaly runSelfTest: %w", err)
	}
	return &info, nil
}

// ---------------------------------------------------------------------------
// Transactions
// ---------------------------------------------------------------------------

// StartTransaction opens a new transaction on the TSS (tx_revision=1).
func (c *FiskalyClient) StartTransaction(tssID, txID, clientID string) (*TransactionResponse, error) {
	token, err := c.Authenticate()
	if err != nil {
		return nil, err
	}
	req := StartTransactionRequest{
		State:    TransactionStateActive,
		ClientID: clientID,
	}
	var resp TransactionResponse
	path := fmt.Sprintf("/tss/%s/tx/%s?tx_revision=1", tssID, txID)
	if err := c.doRequest(http.MethodPut, path, &token, req, &resp); err != nil {
		return nil, fmt.Errorf("fiskaly startTransaction: %w", err)
	}
	return &resp, nil
}

// FinishTransaction closes and signs a transaction (tx_revision=txRev).
func (c *FiskalyClient) FinishTransaction(
	tssID, txID, clientID string,
	amountsPerVatRate []AmountPerVatRate,
	paymentType, paymentAmount string,
	txRevision int,
) (*TransactionResponse, error) {
	token, err := c.Authenticate()
	if err != nil {
		return nil, err
	}

	req := FinishTransactionRequest{
		State:    TransactionStateFinished,
		ClientID: clientID,
		Schema: TransactionSchema{
			StandardV1: StandardV1Schema{
				Receipt: ReceiptSchema{
					ReceiptType:       "RECEIPT",
					AmountsPerVatRate: amountsPerVatRate,
					AmountsPerPaymentType: []AmountPerPaymentType{
						{PaymentType: paymentType, Amount: paymentAmount},
					},
				},
			},
		},
	}

	var resp TransactionResponse
	path := fmt.Sprintf("/tss/%s/tx/%s?tx_revision=%d", tssID, txID, txRevision)
	if err := c.doRequest(http.MethodPut, path, &token, req, &resp); err != nil {
		return nil, fmt.Errorf("fiskaly finishTransaction: %w", err)
	}
	return &resp, nil
}

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

// TriggerExport initiates a DSFinV-K / TAR export on Fiskaly.
func (c *FiskalyClient) TriggerExport(tssID string, startDate, endDate *time.Time) (*ExportResponse, error) {
	token, err := c.Authenticate()
	if err != nil {
		return nil, err
	}
	req := ExportTriggerRequest{StartDate: startDate, EndDate: endDate}
	var resp ExportResponse
	if err := c.doRequest(http.MethodPost, "/tss/"+tssID+"/export", &token, req, &resp); err != nil {
		return nil, fmt.Errorf("fiskaly triggerExport: %w", err)
	}
	return &resp, nil
}

// GetExportStatus returns the current status of an export job.
func (c *FiskalyClient) GetExportStatus(tssID, exportID string) (*ExportResponse, error) {
	token, err := c.Authenticate()
	if err != nil {
		return nil, err
	}
	var resp ExportResponse
	if err := c.doRequest(http.MethodGet, "/tss/"+tssID+"/export/"+exportID, &token, nil, &resp); err != nil {
		return nil, fmt.Errorf("fiskaly getExportStatus: %w", err)
	}
	return &resp, nil
}

// ---------------------------------------------------------------------------
// HTTP helper
// ---------------------------------------------------------------------------

// FiskalyError is returned when the Fiskaly API returns a non-2xx status.
type FiskalyError struct {
	StatusCode int
	Body       string
}

func (e *FiskalyError) Error() string {
	return fmt.Sprintf("fiskaly API error %d: %s", e.StatusCode, e.Body)
}

// doRequest executes an authenticated HTTP request and decodes the JSON response.
// If token is nil, the request is sent without an Authorization header.
func (c *FiskalyClient) doRequest(method, path string, token *string, body any, out any) error {
	var bodyReader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("marshal request: %w", err)
		}
		bodyReader = bytes.NewReader(b)
	}

	req, err := http.NewRequest(method, c.baseURL+path, bodyReader)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if token != nil && *token != "" {
		req.Header.Set("Authorization", "Bearer "+*token)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("execute request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return &FiskalyError{StatusCode: resp.StatusCode, Body: string(respBody)}
	}

	if out != nil && len(respBody) > 0 {
		if err := json.Unmarshal(respBody, out); err != nil {
			return fmt.Errorf("decode response: %w", err)
		}
	}
	return nil
}
