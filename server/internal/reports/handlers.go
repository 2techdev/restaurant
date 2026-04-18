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
	m.writePeriodReport(w, r, tenantID, day, dayEnd, day.Format("2006-01-02"))
}

// handleWeeklyReport returns a sales summary for the last 7 days.
// GET /api/v1/reports/weekly
func (m *Module) handleWeeklyReport(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	now := time.Now()
	end := time.Date(now.Year(), now.Month(), now.Day(), 23, 59, 59, 0, now.Location())
	start := end.AddDate(0, 0, -6)
	start = time.Date(start.Year(), start.Month(), start.Day(), 0, 0, 0, 0, start.Location())
	m.writePeriodReport(w, r, tenantID, start, end, start.Format("2006-01-02"))
}

// handleMonthlyReport returns a sales summary for the current calendar month.
// GET /api/v1/reports/monthly
func (m *Module) handleMonthlyReport(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	now := time.Now()
	start := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
	end := time.Date(now.Year(), now.Month()+1, 1, 0, 0, 0, 0, now.Location()).Add(-time.Nanosecond)
	m.writePeriodReport(w, r, tenantID, start, end, start.Format("2006-01-02"))
}

// writePeriodReport runs the aggregations for a given date range and writes
// the response in the shape the backoffice Reports page expects (revenue /
// order_count / average_order / hourly_sales / by_payment / top_products /
// by_category). Each aggregation swallows its own error so a single empty
// table never takes down the whole report.
func (m *Module) writePeriodReport(w http.ResponseWriter, r *http.Request, tenantID string, start, end time.Time, dateLabel string) {
	var revenue, orderCount int64
	var averageOrder int64

	err := m.db.QueryRowContext(r.Context(), `
		SELECT
			COUNT(*) FILTER (WHERE status NOT IN ('void','open')),
			COALESCE(SUM(total) FILTER (WHERE status NOT IN ('void','open')), 0),
			COALESCE(AVG(total) FILTER (WHERE status NOT IN ('void','open'))::BIGINT, 0)
		FROM tickets
		WHERE tenant_id = $1 AND is_deleted = FALSE
		  AND created_at >= $2 AND created_at <= $3
	`, tenantID, start, end).Scan(&orderCount, &revenue, &averageOrder)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to aggregate period stats")
		return
	}

	hourlySales := m.loadHourlySales(r, tenantID, start, end)
	byPayment := m.loadPaymentBreakdown(r, tenantID, start, end)
	topProducts := m.loadTopProducts(r, tenantID, start, end, 10)
	byCategory := m.loadCategoryBreakdown(r, tenantID, start, end)

	response.JSON(w, http.StatusOK, map[string]any{
		"date":          dateLabel,
		"revenue":       revenue,
		"order_count":   orderCount,
		"average_order": averageOrder,
		"hourly_sales":  hourlySales,
		"by_payment":    byPayment,
		"top_products":  topProducts,
		"by_category":   byCategory,
	})
}

func (m *Module) loadHourlySales(r *http.Request, tenantID string, start, end time.Time) []map[string]any {
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT EXTRACT(HOUR FROM created_at)::INT AS hr,
		       COALESCE(SUM(total), 0)
		FROM tickets
		WHERE tenant_id = $1 AND is_deleted = FALSE
		  AND status NOT IN ('void','open')
		  AND created_at >= $2 AND created_at <= $3
		GROUP BY hr
		ORDER BY hr
	`, tenantID, start, end)
	if err != nil {
		return []map[string]any{}
	}
	defer rows.Close()
	out := make([]map[string]any, 0, 24)
	for rows.Next() {
		var hr int
		var total int64
		if rows.Scan(&hr, &total) == nil {
			out = append(out, map[string]any{"hour": hr, "total": total})
		}
	}
	return out
}

func (m *Module) loadPaymentBreakdown(r *http.Request, tenantID string, start, end time.Time) []map[string]any {
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT payment_method, COALESCE(SUM(amount), 0)
		FROM payments
		WHERE tenant_id = $1 AND is_deleted = FALSE
		  AND paid_at >= $2 AND paid_at <= $3
		GROUP BY payment_method
		ORDER BY 2 DESC
	`, tenantID, start, end)
	if err != nil {
		return []map[string]any{}
	}
	defer rows.Close()
	out := make([]map[string]any, 0)
	for rows.Next() {
		var method string
		var total int64
		if rows.Scan(&method, &total) == nil {
			out = append(out, map[string]any{"type": method, "total": total})
		}
	}
	return out
}

func (m *Module) loadTopProducts(r *http.Request, tenantID string, start, end time.Time, limit int) []map[string]any {
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT oi.product_name,
		       COALESCE(SUM(oi.quantity), 0) AS qty,
		       COALESCE(SUM(oi.subtotal), 0) AS total
		FROM order_items oi
		JOIN tickets t ON t.id = oi.ticket_id
		WHERE oi.tenant_id = $1
		  AND oi.is_deleted = FALSE
		  AND t.is_deleted = FALSE
		  AND t.status NOT IN ('void','open')
		  AND t.created_at >= $2 AND t.created_at <= $3
		GROUP BY oi.product_name
		ORDER BY total DESC
		LIMIT $4
	`, tenantID, start, end, limit)
	if err != nil {
		return []map[string]any{}
	}
	defer rows.Close()
	out := make([]map[string]any, 0)
	for rows.Next() {
		var name string
		var qty float64
		var total int64
		if rows.Scan(&name, &qty, &total) == nil {
			out = append(out, map[string]any{"name": name, "qty": qty, "total": total})
		}
	}
	return out
}

func (m *Module) loadCategoryBreakdown(r *http.Request, tenantID string, start, end time.Time) []map[string]any {
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT COALESCE(c.name, 'Diğer') AS name,
		       COALESCE(SUM(oi.subtotal), 0) AS total
		FROM order_items oi
		JOIN tickets t ON t.id = oi.ticket_id
		LEFT JOIN products p ON p.id = oi.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		WHERE oi.tenant_id = $1
		  AND oi.is_deleted = FALSE
		  AND t.is_deleted = FALSE
		  AND t.status NOT IN ('void','open')
		  AND t.created_at >= $2 AND t.created_at <= $3
		GROUP BY c.name
		ORDER BY total DESC
	`, tenantID, start, end)
	if err != nil {
		return []map[string]any{}
	}
	defer rows.Close()
	out := make([]map[string]any, 0)
	for rows.Next() {
		var name string
		var total int64
		if rows.Scan(&name, &total) == nil {
			out = append(out, map[string]any{"name": name, "total": total})
		}
	}
	return out
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
