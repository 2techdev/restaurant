// Package loyalty owns the per-tenant tier system, point earn/redeem flow,
// and bonus campaign multipliers. The legacy `/api/v1/crm/customers/{id}/loyalty`
// adjust endpoint (in package crm) stays for backward compat; this module adds
// the higher-level business endpoints introduced in migration 036.
package loyalty

import (
	"database/sql"
	"net/http"
)

// Module exposes /api/v1/loyalty/* endpoints.
type Module struct {
	db *sql.DB
}

func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// Tier management — read for any authed caller; write for admin/manager.
	mux.HandleFunc("GET /api/v1/loyalty/tiers", m.handleListTiers)
	mux.HandleFunc("POST /api/v1/loyalty/tiers", m.handleCreateTier)
	mux.HandleFunc("PUT /api/v1/loyalty/tiers/{id}", m.handleUpdateTier)
	mux.HandleFunc("DELETE /api/v1/loyalty/tiers/{id}", m.handleDeleteTier)

	// Program settings — toggle + base rates.
	mux.HandleFunc("GET /api/v1/loyalty/settings", m.handleGetSettings)
	mux.HandleFunc("PUT /api/v1/loyalty/settings", m.handleUpdateSettings)

	// Customer account view — points + tier in one call.
	mux.HandleFunc("GET /api/v1/loyalty/account/{customer_id}", m.handleAccount)

	// Earn / Redeem — business-level operations that compute tier transitions.
	mux.HandleFunc("POST /api/v1/loyalty/earn", m.handleEarn)
	mux.HandleFunc("POST /api/v1/loyalty/redeem", m.handleRedeem)

	// Bonus campaigns — active multiplier window.
	mux.HandleFunc("GET /api/v1/loyalty/bonus-campaigns", m.handleListBonusCampaigns)
	mux.HandleFunc("POST /api/v1/loyalty/bonus-campaigns", m.handleCreateBonusCampaign)
	mux.HandleFunc("PUT /api/v1/loyalty/bonus-campaigns/{id}", m.handleUpdateBonusCampaign)
	mux.HandleFunc("DELETE /api/v1/loyalty/bonus-campaigns/{id}", m.handleDeleteBonusCampaign)
}
