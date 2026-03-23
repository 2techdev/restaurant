package reports

import (
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// handleDailyReport returns a daily sales summary.
// GET /api/v1/reports/daily?date=2026-03-23
func (m *Module) handleDailyReport(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}

	dateStr := r.URL.Query().Get("date")
	var day time.Time
	if dateStr != "" {
		var err error
		day, err = time.Parse("2006-01-02", dateStr)
		if err != nil {
			response.Error(w, http.StatusBadRequest, "INVALID_DATE", "date must be YYYY-MM-DD")
			return
		}
	} else {
		now := time.Now()
		day = time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	}
	dayEnd := day.Add(24*time.Hour - time.Nanosecond)

	// Core revenue aggregation
	var totalRevenue, totalTax, totalDiscounts, netRevenue int64
	var totalOrders int
	var avgOrderValue int64

	err := m.db.QueryRowContext(r.Context(), `
		SELECT
			COUNT(*) FILTER (WHERE status NOT IN ('void','open')),
			COALESCE(SUM(total) FILTER (WHERE status NOT IN ('void','open')), 0),
			COALESCE(AVG(total) FILTER (WHERE status NOT IN ('void','open'))::BIGINT, 0),
			COALESCE(SUM(tax_amount) FILTER (WHERE status NOT IN ('void','open')), 0),
			COALESCE(SUM(discount_amount) FILTER (WHERE status NOT IN ('void','open')), 0),
			COALESCE(SUM(total - discount_amount) FILTER (WHERE status NOT IN ('void','open')), 0)
		FROM tickets
		WHERE tenant_id = $1
		  AND is_deleted = FALSE
		  AND created_at >= $2
		  AND created_at <= $3
	`, tenantID, day, dayEnd).Scan(
		&totalOrders, &totalRevenue, &avgOrderValue,
		&totalTax, &totalDiscounts, &netRevenue,
	)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to aggregate daily stats")
		return
	}

	// Orders by type
	typeRows, err := m.db.QueryContext(r.Context(), `
		SELECT order_type, COUNT(*)
		FROM tickets
		WHERE tenant_id = $1 AND is_deleted = FALSE
		  AND status NOT IN ('void','open')
		  AND created_at >= $2 AND created_at <= $3
		GROUP BY order_type
	`, tenantID, day, dayEnd)
	ordersByType := map[string]int{}
	if err == nil {
		defer typeRows.Close()
		for typeRows.Next() {
			var ot string
			var cnt int
			if typeRows.Scan(&ot, &cnt) == nil {
				ordersByType[ot] = cnt
			}
		}
	}

	// Payments by method (from payments table)
	payRows, err := m.db.QueryContext(r.Context(), `
		SELECT payment_method, COUNT(*), COALESCE(SUM(amount), 0)
		FROM payments p
		JOIN tickets t ON t.id = p.ticket_id
		WHERE p.tenant_id = $1 AND p.is_deleted = FALSE
		  AND p.paid_at >= $2 AND p.paid_at <= $3
		GROUP BY payment_method
	`, tenantID, day, dayEnd)
	paymentsByMethod := map[string]int64{}
	if err == nil {
		defer payRows.Close()
		for payRows.Next() {
			var method string
			var cnt int
			var amount int64
			if payRows.Scan(&method, &cnt, &amount) == nil {
				_ = cnt
				paymentsByMethod[method] = amount
			}
		}
	}

	// Hourly breakdown (24 buckets)
	hourlyRows, err := m.db.QueryContext(r.Context(), `
		SELECT EXTRACT(HOUR FROM created_at)::INT, COALESCE(SUM(total), 0)
		FROM tickets
		WHERE tenant_id = $1 AND is_deleted = FALSE
		  AND status NOT IN ('void','open')
		  AND created_at >= $2 AND created_at <= $3
		GROUP BY EXTRACT(HOUR FROM created_at)
	`, tenantID, day, dayEnd)
	hourlyBreakdown := make([]int64, 24)
	if err == nil {
		defer hourlyRows.Close()
		for hourlyRows.Next() {
			var hour int
			var amount int64
			if hourlyRows.Scan(&hour, &amount) == nil && hour >= 0 && hour < 24 {
				hourlyBreakdown[hour] = amount
			}
		}
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"date":                day.Format("2006-01-02"),
		"total_revenue":       totalRevenue,
		"total_orders":        totalOrders,
		"average_order_value": avgOrderValue,
		"total_tax":           totalTax,
		"total_discounts":     totalDiscounts,
		"net_revenue":         netRevenue,
		"orders_by_type":      ordersByType,
		"payments_by_method":  paymentsByMethod,
		"hourly_breakdown":    hourlyBreakdown,
	})
}

// handleProductReport returns product performance data.
// GET /api/v1/reports/products?date_from=&date_to=&category_id=
func (m *Module) handleProductReport(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}

	q := r.URL.Query()
	dateFrom, dateTo := parseDateRange(q.Get("date_from"), q.Get("date_to"))
	categoryID := q.Get("category_id")

	// Build query with optional category filter
	catFilter := ""
	args := []any{tenantID, dateFrom, dateTo}
	if categoryID != "" {
		catFilter = " AND p.category_id = $4"
		args = append(args, categoryID)
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT
			oi.product_id,
			oi.product_name,
			COALESCE(p.category_id::TEXT, '') as category_id,
			COUNT(*) as order_count,
			SUM(oi.quantity) as total_quantity,
			SUM(oi.subtotal) as total_revenue,
			AVG(oi.unit_price)::BIGINT as avg_price
		FROM order_items oi
		LEFT JOIN products p ON p.id = oi.product_id::UUID
		JOIN tickets t ON t.id = oi.ticket_id
		WHERE oi.tenant_id = $1
		  AND oi.is_deleted = FALSE
		  AND t.is_deleted = FALSE
		  AND t.status NOT IN ('void','open')
		  AND t.created_at >= $2 AND t.created_at <= $3
		`+catFilter+`
		GROUP BY oi.product_id, oi.product_name, p.category_id
		ORDER BY total_revenue DESC
		LIMIT 100
	`, args...)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to aggregate product stats")
		return
	}
	defer rows.Close()

	type ProductPerf struct {
		ProductID   string  `json:"product_id"`
		ProductName string  `json:"product_name"`
		CategoryID  string  `json:"category_id"`
		OrderCount  int     `json:"order_count"`
		TotalQty    float64 `json:"total_quantity"`
		TotalRev    int64   `json:"total_revenue"`
		AvgPrice    int64   `json:"avg_price"`
	}

	products := make([]ProductPerf, 0)
	for rows.Next() {
		var p ProductPerf
		if err := rows.Scan(
			&p.ProductID, &p.ProductName, &p.CategoryID,
			&p.OrderCount, &p.TotalQty, &p.TotalRev, &p.AvgPrice,
		); err == nil {
			products = append(products, p)
		}
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"date_from": dateFrom.Format("2006-01-02"),
		"date_to":   dateTo.Format("2006-01-02"),
		"products":  products,
	})
}

// handleStaffReport returns staff performance data.
// GET /api/v1/reports/staff?date_from=&date_to=
func (m *Module) handleStaffReport(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}

	dateFrom, dateTo := parseDateRange(
		r.URL.Query().Get("date_from"),
		r.URL.Query().Get("date_to"),
	)

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT
			t.waiter_id::TEXT,
			COALESCE(u.name, 'Unknown') as waiter_name,
			COUNT(*) as order_count,
			COALESCE(SUM(t.total), 0) as total_revenue,
			COALESCE(AVG(t.total)::BIGINT, 0) as avg_order_value
		FROM tickets t
		LEFT JOIN users u ON u.id = t.waiter_id AND u.tenant_id = t.tenant_id
		WHERE t.tenant_id = $1
		  AND t.is_deleted = FALSE
		  AND t.waiter_id IS NOT NULL
		  AND t.status NOT IN ('void','open')
		  AND t.created_at >= $2 AND t.created_at <= $3
		GROUP BY t.waiter_id, u.name
		ORDER BY total_revenue DESC
	`, tenantID, dateFrom, dateTo)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to aggregate staff stats")
		return
	}
	defer rows.Close()

	type StaffPerf struct {
		WaiterID      string `json:"waiter_id"`
		WaiterName    string `json:"waiter_name"`
		OrderCount    int    `json:"order_count"`
		TotalRevenue  int64  `json:"total_revenue"`
		AvgOrderValue int64  `json:"avg_order_value"`
	}

	staff := make([]StaffPerf, 0)
	for rows.Next() {
		var s StaffPerf
		if err := rows.Scan(
			&s.WaiterID, &s.WaiterName,
			&s.OrderCount, &s.TotalRevenue, &s.AvgOrderValue,
		); err == nil {
			staff = append(staff, s)
		}
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"date_from": dateFrom.Format("2006-01-02"),
		"date_to":   dateTo.Format("2006-01-02"),
		"staff":     staff,
	})
}

// handleShiftReport returns shift summaries.
// GET /api/v1/reports/shifts?date_from=&date_to=&user_id=
func (m *Module) handleShiftReport(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}

	q := r.URL.Query()
	dateFrom, dateTo := parseDateRange(q.Get("date_from"), q.Get("date_to"))
	userID := q.Get("user_id")

	userFilter := ""
	args := []any{tenantID, dateFrom, dateTo}
	if userID != "" {
		userFilter = " AND s.user_id = $4"
		args = append(args, userID)
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT
			s.id,
			s.user_id::TEXT,
			COALESCE(u.name, 'Unknown') as user_name,
			s.opened_at,
			s.closed_at,
			COALESCE(s.opening_float, 0) as opening_float,
			COALESCE(s.closing_float, 0) as closing_float,
			COALESCE(s.total_cash, 0) as total_cash,
			COALESCE(s.total_card, 0) as total_card,
			COALESCE(s.total_other, 0) as total_other,
			COALESCE(s.order_count, 0) as order_count,
			s.notes
		FROM shifts s
		LEFT JOIN users u ON u.id = s.user_id AND u.tenant_id = s.tenant_id
		WHERE s.tenant_id = $1
		  AND s.opened_at >= $2 AND s.opened_at <= $3
		`+userFilter+`
		ORDER BY s.opened_at DESC
		LIMIT 100
	`, args...)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to query shifts")
		return
	}
	defer rows.Close()

	type ShiftSummary struct {
		ID           string     `json:"id"`
		UserID       string     `json:"user_id"`
		UserName     string     `json:"user_name"`
		OpenedAt     time.Time  `json:"opened_at"`
		ClosedAt     *time.Time `json:"closed_at"`
		OpeningFloat int64      `json:"opening_float"`
		ClosingFloat int64      `json:"closing_float"`
		TotalCash    int64      `json:"total_cash"`
		TotalCard    int64      `json:"total_card"`
		TotalOther   int64      `json:"total_other"`
		OrderCount   int        `json:"order_count"`
		Notes        *string    `json:"notes,omitempty"`
	}

	shifts := make([]ShiftSummary, 0)
	for rows.Next() {
		var s ShiftSummary
		if err := rows.Scan(
			&s.ID, &s.UserID, &s.UserName,
			&s.OpenedAt, &s.ClosedAt,
			&s.OpeningFloat, &s.ClosingFloat,
			&s.TotalCash, &s.TotalCard, &s.TotalOther,
			&s.OrderCount, &s.Notes,
		); err == nil {
			shifts = append(shifts, s)
		}
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"date_from": dateFrom.Format("2006-01-02"),
		"date_to":   dateTo.Format("2006-01-02"),
		"shifts":    shifts,
	})
}

// parseDateRange parses from/to date strings, defaulting to the last 7 days.
func parseDateRange(fromStr, toStr string) (from, to time.Time) {
	now := time.Now()
	to = time.Date(now.Year(), now.Month(), now.Day(), 23, 59, 59, 0, now.Location())
	from = to.AddDate(0, 0, -6)
	from = time.Date(from.Year(), from.Month(), from.Day(), 0, 0, 0, 0, from.Location())

	if fromStr != "" {
		if t, err := time.Parse("2006-01-02", fromStr); err == nil {
			from = t
		}
	}
	if toStr != "" {
		if t, err := time.Parse("2006-01-02", toStr); err == nil {
			to = time.Date(t.Year(), t.Month(), t.Day(), 23, 59, 59, 0, t.Location())
		}
	}
	return
}
