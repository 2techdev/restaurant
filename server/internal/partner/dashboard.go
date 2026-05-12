package partner

import (
	"net/http"

	"github.com/gastrocore/server/internal/shared/response"
)

type dashboardResponse struct {
	BrandCount    int     `json:"brand_count"`
	StoreCount    int     `json:"store_count"`
	EditionCount  int     `json:"edition_count"`
	EmployeeCount int     `json:"employee_count"`
	ActiveStores  int     `json:"active_stores"`
	MRRChf        float64 `json:"mrr_chf"`
}

func (m *Module) handleDashboard(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, ""); !ok {
		return
	}
	var d dashboardResponse
	// All counts in one round-trip via separate queries — small dataset, fine.
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT COUNT(*) FROM organizations WHERE deleted_at IS NULL`).Scan(&d.BrandCount)
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT COUNT(*) FROM tenants WHERE COALESCE(is_deleted,false)=false`).Scan(&d.StoreCount)
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT COUNT(*) FROM editions WHERE is_active=true`).Scan(&d.EditionCount)
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT COUNT(*) FROM partner_employees WHERE status='active'`).Scan(&d.EmployeeCount)
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT COUNT(*) FROM tenants WHERE COALESCE(is_deleted,false)=false AND is_open=true`).Scan(&d.ActiveStores)
	// MRR = sum of current_edition.price_chf_month for every active store.
	_ = m.db.QueryRowContext(r.Context(), `
		SELECT COALESCE(SUM(e.price_chf_month),0)
		  FROM tenants t
		  JOIN editions e ON e.id = t.current_edition_id
		 WHERE COALESCE(t.is_deleted,false)=false`).Scan(&d.MRRChf)

	response.JSON(w, http.StatusOK, d)
}
