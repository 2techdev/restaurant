package crm

import "time"

// Customer is a CRM contact with loyalty data.
type Customer struct {
	ID              string     `json:"id"`
	TenantID        string     `json:"tenant_id"`
	Name            string     `json:"name"`
	Phone           *string    `json:"phone,omitempty"`
	Email           *string    `json:"email,omitempty"`
	Birthday        *string    `json:"birthday,omitempty"` // YYYY-MM-DD
	Notes           *string    `json:"notes,omitempty"`
	LoyaltyPoints   int        `json:"loyalty_points"`
	TotalVisits     int        `json:"total_visits"`
	TotalSpentCents int64      `json:"total_spent_cents"`
	LastVisitAt     *time.Time `json:"last_visit_at,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
	IsDeleted       bool       `json:"is_deleted"`
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
	ID       string  `json:"id"`
	Name     string  `json:"name"`
	Phone    *string `json:"phone,omitempty"`
	Email    *string `json:"email,omitempty"`
	Birthday *string `json:"birthday,omitempty"`
	Notes    *string `json:"notes,omitempty"`
}

// UpdateCustomerRequest is the body for PUT /api/v1/crm/customers/{id}.
type UpdateCustomerRequest struct {
	Name     *string `json:"name,omitempty"`
	Phone    *string `json:"phone,omitempty"`
	Email    *string `json:"email,omitempty"`
	Birthday *string `json:"birthday,omitempty"`
	Notes    *string `json:"notes,omitempty"`
}

// LoyaltyRequest is the body for POST /api/v1/crm/customers/{id}/loyalty.
type LoyaltyRequest struct {
	ID          string  `json:"id"`
	Points      int     `json:"points"`
	Type        string  `json:"type"` // earn | redeem | adjust
	Description *string `json:"description,omitempty"`
	TicketID    *string `json:"ticket_id,omitempty"`
}
