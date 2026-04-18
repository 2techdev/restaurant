package printers

import (
	"database/sql"
	"net/http"
)

// Module handles per-store printer configuration.
type Module struct {
	db *sql.DB
}

// NewModule creates a new printers module.
func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

// RegisterRoutes registers the printer configuration routes. These endpoints
// are tenant-scoped — the caller must be authenticated via the brand/store
// JWT middleware upstream.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/stores/{id}/printers", m.handleListPrinters)
	mux.HandleFunc("PUT /api/v1/stores/{id}/printers", m.handleReplacePrinters)
	mux.HandleFunc("POST /api/v1/stores/{id}/printers/{pid}/test", m.handleTestPrint)
}
