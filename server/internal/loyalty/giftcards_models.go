package loyalty

import "time"

// GiftCard mirrors the gift_cards row (Swiss legal: 5-year min expiry).
type GiftCard struct {
	ID                  string     `json:"id"`
	TenantID            string     `json:"tenant_id"`
	Code                string     `json:"code"`
	DenominationCents   int64      `json:"denomination_cents"`
	BalanceCents        int64      `json:"balance_cents"`
	IssuedToCustomerID  *string    `json:"issued_to_customer_id,omitempty"`
	IssuedByUserID      *string    `json:"issued_by_user_id,omitempty"`
	IssuedAt            time.Time  `json:"issued_at"`
	ExpiresAt           time.Time  `json:"expires_at"`
	Status              string     `json:"status"`
	Notes               *string    `json:"notes,omitempty"`
	CreatedAt           time.Time  `json:"created_at"`
	UpdatedAt           time.Time  `json:"updated_at"`
}

type GiftCardTransaction struct {
	ID                string    `json:"id"`
	GiftCardID        string    `json:"gift_card_id"`
	TenantID          string    `json:"tenant_id"`
	Type              string    `json:"type"`
	AmountCents       int64     `json:"amount_cents"`
	OrderID           *string   `json:"order_id,omitempty"`
	BalanceAfterCents int64     `json:"balance_after_cents"`
	Description       *string   `json:"description,omitempty"`
	CreatedByUserID   *string   `json:"created_by_user_id,omitempty"`
	CreatedAt         time.Time `json:"created_at"`
}

// IssueGiftCardRequest — POST /api/v1/giftcards body.
type IssueGiftCardRequest struct {
	DenominationCents   int64   `json:"denomination_cents"`
	IssuedToCustomerID  *string `json:"issued_to_customer_id,omitempty"`
	ExpiresAt           *time.Time `json:"expires_at,omitempty"`
	Notes               *string `json:"notes,omitempty"`
}

// BulkIssueGiftCardsRequest — POST /api/v1/giftcards/bulk body.
type BulkIssueGiftCardsRequest struct {
	Quantity          int        `json:"quantity"`
	DenominationCents int64      `json:"denomination_cents"`
	ExpiresAt         *time.Time `json:"expires_at,omitempty"`
	Notes             *string    `json:"notes,omitempty"`
}

// RedeemGiftCardRequest — POST /api/v1/giftcards/{code}/redeem body.
type RedeemGiftCardRequest struct {
	AmountCents int64   `json:"amount_cents"`
	OrderID     *string `json:"order_id,omitempty"`
	Description *string `json:"description,omitempty"`
}

// RefundGiftCardRequest — POST /api/v1/giftcards/{code}/refund body.
type RefundGiftCardRequest struct {
	AmountCents int64   `json:"amount_cents"`
	OrderID     *string `json:"order_id,omitempty"`
	Description *string `json:"description,omitempty"`
}
