package crm

import "time"

// Customer is a CRM contact with loyalty data + extended profile fields
// (migration 038: tags, allergens, dietary_tags, anniversary, lifetime
// aggregates such as avg_ticket, favorite product/category, preferred
// hour bucket, preferred payment method).
type Customer struct {
	ID                     string     `json:"id"`
	TenantID               string     `json:"tenant_id"`
	Name                   string     `json:"name"`
	Phone                  *string    `json:"phone,omitempty"`
	Email                  *string    `json:"email,omitempty"`
	Birthday               *string    `json:"birthday,omitempty"` // YYYY-MM-DD
	Anniversary            *string    `json:"anniversary,omitempty"` // YYYY-MM-DD
	Notes                  *string    `json:"notes,omitempty"`
	LoyaltyPoints          int        `json:"loyalty_points"`
	TotalVisits            int        `json:"total_visits"`
	TotalSpentCents        int64      `json:"total_spent_cents"`
	AvgTicketCents         int64      `json:"avg_ticket_cents"`
	FirstVisitAt           *time.Time `json:"first_visit_at,omitempty"`
	LastVisitAt            *time.Time `json:"last_visit_at,omitempty"`
	Tags                   []string   `json:"tags"`
	Allergens              []string   `json:"allergens"`
	DietaryTags            []string   `json:"dietary_tags"`
	PreferredPaymentMethod *string    `json:"preferred_payment_method,omitempty"`
	PreferredHourBucket    *int       `json:"preferred_hour_bucket,omitempty"`
	FavoriteCategoryID     *string    `json:"favorite_category_id,omitempty"`
	FavoriteProductID      *string    `json:"favorite_product_id,omitempty"`
	CreatedAt              time.Time  `json:"created_at"`
	UpdatedAt              time.Time  `json:"updated_at"`
	IsDeleted              bool       `json:"is_deleted"`
}

// LoyaltyTransaction records a single point earn/redeem/adjust event.
type LoyaltyTransaction struct {
	ID          string    `json:"id"`
	TenantID    string    `json:"tenant_id"`
	CustomerID  string    `json:"customer_id"`
	Points      int       `json:"points"` // positive = earn, negative = redeem
	Type        string    `json:"type"`   // earn | redeem | adjust
	Description *string   `json:"description,omitempty"`
	TicketID    *string   `json:"ticket_id,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
}

// CreateCustomerRequest is the body for POST /api/v1/crm/customers.
type CreateCustomerRequest struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Phone       *string `json:"phone,omitempty"`
	Email       *string `json:"email,omitempty"`
	Birthday    *string `json:"birthday,omitempty"`
	Anniversary *string `json:"anniversary,omitempty"`
	Notes       *string `json:"notes,omitempty"`
}

// UpdateCustomerRequest is the body for PUT /api/v1/crm/customers/{id}.
// Any field left nil is preserved server-side via COALESCE. Slice fields
// (tags / allergens / dietary_tags) replace the existing array when present
// — pass an empty array to clear.
type UpdateCustomerRequest struct {
	Name                   *string   `json:"name,omitempty"`
	Phone                  *string   `json:"phone,omitempty"`
	Email                  *string   `json:"email,omitempty"`
	Birthday               *string   `json:"birthday,omitempty"`
	Anniversary            *string   `json:"anniversary,omitempty"`
	Notes                  *string   `json:"notes,omitempty"`
	Tags                   *[]string `json:"tags,omitempty"`
	Allergens              *[]string `json:"allergens,omitempty"`
	DietaryTags            *[]string `json:"dietary_tags,omitempty"`
	PreferredPaymentMethod *string   `json:"preferred_payment_method,omitempty"`
}

// LoyaltyRequest is the body for POST /api/v1/crm/customers/{id}/loyalty.
type LoyaltyRequest struct {
	ID          string  `json:"id"`
	Points      int     `json:"points"`
	Type        string  `json:"type"` // earn | redeem | adjust
	Description *string `json:"description,omitempty"`
	TicketID    *string `json:"ticket_id,omitempty"`
}

// ── Segments (migration 038) ────────────────────────────────────────────────

// Segment is a saved customer-filter definition. `is_dynamic = true` means
// membership is recomputed on every read against the live `customers` rows
// (the default; no materialized member list is kept). Set false to freeze a
// static membership snapshot.
type Segment struct {
	ID          string    `json:"id"`
	TenantID    string    `json:"tenant_id"`
	Name        string    `json:"name"`
	Description *string   `json:"description,omitempty"`
	Definition  SegmentDefinition `json:"definition"`
	IsDynamic   bool      `json:"is_dynamic"`
	CreatedBy   *string   `json:"created_by,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	IsDeleted   bool      `json:"is_deleted"`
	// Computed at read time when the caller asks for matching membership count.
	MemberCount *int `json:"member_count,omitempty"`
}

// SegmentDefinition is the JSONB blob stored in customer_segments.definition.
// Each filter is matched in Go (see segment_match.go).
type SegmentDefinition struct {
	Combinator string          `json:"combinator"` // "AND" | "OR" (default AND)
	Filters    []SegmentFilter `json:"filters"`
}

// SegmentFilter is one predicate in a segment's definition.
//
// Supported `type` values + their associated payload field:
//
//	last_visit_before_days        / Days
//	last_visit_after_days         / Days
//	total_visits_min              / Value
//	total_visits_max              / Value
//	total_visits_eq               / Value
//	total_spend_min_cents         / Value
//	total_spend_max_cents         / Value
//	has_tag                       / Tag
//	has_allergen                  / Tag
//	has_dietary_tag               / Tag
//	birthday_in_days              / Days   (next N days, inclusive)
//	anniversary_in_days           / Days
//	first_visit_before_days       / Days   (cohort: signed up > N days ago)
//	preferred_hour_bucket_in      / Hours  (e.g. [11,12,13] = lunch crowd)
//	preferred_payment_method      / Tag    (e.g. "cash", "card")
//	never_visited                 / (no payload)
type SegmentFilter struct {
	Type  string  `json:"type"`
	Days  *int    `json:"days,omitempty"`
	Value *int64  `json:"value,omitempty"`
	Tag   *string `json:"tag,omitempty"`
	Hours []int   `json:"hours,omitempty"`
}

// CreateSegmentRequest is the body for POST /api/v1/crm/segments.
type CreateSegmentRequest struct {
	ID          string             `json:"id"`
	Name        string             `json:"name"`
	Description *string            `json:"description,omitempty"`
	Definition  SegmentDefinition  `json:"definition"`
	IsDynamic   *bool              `json:"is_dynamic,omitempty"`
}

// UpdateSegmentRequest is the body for PUT /api/v1/crm/segments/{id}.
type UpdateSegmentRequest struct {
	Name        *string            `json:"name,omitempty"`
	Description *string            `json:"description,omitempty"`
	Definition  *SegmentDefinition `json:"definition,omitempty"`
	IsDynamic   *bool              `json:"is_dynamic,omitempty"`
}

// PreviewSegmentRequest applies a definition without persisting it; used by
// the segment editor in the backoffice to render a live "matched: 42" badge.
type PreviewSegmentRequest struct {
	Definition SegmentDefinition `json:"definition"`
	Limit      int               `json:"limit,omitempty"` // default 10, max 200
}

// ── Marketing Campaigns (migration 038) ─────────────────────────────────────

// MarketingCampaign targets a Segment with email/sms/push. Status
// transitions: draft → scheduled → sending → sent / failed / cancelled.
// (Separate concept from the existing `campaigns` table which links discounts.)
type MarketingCampaign struct {
	ID             string     `json:"id"`
	TenantID       string     `json:"tenant_id"`
	SegmentID      *string    `json:"segment_id,omitempty"`
	Name           string     `json:"name"`
	Channel        string     `json:"channel"` // email | sms | push
	Subject        *string    `json:"subject,omitempty"`
	BodyHTML       *string    `json:"body_html,omitempty"`
	BodyText       *string    `json:"body_text,omitempty"`
	TemplateKey    *string    `json:"template_key,omitempty"`
	ScheduledAt    *time.Time `json:"scheduled_at,omitempty"`
	SentAt         *time.Time `json:"sent_at,omitempty"`
	Status         string     `json:"status"`
	SentCount      int        `json:"sent_count"`
	OpenedCount    int        `json:"opened_count"`
	ClickedCount   int        `json:"clicked_count"`
	ConvertedCount int        `json:"converted_count"`
	CreatedBy      *string    `json:"created_by,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
	IsDeleted      bool       `json:"is_deleted"`
}

// CreateCampaignRequest is the body for POST /api/v1/crm/campaigns.
type CreateCampaignRequest struct {
	ID          string     `json:"id"`
	Name        string     `json:"name"`
	SegmentID   *string    `json:"segment_id,omitempty"`
	Channel     string     `json:"channel"`
	Subject     *string    `json:"subject,omitempty"`
	BodyHTML    *string    `json:"body_html,omitempty"`
	BodyText    *string    `json:"body_text,omitempty"`
	TemplateKey *string    `json:"template_key,omitempty"`
	ScheduledAt *time.Time `json:"scheduled_at,omitempty"`
}

// UpdateCampaignRequest is the body for PUT /api/v1/crm/campaigns/{id}.
type UpdateCampaignRequest struct {
	Name        *string    `json:"name,omitempty"`
	SegmentID   *string    `json:"segment_id,omitempty"`
	Channel     *string    `json:"channel,omitempty"`
	Subject     *string    `json:"subject,omitempty"`
	BodyHTML    *string    `json:"body_html,omitempty"`
	BodyText    *string    `json:"body_text,omitempty"`
	TemplateKey *string    `json:"template_key,omitempty"`
	ScheduledAt *time.Time `json:"scheduled_at,omitempty"`
	Status      *string    `json:"status,omitempty"`
}

// CampaignRecipient is a per-customer attribution row.
type CampaignRecipient struct {
	ID               string     `json:"id"`
	CampaignID       string     `json:"campaign_id"`
	CustomerID       string     `json:"customer_id"`
	CustomerName     *string    `json:"customer_name,omitempty"`
	CustomerEmail    *string    `json:"customer_email,omitempty"`
	TenantID         string     `json:"tenant_id"`
	SentAt           *time.Time `json:"sent_at,omitempty"`
	OpenedAt         *time.Time `json:"opened_at,omitempty"`
	ClickedAt        *time.Time `json:"clicked_at,omitempty"`
	ConvertedOrderID *string    `json:"converted_order_id,omitempty"`
	Error            *string    `json:"error,omitempty"`
	CreatedAt        time.Time  `json:"created_at"`
}

// CampaignStats is the aggregated performance summary for one campaign.
type CampaignStats struct {
	CampaignID     string  `json:"campaign_id"`
	Status         string  `json:"status"`
	Recipients     int     `json:"recipients"`
	SentCount      int     `json:"sent_count"`
	OpenedCount    int     `json:"opened_count"`
	ClickedCount   int     `json:"clicked_count"`
	ConvertedCount int     `json:"converted_count"`
	OpenRate       float64 `json:"open_rate"`       // opened / sent
	ClickRate      float64 `json:"click_rate"`      // clicked / sent
	ConversionRate float64 `json:"conversion_rate"` // converted / sent
}

// ── Extended profile aggregate (read-only) ──────────────────────────────────

// ExtendedProfile combines the Customer record with derived aggregates and
// recent loyalty/order activity counters.
type ExtendedProfile struct {
	Customer        Customer            `json:"customer"`
	RecentOrders    int                 `json:"recent_orders"`    // last 90 days
	OrderCount      int                 `json:"order_count"`
	LoyaltyEarned   int                 `json:"loyalty_earned"`   // sum of positive points
	LoyaltyRedeemed int                 `json:"loyalty_redeemed"` // sum of |negative| points
	SegmentIDs      []string            `json:"segment_ids"`      // segments the customer currently matches
	FavoriteProduct *FavoriteProductRef `json:"favorite_product,omitempty"`
}

// FavoriteProductRef is a lightweight view of the customer's #1 product.
type FavoriteProductRef struct {
	ProductID  string  `json:"product_id"`
	Name       string  `json:"name"`
	OrderCount int     `json:"order_count"`
	CategoryID *string `json:"category_id,omitempty"`
}

// RefreshAggregatesResponse is returned by POST /api/v1/crm/aggregates/refresh.
type RefreshAggregatesResponse struct {
	TenantID        string `json:"tenant_id"`
	CustomersTotal  int    `json:"customers_total"`
	CustomersUpdated int   `json:"customers_updated"`
	DurationMs      int64  `json:"duration_ms"`
}
