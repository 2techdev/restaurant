package inventory

import (
	"database/sql"
	"net/http"
)

// Module handles inventory item and stock-movement CRUD.
type Module struct {
	db *sql.DB
}

// NewModule creates a new inventory module.
func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

// RegisterRoutes registers all inventory routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// Stock items
	mux.HandleFunc("GET /api/v1/inventory/items", m.handleListItems)
	mux.HandleFunc("POST /api/v1/inventory/items", m.handleCreateItem)
	mux.HandleFunc("GET /api/v1/inventory/items/{id}", m.handleGetItem)
	mux.HandleFunc("PUT /api/v1/inventory/items/{id}", m.handleUpdateItem)
	mux.HandleFunc("DELETE /api/v1/inventory/items/{id}", m.handleDeleteItem)

	// Stock movements
	mux.HandleFunc("GET /api/v1/inventory/movements", m.handleListMovements)
	mux.HandleFunc("POST /api/v1/inventory/movements", m.handleCreateMovement)

	// Convenience aliases mounted at the root /api/v1/inventory path so
	// backoffice clients can hit a flatter URL surface.
	mux.HandleFunc("GET /api/v1/inventory", m.handleListItems)
	mux.HandleFunc("POST /api/v1/inventory", m.handleCreateItem)
	mux.HandleFunc("PUT /api/v1/inventory/{id}", m.handleUpdateItem)
	mux.HandleFunc("POST /api/v1/inventory/{id}/adjust", m.handleAdjust)
	mux.HandleFunc("GET /api/v1/inventory/low-stock", m.handleLowStock)
}
