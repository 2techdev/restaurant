package devices

import (
	"database/sql"
	"net/http"
)

// Module is the devices module handling device registry, capabilities,
// and health checking.
type Module struct {
	db *sql.DB
}

// NewModule creates a new devices module.
func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

// RegisterRoutes registers all device routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/devices", m.handleListDevices)
	mux.HandleFunc("POST /api/v1/devices", m.handleRegisterDevice)
	mux.HandleFunc("GET /api/v1/devices/{id}", m.handleGetDevice)
	mux.HandleFunc("PUT /api/v1/devices/{id}/capabilities", m.handleUpdateCapabilities)
	mux.HandleFunc("POST /api/v1/devices/{id}/heartbeat", m.handleHeartbeat)
}
