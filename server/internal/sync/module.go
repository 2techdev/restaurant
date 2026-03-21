package sync

import (
	"database/sql"
	"net/http"

	"github.com/gastrocore/server/internal/shared/config"
)

// Module is the sync module handling push/pull of change events and WebSocket notifications.
type Module struct {
	db    *sql.DB
	cfg   *config.Config
	store Store
	hub   *Hub
}

// NewModule creates a new sync module.
func NewModule(db *sql.DB, cfg *config.Config) *Module {
	return &Module{
		db:    db,
		cfg:   cfg,
		store: newStore(db),
		hub:   newHub(),
	}
}

// SyncHub returns the module's WebSocket hub so other modules can call
// NotifyTenant after performing mutations.
func (m *Module) SyncHub() *Hub { return m.hub }

// RegisterRoutes registers all sync routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// Primary sync endpoints
	mux.HandleFunc("POST /api/v1/sync/push", m.handlePush)
	mux.HandleFunc("GET /api/v1/sync/pull", m.handlePull)
	mux.HandleFunc("GET /api/v1/sync/status", m.handleStatus)

	// Device registration for sync
	mux.HandleFunc("POST /api/v1/devices/register", m.handleRegisterDevice)

	// Legacy aliases (upload/download/seed kept for compatibility)
	mux.HandleFunc("POST /api/v1/sync/upload", m.handleUpload)
	mux.HandleFunc("GET /api/v1/sync/download", m.handleDownload)
	mux.HandleFunc("POST /api/v1/sync/seed", m.handleSeed)

	// WebSocket for real-time notifications
	mux.HandleFunc("GET /ws/sync", m.hub.serveWS)
}
