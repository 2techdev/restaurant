package feedback

import (
	"database/sql"
	"net/http"
)

// Module exposes customer-feedback CRUD endpoints for the backoffice.
type Module struct {
	db *sql.DB
}

// NewModule constructs a Feedback module bound to the given DB.
func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

// RegisterRoutes wires the feedback routes onto the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/feedback", m.handleList)
	mux.HandleFunc("POST /api/v1/feedback", m.handleCreate)
	mux.HandleFunc("PUT /api/v1/feedback/{id}/resolve", m.handleResolve)
}
