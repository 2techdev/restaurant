package suppliers

import (
	"database/sql"
	"net/http"
)

// Module exposes /api/v1/suppliers CRUD endpoints (vendor master).
type Module struct {
	db *sql.DB
}

func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/suppliers", m.handleList)
	mux.HandleFunc("POST /api/v1/suppliers", m.handleCreate)
	mux.HandleFunc("GET /api/v1/suppliers/{id}", m.handleGet)
	mux.HandleFunc("PUT /api/v1/suppliers/{id}", m.handleUpdate)
	mux.HandleFunc("DELETE /api/v1/suppliers/{id}", m.handleDelete)
}
