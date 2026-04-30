package crm

import (
	"context"
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"
)

// SyncNotifier is satisfied by the sync Hub for real-time device notifications.
type SyncNotifier interface {
	NotifyTenant(tenantID, senderDeviceID string, count int)
}

// SyncStore persists sync events so devices can pull CRM changes.
type SyncStore interface {
	SaveEvents(ctx context.Context, events []syncEvent) error
}

// syncEvent mirrors the sync package's SyncEvent for write-side use only.
type syncEvent struct {
	ID         string
	TenantID   string
	DeviceID   string
	TableName  string
	RecordID   string
	Operation  string
	Payload    json.RawMessage
	CreatedAt  time.Time
	ReceivedAt time.Time
}

// Module is the CRM module providing customer and loyalty endpoints.
type Module struct {
	db     *sql.DB
	hub    SyncNotifier
}

// NewModule creates a new CRM module.  hub may be nil (sync notifications disabled).
func NewModule(db *sql.DB, hub SyncNotifier) *Module {
	return &Module{db: db, hub: hub}
}

// RegisterRoutes mounts all CRM routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/crm/customers", m.handleListCustomers)
	mux.HandleFunc("POST /api/v1/crm/customers", m.handleCreateCustomer)
	mux.HandleFunc("GET /api/v1/crm/customers/{id}", m.handleGetCustomer)
	mux.HandleFunc("PUT /api/v1/crm/customers/{id}", m.handleUpdateCustomer)
	mux.HandleFunc("DELETE /api/v1/crm/customers/{id}", m.handleDeleteCustomer)
	mux.HandleFunc("POST /api/v1/crm/customers/{id}/loyalty", m.handleAddLoyalty)
	mux.HandleFunc("GET /api/v1/crm/customers/{id}/loyalty", m.handleListLoyalty)

	// Flatter aliases (added in 016) so backoffice clients can hit the
	// canonical resource path without the /crm/ prefix.
	mux.HandleFunc("GET /api/v1/customers", m.handleListCustomers)
	mux.HandleFunc("POST /api/v1/customers", m.handleCreateCustomer)
	mux.HandleFunc("GET /api/v1/customers/{id}", m.handleGetCustomer)
	mux.HandleFunc("PUT /api/v1/customers/{id}", m.handleUpdateCustomer)
	mux.HandleFunc("DELETE /api/v1/customers/{id}", m.handleDeleteCustomer)
	mux.HandleFunc("POST /api/v1/customers/{id}/loyalty", m.handleAddLoyalty)
	mux.HandleFunc("POST /api/v1/customers/{id}/loyalty/add", m.handleAddLoyalty)
	mux.HandleFunc("GET /api/v1/customers/{id}/loyalty", m.handleListLoyalty)
	mux.HandleFunc("GET /api/v1/customers/{id}/orders", m.handleCustomerOrders)
}

// publishSyncEvent writes a sync event to the sync_events table and notifies
// connected devices via WebSocket.
func (m *Module) publishSyncEvent(ctx context.Context, tenantID, tableName, recordID, operation string, payload any) {
	p, err := json.Marshal(payload)
	if err != nil {
		slog.Warn("crm: marshal sync payload", "error", err)
		return
	}

	now := time.Now().UTC()
	_, err = m.db.ExecContext(ctx, `
		INSERT INTO sync_events (id, tenant_id, device_id, table_name, record_id, operation, payload, created_at, received_at)
		VALUES (gen_random_uuid()::text, $1, 'server', $2, $3, $4, $5::jsonb, $6, $6)
		ON CONFLICT (id) DO NOTHING
	`, tenantID, tableName, recordID, operation, string(p), now)
	if err != nil {
		slog.Warn("crm: insert sync event", "error", err)
		return
	}

	if m.hub != nil {
		m.hub.NotifyTenant(tenantID, "server", 1)
	}
}
