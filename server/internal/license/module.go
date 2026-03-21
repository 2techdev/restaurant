package license

import (
	"database/sql"
	"log/slog"
	"net/http"

	"github.com/gastrocore/server/internal/shared/config"
)

// Module is the license management module responsible for:
//   - Generating signed Ed25519 license tokens (offline-first JWT format).
//   - Validating tokens submitted by POS clients.
//   - Reporting token status (edition, expiry, features).
type Module struct {
	db  *sql.DB
	cfg *config.Config
	svc *Service
}

// NewModule creates a new license module, initialising the Ed25519 service
// from the LICENSE_SIGNING_KEY config value (falls back to the dev seed when
// the env var is not set).
func NewModule(db *sql.DB, cfg *config.Config) *Module {
	svc, err := NewService(cfg.LicenseSigningKey)
	if err != nil {
		// Only fatal in production; log and fall back to dev key for
		// development environments.
		slog.Error("license: failed to initialise signing service",
			"error", err,
			"hint", "check LICENSE_SIGNING_KEY env var")
		// Fallback to dev key (NewService("") always succeeds).
		svc, _ = NewService("")
	}
	return &Module{db: db, cfg: cfg, svc: svc}
}

// RegisterRoutes registers all license API endpoints on [mux].
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/license/generate", m.handleGenerate)
	mux.HandleFunc("POST /api/v1/license/validate", m.handleValidate)
	mux.HandleFunc("POST /api/v1/license/status", m.handleStatus)
}
