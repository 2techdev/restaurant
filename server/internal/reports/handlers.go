package reports

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

// handleDailyReport returns a daily sales summary.
// GET /api/v1/reports/daily?date=YYYY-MM-DD
func (m *Module) handleDailyReport(w http.ResponseWriter, r *http.Request) {
	date := r.URL.Query().Get("date")
	if date == "" {
		date = time.Now().Format("2006-01-02")
	}

	var totalRevenue, totalOrders, totalTax, totalDiscounts int
	err := m.db.QueryRowContext(r.Context(), `
		SELECT
			COALESCE(SUM(total_amount), 0)    AS revenue,
			COUNT(*)                           AS orders,
			COALESCE(SUM(tax_amount), 0)       AS tax,
			COALESCE(SUM(discount_amount), 0)  AS discounts
		FROM tickets
		WHERE DATE(created_at) = $1
		  AND status NOT IN ('cancelled')
		  AND is_deleted = false
	`, date).Scan(&totalRevenue, &totalOrders, &totalTax, &totalDiscounts)
	if err != nil {
		slog.Error("reports: daily query", "error", err)
	}

	avgOrderValue := 0
	if totalOrders > 0 {
		avgOrderValue = totalRevenue / totalOrders
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"date":                date,
		"total_revenue":       totalRevenue,
		"total_orders":        totalOrders,
		"average_order_value": avgOrderValue,
		"total_tax":           totalTax,
		"total_discounts":     totalDiscounts,
		"net_revenue":         totalRevenue - totalTax,
		"orders_by_type":      map[string]int{},
		"payments_by_method":  map[string]int{},
		"hourly_breakdown":    []any{},
	})
}

// handleProductReport returns product performance data.
// GET /api/v1/reports/products?date_from=&date_to=&category_id=
func (m *Module) handleProductReport(w http.ResponseWriter, r *http.Request) {
	dateFrom := r.URL.Query().Get("date_from")
	dateTo := r.URL.Query().Get("date_to")
	if dateFrom == "" {
		dateFrom = time.Now().AddDate(0, 0, -30).Format("2006-01-02")
	}
	if dateTo == "" {
		dateTo = time.Now().Format("2006-01-02")
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT
			oi.product_id,
			oi.product_name,
			SUM(oi.quantity)              AS qty,
			SUM(oi.quantity * oi.unit_price) AS revenue
		FROM order_items oi
		JOIN tickets t ON t.id = oi.ticket_id
		WHERE DATE(t.created_at) BETWEEN $1 AND $2
		  AND t.status NOT IN ('cancelled')
		  AND t.is_deleted = false
		  AND oi.is_deleted = false
		GROUP BY oi.product_id, oi.product_name
		ORDER BY qty DESC
	`, dateFrom, dateTo)

	type productPerf struct {
		ProductID   string `json:"product_id"`
		ProductName string `json:"product_name"`
		Quantity    int    `json:"quantity"`
		Revenue     int    `json:"revenue"`
	}
	products := []productPerf{}
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var p productPerf
			if err := rows.Scan(&p.ProductID, &p.ProductName, &p.Quantity, &p.Revenue); err == nil {
				products = append(products, p)
			}
		}
	} else {
		slog.Error("reports: product query", "error", err)
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"date_from": dateFrom,
		"date_to":   dateTo,
		"products":  products,
	})
}

// handleStaffReport returns staff performance data.
// GET /api/v1/reports/staff?date_from=&date_to=
func (m *Module) handleStaffReport(w http.ResponseWriter, r *http.Request) {
	dateFrom := r.URL.Query().Get("date_from")
	dateTo := r.URL.Query().Get("date_to")
	if dateFrom == "" {
		dateFrom = time.Now().AddDate(0, 0, -30).Format("2006-01-02")
	}
	if dateTo == "" {
		dateTo = time.Now().Format("2006-01-02")
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT
			t.waiter_name,
			COUNT(*)               AS order_count,
			SUM(t.total_amount)    AS total_revenue
		FROM tickets t
		WHERE DATE(t.created_at) BETWEEN $1 AND $2
		  AND t.status NOT IN ('cancelled')
		  AND t.is_deleted = false
		  AND t.waiter_name IS NOT NULL
		GROUP BY t.waiter_name
		ORDER BY order_count DESC
	`, dateFrom, dateTo)

	type staffPerf struct {
		WaiterName   string `json:"waiter_name"`
		OrderCount   int    `json:"order_count"`
		TotalRevenue int    `json:"total_revenue"`
	}
	staff := []staffPerf{}
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var s staffPerf
			if err := rows.Scan(&s.WaiterName, &s.OrderCount, &s.TotalRevenue); err == nil {
				staff = append(staff, s)
			}
		}
	} else {
		slog.Error("reports: staff query", "error", err)
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"date_from": dateFrom,
		"date_to":   dateTo,
		"staff":     staff,
	})
}

// handleShiftReport returns shift summaries.
// GET /api/v1/reports/shifts?date_from=&date_to=
func (m *Module) handleShiftReport(w http.ResponseWriter, r *http.Request) {
	dateFrom := r.URL.Query().Get("date_from")
	dateTo := r.URL.Query().Get("date_to")
	if dateFrom == "" {
		dateFrom = time.Now().AddDate(0, 0, -7).Format("2006-01-02")
	}
	if dateTo == "" {
		dateTo = time.Now().Format("2006-01-02")
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"date_from": dateFrom,
		"date_to":   dateTo,
		"shifts":    []any{},
	})
}

// handleSalesReport returns aggregated sales data for export.
// GET /api/v1/reports/sales?from=YYYY-MM-DD&to=YYYY-MM-DD&group_by=day|week|month
func (m *Module) handleSalesReport(w http.ResponseWriter, r *http.Request) {
	from := r.URL.Query().Get("from")
	to := r.URL.Query().Get("to")
	groupBy := r.URL.Query().Get("group_by")

	if from == "" {
		from = time.Now().AddDate(0, 0, -30).Format("2006-01-02")
	}
	if to == "" {
		to = time.Now().Format("2006-01-02")
	}
	if groupBy == "" {
		groupBy = "day"
	}

	truncFn := "DATE(created_at)"
	switch groupBy {
	case "week":
		truncFn = "DATE_TRUNC('week', created_at)"
	case "month":
		truncFn = "DATE_TRUNC('month', created_at)"
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT
			`+truncFn+`             AS period,
			COUNT(*)                AS order_count,
			COALESCE(SUM(total_amount), 0)   AS revenue,
			COALESCE(SUM(tax_amount), 0)     AS tax,
			COALESCE(SUM(discount_amount), 0) AS discounts
		FROM tickets
		WHERE DATE(created_at) BETWEEN $1 AND $2
		  AND status NOT IN ('cancelled')
		  AND is_deleted = false
		GROUP BY period
		ORDER BY period ASC
	`, from, to)

	type salesPoint struct {
		Period     string `json:"period"`
		OrderCount int    `json:"order_count"`
		Revenue    int    `json:"revenue"`
		Tax        int    `json:"tax"`
		Discounts  int    `json:"discounts"`
	}
	points := []salesPoint{}
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var p salesPoint
			if err := rows.Scan(&p.Period, &p.OrderCount, &p.Revenue, &p.Tax, &p.Discounts); err == nil {
				points = append(points, p)
			}
		}
	} else {
		slog.Error("reports: sales query", "error", err)
	}

	// Sales by category.
	catRows, err := m.db.QueryContext(r.Context(), `
		SELECT
			p.category_id,
			c.name                        AS category_name,
			SUM(oi.quantity)              AS qty,
			SUM(oi.quantity * oi.unit_price) AS revenue
		FROM order_items oi
		JOIN tickets t  ON t.id  = oi.ticket_id
		JOIN products p ON p.id  = oi.product_id
		JOIN categories c ON c.id = p.category_id
		WHERE DATE(t.created_at) BETWEEN $1 AND $2
		  AND t.status NOT IN ('cancelled')
		  AND t.is_deleted = false
		  AND oi.is_deleted = false
		GROUP BY p.category_id, c.name
		ORDER BY revenue DESC
	`, from, to)

	type catSales struct {
		CategoryID   string `json:"category_id"`
		CategoryName string `json:"category_name"`
		Quantity     int    `json:"quantity"`
		Revenue      int    `json:"revenue"`
	}
	cats := []catSales{}
	if err == nil {
		defer catRows.Close()
		for catRows.Next() {
			var c catSales
			if err := catRows.Scan(&c.CategoryID, &c.CategoryName, &c.Quantity, &c.Revenue); err == nil {
				cats = append(cats, c)
			}
		}
	}

	// Payment method breakdown.
	pmRows, err := m.db.QueryContext(r.Context(), `
		SELECT
			payment_method,
			COUNT(*)             AS count,
			SUM(amount)          AS total
		FROM payments p
		JOIN tickets t ON t.id = p.ticket_id
		WHERE DATE(t.created_at) BETWEEN $1 AND $2
		  AND t.is_deleted = false
		GROUP BY payment_method
		ORDER BY total DESC
	`, from, to)

	type pmBreakdown struct {
		Method string `json:"method"`
		Count  int    `json:"count"`
		Total  int    `json:"total"`
	}
	payments := []pmBreakdown{}
	if err == nil {
		defer pmRows.Close()
		for pmRows.Next() {
			var pm pmBreakdown
			if err := pmRows.Scan(&pm.Method, &pm.Count, &pm.Total); err == nil {
				payments = append(payments, pm)
			}
		}
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"from":               from,
		"to":                 to,
		"group_by":           groupBy,
		"timeline":           points,
		"by_category":        cats,
		"by_payment_method":  payments,
	})
}

// handleMWSTReport returns Swiss MWST (VAT) breakdown by tax rate.
// GET /api/v1/reports/mwst?from=YYYY-MM-DD&to=YYYY-MM-DD
func (m *Module) handleMWSTReport(w http.ResponseWriter, r *http.Request) {
	from := r.URL.Query().Get("from")
	to := r.URL.Query().Get("to")

	if from == "" {
		from = time.Now().AddDate(0, -1, 0).Format("2006-01-02")
	}
	if to == "" {
		to = time.Now().Format("2006-01-02")
	}

	// Swiss MWST rates: 2.6% (accommodation), 3.8% (reduced/food), 8.1% (standard).
	// tax_group in products: 'standard' → 8.1%, 'reduced' → 3.8%, 'exempt' → 0%.
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT
			p.tax_group,
			SUM(oi.quantity * oi.unit_price)  AS gross_amount,
			CASE p.tax_group
				WHEN 'standard'     THEN 0.081
				WHEN 'reduced'      THEN 0.038
				WHEN 'accommodation'THEN 0.026
				ELSE 0.0
			END AS rate
		FROM order_items oi
		JOIN tickets t  ON t.id  = oi.ticket_id
		JOIN products p ON p.id  = oi.product_id
		WHERE DATE(t.created_at) BETWEEN $1 AND $2
		  AND t.status NOT IN ('cancelled')
		  AND t.is_deleted = false
		  AND oi.is_deleted = false
		GROUP BY p.tax_group
		ORDER BY rate DESC
	`, from, to)

	type mwstLine struct {
		TaxGroup    string  `json:"tax_group"`
		Rate        float64 `json:"rate"`
		GrossAmount int     `json:"gross_amount"`
		NetAmount   int     `json:"net_amount"`
		TaxAmount   int     `json:"tax_amount"`
	}
	lines := []mwstLine{}
	totalGross, totalTax := 0, 0
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var l mwstLine
			if err := rows.Scan(&l.TaxGroup, &l.GrossAmount, &l.Rate); err == nil {
				// net = gross / (1 + rate), tax = gross - net
				net := int(float64(l.GrossAmount) / (1.0 + l.Rate))
				l.NetAmount = net
				l.TaxAmount = l.GrossAmount - net
				totalGross += l.GrossAmount
				totalTax += l.TaxAmount
				lines = append(lines, l)
			}
		}
	} else {
		slog.Error("reports: mwst query", "error", err)
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"from":        from,
		"to":          to,
		"lines":       lines,
		"total_gross": totalGross,
		"total_tax":   totalTax,
		"total_net":   totalGross - totalTax,
	})
}
