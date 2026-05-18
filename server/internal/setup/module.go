// Package setup powers the operator-facing Setup Progress tracker pill in
// the backoffice. Returns a per-tenant checklist of onboarding steps so a
// fresh restaurant has a visible "you're 60% set up" indicator instead of
// nine half-filled pages with no signpost.
//
// Pure read endpoint — no migrations, all derivations live in this file.
// Adding a new step is "add a query + a Step row in handleProgress".
package setup

import (
	"database/sql"
	"net/http"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

type Module struct{ db *sql.DB }

func NewModule(db *sql.DB) *Module { return &Module{db: db} }

func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/admin/setup-progress", m.handleProgress)
}

// Step is a single checklist item rendered in the dropdown. Keys are
// stable; the backoffice maps them to i18n labels + nav hrefs client-side.
type Step struct {
	Key      string `json:"key"`
	Done     bool   `json:"done"`
	NavHref  string `json:"nav_href"`
	Required bool   `json:"required"`
}

type progressResponse struct {
	TenantID   string `json:"tenant_id"`
	Percent    int    `json:"percent"`
	Done       int    `json:"done"`
	Total      int    `json:"total"`
	Steps      []Step `json:"steps"`
	Completed  bool   `json:"completed"` // true when all required steps done
}

// boolOne runs a single COUNT(*) > 0 style query and returns true if it
// scans to a positive int. Errors collapse to false — better to under-mark
// progress than to crash the panel.
func (m *Module) boolOne(r *http.Request, q string, args ...any) bool {
	var n int
	err := m.db.QueryRowContext(r.Context(), q, args...).Scan(&n)
	return err == nil && n > 0
}

func (m *Module) handleProgress(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	steps := []Step{
		{
			Key:      "tenant_created",
			NavHref:  "/organization/info",
			Required: true,
			Done:     true, // by definition — this request reached us with a tenant
		},
		{
			Key:      "admin_user",
			NavHref:  "/users",
			Required: true,
			Done: m.boolOne(r,
				`SELECT COUNT(*) FROM admin_users WHERE organization_id = (SELECT organization_id FROM tenants WHERE id = $1)`,
				tenantID),
		},
		{
			Key:      "tenant_info",
			NavHref:  "/organization/info",
			Required: true,
			Done: m.boolOne(r,
				`SELECT COUNT(*) FROM tenants WHERE id = $1
				 AND COALESCE(address,'')   <> ''
				 AND COALESCE(phone,'')     <> ''`,
				tenantID),
		},
		{
			Key:      "opening_hours",
			NavHref:  "/restaurant-management/opening-hours",
			Required: false,
			Done: m.boolOne(r,
				`SELECT COUNT(*) FROM tenants WHERE id = $1
				 AND business_hours IS NOT NULL
				 AND jsonb_typeof(business_hours) = 'object'
				 AND business_hours <> '{}'::jsonb`,
				tenantID),
		},
		{
			Key:      "first_category",
			NavHref:  "/menu",
			Required: true,
			Done: m.boolOne(r,
				`SELECT COUNT(*) FROM categories WHERE tenant_id = $1 AND COALESCE(is_deleted,false)=false`,
				tenantID),
		},
		{
			Key:      "first_product",
			NavHref:  "/menu/products",
			Required: true,
			Done: m.boolOne(r,
				`SELECT COUNT(*) FROM products WHERE tenant_id = $1 AND COALESCE(is_deleted,false)=false`,
				tenantID),
		},
		{
			Key:      "tax_profile",
			NavHref:  "/restaurant-management/tax-profiles",
			Required: true,
			Done: m.boolOne(r,
				`SELECT COUNT(*) FROM tax_profiles WHERE tenant_id = $1`,
				tenantID),
		},
		{
			Key:      "receipt_template",
			NavHref:  "/restaurant-management/receipt-templates",
			Required: false,
			Done: m.boolOne(r,
				`SELECT COUNT(*) FROM receipt_templates WHERE tenant_id = $1`,
				tenantID),
		},
		{
			Key:      "payment_method",
			NavHref:  "/restaurant-management/payment-methods",
			Required: false,
			Done:     true, // payment_methods is a static seed; treat as done
		},
		{
			Key:      "pos_device",
			NavHref:  "/restaurant-management/devices",
			Required: false,
			Done: m.boolOne(r,
				`SELECT COUNT(*) FROM pos_devices WHERE tenant_id = $1 AND revoked_at IS NULL`,
				tenantID),
		},
		{
			Key:      "first_staff",
			NavHref:  "/team",
			Required: false,
			Done: m.boolOne(r,
				`SELECT COUNT(*) FROM app_users WHERE organization_id = (SELECT organization_id FROM tenants WHERE id = $1) AND is_active = true`,
				tenantID),
		},
	}

	total := len(steps)
	done := 0
	completed := true
	for _, s := range steps {
		if s.Done {
			done++
		} else if s.Required {
			completed = false
		}
	}
	percent := 0
	if total > 0 {
		percent = (done * 100) / total
	}

	response.JSON(w, http.StatusOK, progressResponse{
		TenantID:  tenantID,
		Percent:   percent,
		Done:      done,
		Total:     total,
		Steps:     steps,
		Completed: completed,
	})
}
