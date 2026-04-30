package menu

import (
	"database/sql"
	"net/http"

	gosync "github.com/gastrocore/server/internal/sync"
)

// Module is the menu module handling product, category, and modifier CRUD
// as well as menu publishing (cloud-master sync — see menusync.go).
type Module struct {
	db  *sql.DB
	hub *gosync.Hub
}

// NewModule creates a new menu module with no real-time hub.
func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

// NewModuleWithHub returns a menu module wired to the sync WebSocket hub.
func NewModuleWithHub(db *sql.DB, hub *gosync.Hub) *Module {
	return &Module{db: db, hub: hub}
}

// RegisterRoutes registers all menu routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/menu/categories", m.handleListCategories)
	mux.HandleFunc("POST /api/v1/menu/categories", m.handleCreateCategory)
	mux.HandleFunc("PUT /api/v1/menu/categories/{id}", m.handleUpdateCategory)
	mux.HandleFunc("DELETE /api/v1/menu/categories/{id}", m.handleDeleteCategory)

	mux.HandleFunc("GET /api/v1/menu/products", m.handleListProducts)
	mux.HandleFunc("POST /api/v1/menu/products", m.handleCreateProduct)
	mux.HandleFunc("PUT /api/v1/menu/products/{id}", m.handleUpdateProduct)
	mux.HandleFunc("DELETE /api/v1/menu/products/{id}", m.handleDeleteProduct)

	mux.HandleFunc("GET /api/v1/menu/modifiers", m.handleListModifiers)

	// Cloud-master sync — version, snapshot, publish, api-key rotate.
	m.registerSyncRoutes(mux)

	// Device pairing — POS tablets exchange admin login → device-scoped key.
	m.registerDevicePairingRoutes(mux)
}
