package orderprofiles

import (
	"time"
)

// Profile is one row of order_profiles plus its nested pricing rules.
// The JSON tags double as the public API shape — keep them stable.
type Profile struct {
	ID                string            `json:"id"`
	TenantID          string            `json:"tenantId"`
	Code              string            `json:"code"`
	Name              string            `json:"name"`
	NameTranslations  map[string]string `json:"nameTranslations"`
	Description       string            `json:"description"`
	IsActive          bool              `json:"isActive"`
	IsDefault         bool              `json:"isDefault"`
	Priority          int               `json:"priority"`
	Settings          ProfileSettings   `json:"settings"`
	PricingRules      []PricingRule     `json:"pricingRules"`
	CreatedAt         time.Time         `json:"createdAt"`
	UpdatedAt         time.Time         `json:"updatedAt"`
}

// ProfileSettings is the JSONB blob persisted on order_profiles.settings.
// Each field is independently optional so the operator can build up a
// profile over multiple edits.
type ProfileSettings struct {
	Schedule          []ScheduleSlot   `json:"schedule"`
	ServiceCharge     *ServiceCharge   `json:"serviceCharge,omitempty"`
	PrintRules        *PrintRules      `json:"printRules,omitempty"`
	Visibility        *Visibility      `json:"visibility,omitempty"`
	ReceiptTemplateID *string          `json:"receiptTemplateId,omitempty"`
}

// ScheduleSlot — "this profile is active on these weekdays between these
// times of day".  Weekdays use Go's time.Weekday convention: 0=Sunday,
// 1=Monday, …, 6=Saturday.  Times are wall-clock "HH:MM" strings in the
// tenant's local timezone (defaults to Europe/Zurich).  An ends_at < starts_at
// is treated as a slot that crosses midnight.
type ScheduleSlot struct {
	Weekdays []int  `json:"weekdays"`
	StartsAt string `json:"startsAt"` // "HH:MM"
	EndsAt   string `json:"endsAt"`   // "HH:MM"
}

// ServiceCharge is auto-appended to the cart when the profile is active.
// Kind "percent" interprets ValueCents as basis-points × 100 (i.e.
// ValueCents=1000 → 10%).  Kind "fixed" is a flat cents amount.  The flat
// form is what Late Night surcharges look like; percent is the form a
// future tip-suggestion preset would use.
type ServiceCharge struct {
	Kind       string `json:"kind"` // "percent" | "fixed"
	ValueCents int64  `json:"valueCents"`
	Label      string `json:"label"`
}

// PrintRules — should the kitchen/bar printer receive a ticket for orders
// taken under this profile, and how many receipt copies for the customer?
// Defaults (kitchen=true, bar=true, copies=1) apply when the profile has no
// printRules block at all.
type PrintRules struct {
	Kitchen        bool `json:"kitchen"`
	Bar            bool `json:"bar"`
	ReceiptCopies  int  `json:"receiptCopies"`
}

// Visibility — restrict the visible product set while this profile is
// active.  Mode "include" means only listed categories/products show; mode
// "exclude" hides them.  Empty Categories+Products with mode "include" is
// pathological and treated as "show everything" by the POS.
type Visibility struct {
	Mode       string   `json:"mode"` // "include" | "exclude"
	Categories []string `json:"categories"`
	Products   []string `json:"products"`
}

// PricingRule is one row of order_profile_pricing_rules.  Exactly one of
// CategoryID / ProductID is set (DB CHECK).  Exactly one of OverridePrice /
// DiscountPercent is set (DB CHECK).  Cents are absolute (e.g. CHF 7.50 →
// 750); the discount percent is 0–100.
type PricingRule struct {
	ID                 string   `json:"id"`
	CategoryID         *string  `json:"categoryId,omitempty"`
	ProductID          *string  `json:"productId,omitempty"`
	OverridePriceCents *int64   `json:"overridePriceCents,omitempty"`
	DiscountPercent    *float64 `json:"discountPercent,omitempty"`
}

// ActiveProfileSummary is the response shape of /order-profiles/active.
// IDs are sorted; consumers can stable-compare for change detection.
type ActiveProfileSummary struct {
	TenantID      string    `json:"tenantId"`
	ComputedAt    time.Time `json:"computedAt"`
	ActiveIDs     []string  `json:"activeIds"`
	DefaultID     *string   `json:"defaultId,omitempty"`
	WinnerID      *string   `json:"winnerId,omitempty"`
	WinnerProfile *Profile  `json:"winnerProfile,omitempty"`
}
