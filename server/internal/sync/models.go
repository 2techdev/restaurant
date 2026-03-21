package sync

import (
	"encoding/json"
	"time"
)

// SyncEvent is a single change event pushed by a device.
type SyncEvent struct {
	ID         string          `json:"id"`
	TenantID   string          `json:"tenant_id"`
	DeviceID   string          `json:"device_id"`
	TableName  string          `json:"table_name"`
	RecordID   string          `json:"record_id"`
	Operation  string          `json:"operation"` // insert, update, delete
	Payload    json.RawMessage `json:"payload"`
	CreatedAt  time.Time       `json:"created_at"`
	ReceivedAt time.Time       `json:"received_at"`
}

// PushRequest is the body for POST /api/v1/sync/push.
type PushRequest struct {
	DeviceID string      `json:"device_id"`
	TenantID string      `json:"tenant_id"`
	Events   []SyncEvent `json:"events"`
}

// PushResponse is the response for POST /api/v1/sync/push.
type PushResponse struct {
	Accepted int      `json:"accepted"`
	Rejected int      `json:"rejected"`
	Errors   []string `json:"errors,omitempty"`
}

// PullResponse is the response for GET /api/v1/sync/pull.
type PullResponse struct {
	Events  []SyncEvent `json:"events"`
	Cursor  string      `json:"cursor"`
	HasMore bool        `json:"has_more"`
}

// SyncStatusResponse holds health info for a device.
type SyncStatusResponse struct {
	DeviceID       string     `json:"device_id"`
	TenantID       string     `json:"tenant_id"`
	LastPushAt     *time.Time `json:"last_push_at"`
	LastPullAt     *time.Time `json:"last_pull_at"`
	PendingForPull int        `json:"pending_for_pull"`
	Status         string     `json:"status"`
}

// WSNotification is the WebSocket message sent when new events arrive.
type WSNotification struct {
	Type     string `json:"type"`     // "new_events"
	TenantID string `json:"tenant_id"`
	Count    int    `json:"count"`
}
