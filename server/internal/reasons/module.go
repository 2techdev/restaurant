// Package reasons exposes tenant-scoped CRUD over the void_reasons and
// discount_reasons dictionaries (migration 034). The POS pulls these on
// startup so cashiers always see a tenant-specific picker when voiding a
// line or applying a manual discount.
//
// Two route families share one module because the table shape is nearly
// identical (only discount carries max_discount_percent). Handlers fan out
// internally on the "kind" argument.
package reasons

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
	mux.HandleFunc("GET /api/v1/admin/reasons/void", m.handleList("void"))
	mux.HandleFunc("POST /api/v1/admin/reasons/void", m.handleCreate("void"))
	mux.HandleFunc("PUT /api/v1/admin/reasons/void/{id}", m.handleUpdate("void"))
	mux.HandleFunc("DELETE /api/v1/admin/reasons/void/{id}", m.handleDelete("void"))

	mux.HandleFunc("GET /api/v1/admin/reasons/discount", m.handleList("discount"))
	mux.HandleFunc("POST /api/v1/admin/reasons/discount", m.handleCreate("discount"))
	mux.HandleFunc("PUT /api/v1/admin/reasons/discount/{id}", m.handleUpdate("discount"))
	mux.HandleFunc("DELETE /api/v1/admin/reasons/discount/{id}", m.handleDelete("discount"))
}
