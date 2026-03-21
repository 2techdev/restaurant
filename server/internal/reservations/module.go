package reservations

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

// Module is the reservations module for booking management.
type Module struct {
	db  *sql.DB
	hub SyncNotifier
}

// NewModule creates a new reservations module.  hub may be nil.
func NewModule(db *sql.DB, hub SyncNotifier) *Module {
	return &Module{db: db, hub: hub}
}

// RegisterRoutes mounts all reservation routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/reservations", m.handleListReservations)
	mux.HandleFunc("POST /api/v1/reservations", m.handleCreateReservation)
	mux.HandleFunc("GET /api/v1/reservations/calendar", m.handleCalendar)
	mux.HandleFunc("POST /api/v1/reservations/check-conflict", m.handleCheckConflict)
	mux.HandleFunc("GET /api/v1/reservations/{id}", m.handleGetReservation)
	mux.HandleFunc("PUT /api/v1/reservations/{id}", m.handleUpdateReservation)
	mux.HandleFunc("DELETE /api/v1/reservations/{id}", m.handleDeleteReservation)
}

// publishSyncEvent writes a sync event to the sync_events table and notifies
// connected devices via WebSocket.
func (m *Module) publishSyncEvent(ctx context.Context, tenantID, tableName, recordID, operation string, payload any) {
	p, err := json.Marshal(payload)
	if err != nil {
		slog.Warn("reservations: marshal sync payload", "error", err)
		return
	}

	now := time.Now().UTC()
	_, err = m.db.ExecContext(ctx, `
		INSERT INTO sync_events (id, tenant_id, device_id, table_name, record_id, operation, payload, created_at, received_at)
		VALUES (gen_random_uuid()::text, $1, 'server', $2, $3, $4, $5::jsonb, $6, $6)
		ON CONFLICT (id) DO NOTHING
	`, tenantID, tableName, recordID, operation, string(p), now)
	if err != nil {
		slog.Warn("reservations: insert sync event", "error", err)
		return
	}

	if m.hub != nil {
		m.hub.NotifyTenant(tenantID, "server", 1)
	}
}
