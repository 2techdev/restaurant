package loyalty

import (
	"encoding/json"
	"time"
)

// Tier is a per-tenant point bucket with an earn multiplier and benefits list.
type Tier struct {
	ID               string          `json:"id"`
	TenantID         string          `json:"tenant_id"`
	Code             string          `json:"code"`
	Name             string          `json:"name"`
	NameTranslations json.RawMessage `json:"name_translations,omitempty"`
	MinPoints        int             `json:"min_points"`
	MaxPoints        *int            `json:"max_points,omitempty"`
	Multiplier       float64         `json:"multiplier"`
	Benefits         json.RawMessage `json:"benefits"`
	ColorHex         *string         `json:"color_hex,omitempty"`
	SortOrder        int             `json:"sort_order"`
	IsActive         bool            `json:"is_active"`
	CreatedAt        time.Time       `json:"created_at"`
	UpdatedAt        time.Time       `json:"updated_at"`
}

// Settings is the per-tenant program toggle + earn/redeem rates.
type Settings struct {
	TenantID               string  `json:"tenant_id"`
	IsEnabled              bool    `json:"is_enabled"`
	EarnRatePointsPerCHF   float64 `json:"earn_rate_points_per_chf"`
	RedeemRatePointsPerCHF float64 `json:"redeem_rate_points_per_chf"`
	ExpiryMonths           int     `json:"expiry_months"`
}

// Account is the customer-facing summary view.
type Account struct {
	CustomerID    string     `json:"customer_id"`
	Name          string     `json:"name"`
	Points        int        `json:"points"`
	TotalEarned   int        `json:"total_earned"`
	CurrentTier   *string    `json:"current_tier,omitempty"`
	TierUpgradeAt *time.Time `json:"tier_upgrade_at,omitempty"`
	NextTier      *string    `json:"next_tier,omitempty"`
	PointsToNext  *int       `json:"points_to_next,omitempty"`
}

// EarnRequest — body of POST /api/v1/loyalty/earn.
type EarnRequest struct {
	CustomerID  string  `json:"customer_id"`
	OrderID     string  `json:"order_id,omitempty"`
	AmountCents int64   `json:"amount_cents"`           // order total — points derived from earn rate
	Points      *int    `json:"points,omitempty"`        // explicit override
	Description *string `json:"description,omitempty"`
}

// RedeemRequest — body of POST /api/v1/loyalty/redeem.
type RedeemRequest struct {
	CustomerID  string  `json:"customer_id"`
	OrderID     string  `json:"order_id,omitempty"`
	Points      int     `json:"points"`
	Description *string `json:"description,omitempty"`
}

// EarnResponse — what earn returns to caller.
type EarnResponse struct {
	PointsEarned    int     `json:"points_earned"`
	PointsBalance   int     `json:"points_balance"`
	TierBefore      *string `json:"tier_before,omitempty"`
	TierAfter       *string `json:"tier_after,omitempty"`
	TierUpgraded    bool    `json:"tier_upgraded"`
	MultiplierUsed  float64 `json:"multiplier_used"`
	BonusCampaignID *string `json:"bonus_campaign_id,omitempty"`
}

// RedeemResponse — what redeem returns to caller.
type RedeemResponse struct {
	PointsRedeemed   int     `json:"points_redeemed"`
	PointsBalance    int     `json:"points_balance"`
	CHFValueRedeemed float64 `json:"chf_value_redeemed"`
}

// BonusCampaign — earn multiplier window.
type BonusCampaign struct {
	ID          string    `json:"id"`
	TenantID    string    `json:"tenant_id"`
	Name        string    `json:"name"`
	Description *string   `json:"description,omitempty"`
	Multiplier  float64   `json:"multiplier"`
	StartsAt    time.Time `json:"starts_at"`
	EndsAt      time.Time `json:"ends_at"`
	IsActive    bool      `json:"is_active"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}
