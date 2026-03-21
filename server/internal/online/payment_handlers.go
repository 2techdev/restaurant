package online

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

// ---------------------------------------------------------------------------
// POST /api/v1/online/payment/checkout
// ---------------------------------------------------------------------------

// handleCreateCheckout creates a Stripe Checkout Session for an online order.
// The frontend redirects the customer to the returned checkout_url.
// No authentication required — restaurantId + orderId are validated.
func (m *Module) handleCreateCheckout(w http.ResponseWriter, r *http.Request) {
	if m.stripeCfg.SecretKey == "" {
		response.Error(w, http.StatusServiceUnavailable, "STRIPE_NOT_CONFIGURED",
			"Online payment is not configured on this server")
		return
	}

	var req CreateCheckoutRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.OrderID == "" || req.RestaurantID == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_FIELDS",
			"order_id and restaurant_id are required")
		return
	}
	if req.AmountCents <= 0 {
		response.Error(w, http.StatusBadRequest, "INVALID_AMOUNT", "amount_cents must be > 0")
		return
	}

	currency := req.Currency
	if currency == "" {
		currency = "chf"
	}
	currency = strings.ToLower(currency)

	// Build Stripe success / cancel URLs
	successURL := fmt.Sprintf("%s/%s/confirmation/%s?number=%s&paid=1",
		m.stripeCfg.SuccessURLBase, req.RestaurantID, req.OrderID, req.OrderID)
	cancelURL := fmt.Sprintf("%s/%s/checkout?cancelled=1",
		m.stripeCfg.SuccessURLBase, req.RestaurantID)

	// Build Stripe Checkout Session via form-encoded POST (no SDK needed)
	sessionURL, sessionID, err := m.createStripeCheckoutSession(stripeCheckoutParams{
		SecretKey:   m.stripeCfg.SecretKey,
		AmountCents: req.AmountCents,
		Currency:    currency,
		Description: req.Description,
		SuccessURL:  successURL,
		CancelURL:   cancelURL,
		Metadata: map[string]string{
			"order_id":      req.OrderID,
			"restaurant_id": req.RestaurantID,
		},
	})
	if err != nil {
		slog.Error("stripe: create session", "error", err)
		response.Error(w, http.StatusBadGateway, "STRIPE_ERROR",
			"Could not create payment session")
		return
	}

	// Store stripe_session_id on the ticket for webhook reconciliation
	_, _ = m.db.ExecContext(r.Context(), `
		UPDATE tickets
		SET notes = COALESCE(notes, '') || ' [stripe:' || $1 || ']',
		    updated_at = $2
		WHERE id = $3
	`, sessionID, time.Now().UTC(), req.OrderID)

	slog.Info("stripe: checkout session created",
		"session_id", sessionID,
		"order_id", req.OrderID,
		"amount_cents", req.AmountCents,
	)

	resp := CreateCheckoutResponse{
		CheckoutURL: sessionURL,
		SessionID:   sessionID,
		OrderID:     req.OrderID,
	}
	response.JSON(w, http.StatusOK, resp)
}

// ---------------------------------------------------------------------------
// POST /api/v1/online/payment/webhook
// ---------------------------------------------------------------------------

// handleStripeWebhook receives and processes Stripe webhook events.
// Stripe signature is verified using HMAC-SHA256.
func (m *Module) handleStripeWebhook(w http.ResponseWriter, r *http.Request) {
	if m.stripeCfg.WebhookSecret == "" {
		// If no webhook secret configured, accept but do nothing (dev mode)
		w.WriteHeader(http.StatusOK)
		return
	}

	payload, err := io.ReadAll(io.LimitReader(r.Body, 1<<20)) // 1 MiB max
	if err != nil {
		response.Error(w, http.StatusBadRequest, "READ_FAILED", "Could not read body")
		return
	}

	sig := r.Header.Get("Stripe-Signature")
	if !verifyStripeSignature(payload, sig, m.stripeCfg.WebhookSecret) {
		response.Error(w, http.StatusUnauthorized, "INVALID_SIGNATURE",
			"Stripe signature verification failed")
		return
	}

	var event stripeEvent
	if err := json.Unmarshal(payload, &event); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_EVENT", "Could not parse event")
		return
	}

	switch event.Type {
	case "checkout.session.completed":
		m.handleSessionCompleted(r, event)
	case "checkout.session.expired":
		m.handleSessionExpired(r, event)
	default:
		// Acknowledged but not handled
		slog.Debug("stripe: unhandled event type", "type", event.Type)
	}

	w.WriteHeader(http.StatusOK)
}

// handleSessionCompleted marks the order as paid when Stripe Checkout completes.
func (m *Module) handleSessionCompleted(r *http.Request, event stripeEvent) {
	sessionID, _ := event.Data["object"].(map[string]interface{})["id"].(string)
	metadata, _ := event.Data["object"].(map[string]interface{})["metadata"].(map[string]interface{})
	orderID, _ := metadata["order_id"].(string)
	amountTotal, _ := event.Data["object"].(map[string]interface{})["amount_total"].(float64)

	if orderID == "" && sessionID != "" {
		// Fallback: find order by session ID stored in notes
		_ = m.db.QueryRowContext(r.Context(), `
			SELECT id FROM tickets WHERE notes LIKE '%[stripe:' || $1 || ']%' LIMIT 1
		`, sessionID).Scan(&orderID)
	}

	if orderID == "" {
		slog.Warn("stripe: webhook session.completed — no order_id found",
			"session_id", sessionID)
		return
	}

	now := time.Now().UTC()
	_, err := m.db.ExecContext(r.Context(), `
		UPDATE tickets
		SET status = 'fully_paid',
		    total = CASE WHEN $2 > 0 THEN $2 ELSE total END,
		    updated_at = $3
		WHERE id = $1
	`, orderID, int64(amountTotal), now)
	if err != nil {
		slog.Error("stripe: update ticket status", "error", err, "order_id", orderID)
		return
	}

	slog.Info("stripe: order marked as paid",
		"order_id", orderID,
		"session_id", sessionID,
		"amount_total", amountTotal,
	)
}

// handleSessionExpired logs expired sessions.
func (m *Module) handleSessionExpired(r *http.Request, event stripeEvent) {
	sessionID, _ := event.Data["object"].(map[string]interface{})["id"].(string)
	slog.Info("stripe: checkout session expired", "session_id", sessionID)
}

// ---------------------------------------------------------------------------
// Stripe API helpers
// ---------------------------------------------------------------------------

type stripeCheckoutParams struct {
	SecretKey   string
	AmountCents int64
	Currency    string
	Description string
	SuccessURL  string
	CancelURL   string
	Metadata    map[string]string
}

// createStripeCheckoutSession calls the Stripe REST API to create a session.
// Returns (checkout_url, session_id, error).
func (m *Module) createStripeCheckoutSession(p stripeCheckoutParams) (string, string, error) {
	form := url.Values{}
	form.Set("mode", "payment")
	form.Set("line_items[0][price_data][currency]", p.Currency)
	form.Set("line_items[0][price_data][unit_amount]", strconv.FormatInt(p.AmountCents, 10))
	form.Set("line_items[0][price_data][product_data][name]",
		ifEmpty(p.Description, "Restaurant Order"))
	form.Set("line_items[0][quantity]", "1")
	form.Set("success_url", p.SuccessURL)
	form.Set("cancel_url", p.CancelURL)
	for k, v := range p.Metadata {
		form.Set(fmt.Sprintf("metadata[%s]", k), v)
	}

	req, err := http.NewRequest(http.MethodPost,
		"https://api.stripe.com/v1/checkout/sessions",
		strings.NewReader(form.Encode()))
	if err != nil {
		return "", "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.SetBasicAuth(p.SecretKey, "")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return "", "", fmt.Errorf("stripe API %d: %s", resp.StatusCode, body)
	}

	var result struct {
		ID  string `json:"id"`
		URL string `json:"url"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", "", err
	}
	return result.URL, result.ID, nil
}

// verifyStripeSignature validates the Stripe-Signature header using HMAC-SHA256.
// See: https://stripe.com/docs/webhooks/signatures
func verifyStripeSignature(payload []byte, sigHeader, secret string) bool {
	if sigHeader == "" || secret == "" {
		return false
	}

	// Parse t=<timestamp>,v1=<sig1>[,v1=<sig2>]
	parts := strings.Split(sigHeader, ",")
	var timestamp string
	var sigs []string
	for _, part := range parts {
		if strings.HasPrefix(part, "t=") {
			timestamp = strings.TrimPrefix(part, "t=")
		} else if strings.HasPrefix(part, "v1=") {
			sigs = append(sigs, strings.TrimPrefix(part, "v1="))
		}
	}
	if timestamp == "" || len(sigs) == 0 {
		return false
	}

	// Tolerance: 5 minutes
	ts, err := strconv.ParseInt(timestamp, 10, 64)
	if err != nil {
		return false
	}
	if time.Now().Unix()-ts > 300 {
		return false
	}

	// Compute expected signature
	signed := timestamp + "." + string(payload)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(signed))
	expected := hex.EncodeToString(mac.Sum(nil))

	for _, sig := range sigs {
		if hmac.Equal([]byte(sig), []byte(expected)) {
			return true
		}
	}
	return false
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func ifEmpty(s, fallback string) string {
	if s == "" {
		return fallback
	}
	return s
}

// stripeEvent is a minimal Stripe webhook event.
type stripeEvent struct {
	ID   string                 `json:"id"`
	Type string                 `json:"type"`
	Data map[string]interface{} `json:"data"`
}
