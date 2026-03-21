package menu

import (
	"database/sql"
	"net/http"
)

// Module is the menu module handling product, category, and modifier CRUD
// as well as menu publishing.
type Module struct {
	db *sql.DB
}

// NewModule creates a new menu module.
func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

// RegisterRoutes registers all menu routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// Categories
	mux.HandleFunc("GET /api/v1/menu/categories", m.handleListCategories)
	mux.HandleFunc("POST /api/v1/menu/categories", m.handleCreateCategory)
	mux.HandleFunc("PUT /api/v1/menu/categories/{id}", m.handleUpdateCategory)
	mux.HandleFunc("DELETE /api/v1/menu/categories/{id}", m.handleDeleteCategory)

	// Products
	mux.HandleFunc("GET /api/v1/menu/products", m.handleListProducts)
	mux.HandleFunc("POST /api/v1/menu/products", m.handleCreateProduct)
	mux.HandleFunc("PUT /api/v1/menu/products/{id}", m.handleUpdateProduct)
	mux.HandleFunc("DELETE /api/v1/menu/products/{id}", m.handleDeleteProduct)

	// Modifiers
	mux.HandleFunc("GET /api/v1/menu/modifiers", m.handleListModifiers)
}
