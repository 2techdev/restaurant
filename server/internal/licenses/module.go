package licenses

import (
	"database/sql"
	"net/http"

	"github.com/gastrocore/server/internal/shared/config"
)

// Module is the licenses module handling subscription validation,
// feature flags, and license token generation.
type Module struct {
	db  *sql.DB
	cfg *config.Config
}

// NewModule creates a new licenses module.
func NewModule(db *sql.DB, cfg *config.Config) *Module {
	return &Module{db: db, cfg: cfg}
}

// RegisterRoutes registers all license routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/licenses/validate", m.handleValidate)
	mux.HandleFunc("POST /api/v1/licenses/activate", m.handleActivate)
	mux.HandleFunc("GET /api/v1/licenses/features", m.handleGetFeatures)
}
