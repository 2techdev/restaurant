package loyalty

import "net/http"

// RegisterGiftCardRoutes mounts /api/v1/giftcards/* on the same mux. Kept on
// the loyalty.Module so we share the *sql.DB handle and tenant resolver.
func (m *Module) RegisterGiftCardRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/giftcards", m.handleListGiftCards)
	mux.HandleFunc("POST /api/v1/giftcards", m.handleIssueGiftCard)
	mux.HandleFunc("POST /api/v1/giftcards/bulk", m.handleBulkIssueGiftCards)
	mux.HandleFunc("GET /api/v1/giftcards/{code}", m.handleGetGiftCard)
	mux.HandleFunc("POST /api/v1/giftcards/{code}/redeem", m.handleRedeemGiftCard)
	mux.HandleFunc("POST /api/v1/giftcards/{code}/refund", m.handleRefundGiftCard)
	mux.HandleFunc("PATCH /api/v1/giftcards/{code}/void", m.handleVoidGiftCard)
}
