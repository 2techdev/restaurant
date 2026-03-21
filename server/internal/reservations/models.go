package reservations

import "time"

// Reservation represents a table booking.
type Reservation struct {
	ID           string     `json:"id"`
	TenantID     string     `json:"tenant_id"`
	CustomerName string     `json:"customer_name"`
	Phone        *string    `json:"phone,omitempty"`
	GuestCount   int        `json:"guest_count"`
	TableID      *string    `json:"table_id,omitempty"`
	Date         string     `json:"date"`          // YYYY-MM-DD
	Time         string     `json:"time"`          // HH:MM (24h)
	DurationMins int        `json:"duration_minutes"`
	Status       string     `json:"status"` // pending | confirmed | seated | cancelled | no_show
	Notes        *string    `json:"notes,omitempty"`
	CustomerID   *string    `json:"customer_id,omitempty"` // optional CRM link
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
	IsDeleted    bool       `json:"is_deleted"`
}

// CreateReservationRequest is the body for POST /api/v1/reservations.
type CreateReservationRequest struct {
	ID           string  `json:"id"`
	CustomerName string  `json:"customer_name"`
	Phone        *string `json:"phone,omitempty"`
	GuestCount   int     `json:"guest_count"`
	TableID      *string `json:"table_id,omitempty"`
	Date         string  `json:"date"`
	Time         string  `json:"time"`
	DurationMins int     `json:"duration_minutes"`
	Notes        *string `json:"notes,omitempty"`
	CustomerID   *string `json:"customer_id,omitempty"`
}

// UpdateReservationRequest is the body for PUT /api/v1/reservations/{id}.
type UpdateReservationRequest struct {
	CustomerName *string `json:"customer_name,omitempty"`
	Phone        *string `json:"phone,omitempty"`
	GuestCount   *int    `json:"guest_count,omitempty"`
	TableID      *string `json:"table_id,omitempty"`
	Date         *string `json:"date,omitempty"`
	Time         *string `json:"time,omitempty"`
	DurationMins *int    `json:"duration_minutes,omitempty"`
	Status       *string `json:"status,omitempty"`
	Notes        *string `json:"notes,omitempty"`
}

// ConflictCheckRequest is the body for POST /api/v1/reservations/check-conflict.
type ConflictCheckRequest struct {
	TableID      string `json:"table_id"`
	Date         string `json:"date"`
	Time         string `json:"time"`          // HH:MM
	DurationMins int    `json:"duration_minutes"`
	ExcludeID    string `json:"exclude_id,omitempty"` // reservation being updated
}

// ConflictCheckResponse reports whether any conflicts exist.
type ConflictCheckResponse struct {
	HasConflict  bool          `json:"has_conflict"`
	Conflicts    []Reservation `json:"conflicts,omitempty"`
}

// CalendarDay groups reservations by date.
type CalendarDay struct {
	Date         string        `json:"date"`
	Count        int           `json:"count"`
	Reservations []Reservation `json:"reservations"`
}
