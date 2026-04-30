package promotions

import (
	"database/sql"
	"net/http"
)

// Module exposes /api/v1/discounts, /api/v1/campaigns and /api/v1/promotions/active.
type Module struct {
	db *sql.DB
}

func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// Discounts
	mux.HandleFunc("GET /api/v1/discounts", m.handleListDiscounts)
	mux.HandleFunc("POST /api/v1/discounts", m.handleCreateDiscount)
	mux.HandleFunc("GET /api/v1/discounts/{id}", m.handleGetDiscount)
	mux.HandleFunc("PUT /api/v1/discounts/{id}", m.handleUpdateDiscount)
	mux.HandleFunc("DELETE /api/v1/discounts/{id}", m.handleDeleteDiscount)

	// Campaigns
	mux.HandleFunc("GET /api/v1/campaigns", m.handleListCampaigns)
	mux.HandleFunc("POST /api/v1/campaigns", m.handleCreateCampaign)
	mux.HandleFunc("GET /api/v1/campaigns/{id}", m.handleGetCampaign)
	mux.HandleFunc("PUT /api/v1/campaigns/{id}", m.handleUpdateCampaign)
	mux.HandleFunc("DELETE /api/v1/campaigns/{id}", m.handleDeleteCampaign)

	// Currently-active promotions (POS picks these up)
	mux.HandleFunc("GET /api/v1/promotions/active", m.handleActive)
}
