// Package tables exposes a minimal CRUD API for restaurant_tables used by the
// backoffice /tables page. Tables returned here are scoped by tenant_id in
// JWT claims. Floor-plan positions are stored in pos_x/pos_y and the free-text
// `zone` label, added in migration 010.
package tables

import (
	"database/sql"
	"net/http"

	"github.com/gastrocore/server/internal/shared/config"
)

type Module struct {
	db  *sql.DB
	cfg *config.Config
}

func NewModule(db *sql.DB, cfg *config.Config) *Module {
	return &Module{db: db, cfg: cfg}
}

func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/tables", m.handleList)
	mux.HandleFunc("POST /api/v1/tables", m.handleCreate)
	mux.HandleFunc("PUT /api/v1/tables/{id}", m.handleUpdate)
	mux.HandleFunc("DELETE /api/v1/tables/{id}", m.handleDelete)
}
