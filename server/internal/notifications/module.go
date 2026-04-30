package notifications

import (
	"database/sql"
	"net/http"
)

// Module exposes /api/v1/notifications/prefs — a per-user JSON preference
// object backed by the notification_preferences table (migration 016).
type Module struct {
	db *sql.DB
}

func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/notifications/prefs", m.handleGet)
	mux.HandleFunc("PUT /api/v1/notifications/prefs", m.handlePut)
}
