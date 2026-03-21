package types

import "time"

// Money represents a monetary value in the smallest currency unit (cents).
type Money int64

// TenantID is a unique identifier for a tenant (restaurant group).
type TenantID = string

// BranchID is a unique identifier for a branch/location.
type BranchID = string

// DeviceID is a unique identifier for a registered POS device.
type DeviceID = string

// UserID is a unique identifier for a user (staff member).
type UserID = string

// PageRequest holds cursor-based pagination parameters.
type PageRequest struct {
	Cursor string `json:"cursor"`
	Limit  int    `json:"limit"`
}

// DefaultPageLimit is the default number of items per page.
const DefaultPageLimit = 50

// MaxPageLimit is the maximum number of items per page.
const MaxPageLimit = 200

// Clamp ensures the page limit is within valid bounds.
func (p *PageRequest) Clamp() {
	if p.Limit <= 0 {
		p.Limit = DefaultPageLimit
	}
	if p.Limit > MaxPageLimit {
		p.Limit = MaxPageLimit
	}
}

// APIError is the standard error response body.
type APIError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Details any    `json:"details,omitempty"`
}

// Timestamps are common timestamp fields shared across entities.
type Timestamps struct {
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// SoftDelete marks an entity as soft-deleted.
type SoftDelete struct {
	IsDeleted bool `json:"is_deleted"`
}

// SyncTracking holds sync-related fields for entities that sync to cloud.
type SyncTracking struct {
	SyncStatus int `json:"sync_status"` // 0=pending, 1=synced, 2=conflict
}
