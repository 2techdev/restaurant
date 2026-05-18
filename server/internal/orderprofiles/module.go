package orderprofiles

import (
	"context"
	"database/sql"
	"net/http"

	gosync "github.com/gastrocore/server/internal/sync"
)

// Module exposes the order-profile CRUD + active-profile compute endpoints
// and runs a once-a-minute background recompute that fans `profile_changed`
// WS events to POS terminals when the winning profile flips.
type Module struct {
	db    *sql.DB
	hub   *gosync.Hub
	sched *scheduler
}

func NewModule(db *sql.DB, hub *gosync.Hub) *Module {
	return &Module{db: db, hub: hub, sched: newScheduler()}
}

func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/order-profiles", m.handleList)
	mux.HandleFunc("GET /api/v1/order-profiles/active", m.handleActive)
	mux.HandleFunc("GET /api/v1/order-profiles/{id}", m.handleGet)
	mux.HandleFunc("POST /api/v1/order-profiles", m.handleCreate)
	mux.HandleFunc("PUT /api/v1/order-profiles/{id}", m.handleUpdate)
	mux.HandleFunc("DELETE /api/v1/order-profiles/{id}", m.handleDelete)
}

// Start launches the periodic recompute loop.  Wire from main() once the
// hub + db are ready; cancel ctx to stop on shutdown.
func (m *Module) Start(ctx context.Context) {
	m.startScheduler(ctx, 0)
}
