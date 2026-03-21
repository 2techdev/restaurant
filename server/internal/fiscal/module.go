// Package fiscal provides German KassenSichV (§146a AO) fiscal compliance
// via the Fiskaly SIGN DE middleware API v2.
//
// Feature is enabled when FISKALY_API_KEY and FISKALY_API_SECRET are set.
// When credentials are absent the module registers placeholder routes that
// return 503 Service Unavailable with an informative message.
//
// Routes:
//   POST /api/fiscal/tse/init            — Initialize TSE lifecycle
//   GET  /api/fiscal/tse/status          — Get TSE state
//   POST /api/fiscal/tse/self-test       — Trigger TSE self-test
//   POST /api/fiscal/transaction/sign    — Sign a transaction
//   GET  /api/fiscal/export/dsfinvk      — Trigger or poll DSFinV-K export
package fiscal

import (
	"encoding/json"
	"net/http"

	"github.com/gastrocore/server/internal/shared/config"
)

// Module is the fiscal compliance module.
type Module struct {
	h       *handler
	enabled bool
}

// NewModule creates the fiscal module.
//
// If Fiskaly credentials are absent the module is created in disabled mode:
// all routes return 503 with an explanatory body.
func NewModule(cfg *config.Config) *Module {
	if cfg.FiskalyAPIKey == "" || cfg.FiskalyAPISecret == "" {
		return &Module{enabled: false}
	}
	client := NewFiskalyClient(cfg.FiskalyAPIKey, cfg.FiskalyAPISecret)
	return &Module{
		h:       &handler{fiskaly: client},
		enabled: true,
	}
}

// RegisterRoutes registers all fiscal compliance routes on the given mux.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	if !m.enabled {
		disabled := m.disabledHandler()
		mux.HandleFunc("POST /api/fiscal/tse/init", disabled)
		mux.HandleFunc("GET /api/fiscal/tse/status", disabled)
		mux.HandleFunc("POST /api/fiscal/tse/self-test", disabled)
		mux.HandleFunc("POST /api/fiscal/transaction/sign", disabled)
		mux.HandleFunc("GET /api/fiscal/export/dsfinvk", disabled)
		return
	}

	mux.HandleFunc("POST /api/fiscal/tse/init", m.h.handleInitTSE)
	mux.HandleFunc("GET /api/fiscal/tse/status", m.h.handleTSEStatus)
	mux.HandleFunc("POST /api/fiscal/tse/self-test", m.h.handleSelfTest)
	mux.HandleFunc("POST /api/fiscal/transaction/sign", m.h.handleSignTransaction)
	mux.HandleFunc("GET /api/fiscal/export/dsfinvk", m.h.handleExportDSFinVK)
}

func (m *Module) disabledHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{
			"code":    "fiscal_disabled",
			"message": "German fiscal compliance is disabled — set FISKALY_API_KEY and FISKALY_API_SECRET to enable",
		})
	}
}
