package stations

import (
	"database/sql"
	"net/http"

	"github.com/gastrocore/server/internal/shared/config"
)

// Module handles kitchen/bar station CRUD.
type Module struct {
	db  *sql.DB
	cfg *config.Config
}

func NewModule(db *sql.DB, cfg *config.Config) *Module {
	return &Module{db: db, cfg: cfg}
}

func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/stations", m.handleList)
	mux.HandleFunc("POST /api/v1/stations", m.handleCreate)
	mux.HandleFunc("PUT /api/v1/stations/{id}", m.handleUpdate)
	mux.HandleFunc("DELETE /api/v1/stations/{id}", m.handleDelete)
}
