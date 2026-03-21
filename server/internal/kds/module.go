package kds

import (
	"database/sql"
	"net/http"
)

// Module is the KDS module providing kitchen display WebSocket and REST endpoints.
type Module struct {
	db  *sql.DB
	hub *Hub
}

// NewModule creates a new KDS module.  hub must already be running (go hub.Run()).
func NewModule(db *sql.DB, hub *Hub) *Module {
	return &Module{db: db, hub: hub}
}

// RegisterRoutes registers KDS routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// WebSocket for real-time kitchen notifications.
	mux.HandleFunc("GET /ws/kds", m.hub.serveWS)

	// REST endpoints for KDS devices.
	mux.HandleFunc("GET /api/v1/kds/tickets", m.handleListTickets)
	mux.HandleFunc("PUT /api/v1/kds/items/{id}/status", m.handleUpdateItemStatus)
	mux.HandleFunc("PUT /api/v1/kds/tickets/{id}/status", m.handleUpdateTicketStatus)
}
