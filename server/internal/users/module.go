package users

import (
	"database/sql"
	"net/http"

	"github.com/gastrocore/server/internal/shared/config"
)

// Module exposes a tenant-scoped /api/v1/users bridge over the app_users table.
// It lets the backoffice manage staff across all stores of a tenant from a
// single flat endpoint, without threading store_id through every call.
type Module struct {
	db  *sql.DB
	cfg *config.Config
}

func NewModule(db *sql.DB, cfg *config.Config) *Module {
	return &Module{db: db, cfg: cfg}
}

func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/users", m.handleList)
	mux.HandleFunc("POST /api/v1/users", m.handleCreate)
	mux.HandleFunc("PUT /api/v1/users/{id}", m.handleUpdate)
	mux.HandleFunc("DELETE /api/v1/users/{id}", m.handleDelete)
	mux.HandleFunc("POST /api/v1/users/{id}/pin", m.handleResetPin)
}
