package reports

import (
	"encoding/csv"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// handleTopSellers returns the top-selling products (by revenue) for a window.
// GET /api/v1/reports/top-sellers?from=YYYY-MM-DD&to=YYYY-MM-DD&limit=10
func (m *Module) handleTopSellers(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	q := r.URL.Query()
	from, to := parseDateRange(q.Get("from"), q.Get("to"))
	limit := 10
	if l := q.Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 && n <= 200 {
			limit = n
		}
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT oi.product_id::TEXT, oi.product_name,
		       COALESCE(SUM(oi.quantity), 0) AS qty,
		       COALESCE(SUM(oi.subtotal), 0) AS revenue,
		       COUNT(DISTINCT t.id) AS order_count
		FROM order_items oi
		JOIN tickets t ON t.id = oi.ticket_id
		WHERE oi.tenant_id = $1
		  AND oi.is_deleted = FALSE
		  AND t.is_deleted  = FALSE
		  AND t.status NOT IN ('void','open')
		  AND t.created_at >= $2 AND t.created_at <= $3
		GROUP BY oi.product_id, oi.product_name
		ORDER BY revenue DESC
		LIMIT $4
	`, tenantID, from, to, limit)
	if err != nil {
		slog.Error("reports: top-sellers", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to query top sellers")
		return
	}
	defer rows.Close()

	type Row struct {
		ProductID   string  `json:"product_id"`
		ProductName string  `json:"product_name"`
		Quantity    float64 `json:"quantity"`
		Revenue     int64   `json:"revenue"`
		OrderCount  int     `json:"order_count"`
	}
	out := make([]Row, 0, limit)
	for rows.Next() {
		var r Row
		if err := rows.Scan(&r.ProductID, &r.ProductName, &r.Quantity, &r.Revenue, &r.OrderCount); err == nil {
			out = append(out, r)
		}
	}
	response.JSON(w, http.StatusOK, map[string]any{
		"from":    from.Format("2006-01-02"),
		"to":      to.Format("2006-01-02"),
		"limit":   limit,
		"results": out,
	})
}

// handleHourlyReport returns orders / revenue grouped by hour-of-day for a single date.
// GET /api/v1/reports/hourly?date=YYYY-MM-DD
func (m *Module) handleHourlyReport(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}

	dateStr := r.URL.Query().Get("date")
	now := time.Now()
	day := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	if dateStr != "" {
		t, err := time.Parse("2006-01-02", dateStr)
		if err != nil {
			response.Error(w, http.StatusBadRequest, "INVALID_DATE", "date must be YYYY-MM-DD")
			return
		}
		day = t
	}
	dayEnd := day.Add(24*time.Hour - time.Nanosecond)

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT EXTRACT(HOUR FROM created_at)::INT AS hr,
		       COUNT(*) AS cnt,
		       COALESCE(SUM(total), 0) AS revenue
		FROM tickets
		WHERE tenant_id = $1
		  AND is_deleted = FALSE
		  AND status NOT IN ('void','open')
		  AND created_at >= $2 AND created_at <= $3
		GROUP BY hr
		ORDER BY hr
	`, tenantID, day, dayEnd)
	if err != nil {
		slog.Error("reports: hourly", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to query hourly report")
		return
	}
	defer rows.Close()

	type Bucket struct {
		Hour    int   `json:"hour"`
		Count   int   `json:"count"`
		Revenue int64 `json:"revenue"`
	}
	buckets := make([]Bucket, 0, 24)
	for rows.Next() {
		var b Bucket
		if rows.Scan(&b.Hour, &b.Count, &b.Revenue) == nil {
			buckets = append(buckets, b)
		}
	}
	response.JSON(w, http.StatusOK, map[string]any{
		"date":    day.Format("2006-01-02"),
		"buckets": buckets,
	})
}

// handleMWSTReport returns Swiss MWST (VAT) breakdown for a date window.
// Uses tickets.tax_amount aggregated by tax_profiles.tax_rate when available;
// falls back to a single bucket when tax profiles are not set up.
// GET /api/v1/reports/mwst?from=&to=
func (m *Module) handleMWSTReport(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	q := r.URL.Query()
	from, to := parseDateRange(q.Get("from"), q.Get("to"))

	// Aggregate totals at the order_items level so we can split by tax rate.
	// order_items.tax_amount is already in cents; we group by the rate that
	// was applied (looked up via tax_profiles based on the ticket's
	// order_type and the product's tax_group).
	//
	// Falls back to a single 'unspecified' bucket when no profile match.
	rows, err := m.db.QueryContext(r.Context(), `
		WITH base AS (
			SELECT t.id          AS ticket_id,
			       t.subtotal,
			       t.tax_amount,
			       t.discount_amount,
			       t.total,
			       COALESCE(t.channel, 'pos') AS order_type
			FROM tickets t
			WHERE t.tenant_id = $1
			  AND t.is_deleted = FALSE
			  AND t.status NOT IN ('void','open')
			  AND t.created_at >= $2 AND t.created_at <= $3
		),
		profile_match AS (
			SELECT
				b.ticket_id,
				b.subtotal,
				b.tax_amount,
				b.discount_amount,
				b.total,
				COALESCE(
					(SELECT tax_rate FROM tax_profiles
					 WHERE tenant_id = $1 AND order_type = b.order_type
					 ORDER BY is_default DESC LIMIT 1),
					NULL
				) AS tax_rate
			FROM base b
		)
		SELECT
			COALESCE(tax_rate::TEXT, 'unspecified') AS rate,
			COUNT(*)                                AS ticket_count,
			COALESCE(SUM(subtotal), 0)              AS net,
			COALESCE(SUM(tax_amount), 0)            AS tax,
			COALESCE(SUM(discount_amount), 0)       AS discount,
			COALESCE(SUM(total), 0)                 AS gross
		FROM profile_match
		GROUP BY tax_rate
		ORDER BY tax_rate NULLS LAST
	`, tenantID, from, to)
	if err != nil {
		slog.Error("reports: mwst", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to query MWST report")
		return
	}
	defer rows.Close()

	type Bucket struct {
		Rate        string `json:"rate"`
		TicketCount int    `json:"ticket_count"`
		Net         int64  `json:"net"`
		Tax         int64  `json:"tax"`
		Discount    int64  `json:"discount"`
		Gross       int64  `json:"gross"`
	}
	var totalNet, totalTax, totalDiscount, totalGross int64
	var totalTickets int
	buckets := make([]Bucket, 0)
	for rows.Next() {
		var b Bucket
		if err := rows.Scan(&b.Rate, &b.TicketCount, &b.Net, &b.Tax, &b.Discount, &b.Gross); err == nil {
			totalTickets += b.TicketCount
			totalNet += b.Net
			totalTax += b.Tax
			totalDiscount += b.Discount
			totalGross += b.Gross
			buckets = append(buckets, b)
		}
	}
	response.JSON(w, http.StatusOK, map[string]any{
		"from":    from.Format("2006-01-02"),
		"to":      to.Format("2006-01-02"),
		"buckets": buckets,
		"totals": map[string]any{
			"ticket_count": totalTickets,
			"net":          totalNet,
			"tax":          totalTax,
			"discount":     totalDiscount,
			"gross":        totalGross,
		},
	})
}

// handleExport streams a CSV file for either orders or menu (line items).
// GET /api/v1/reports/export?type=orders|menu&from=&to=
func (m *Module) handleExport(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	q := r.URL.Query()
	exportType := q.Get("type")
	if exportType == "" {
		exportType = "orders"
	}
	if exportType != "orders" && exportType != "menu" {
		response.Error(w, http.StatusBadRequest, "INVALID_TYPE", "type must be orders|menu")
		return
	}
	from, to := parseDateRange(q.Get("from"), q.Get("to"))

	filename := fmt.Sprintf("%s_%s_to_%s.csv", exportType,
		from.Format("20060102"), to.Format("20060102"))
	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="`+filename+`"`)

	cw := csv.NewWriter(w)
	defer cw.Flush()

	switch exportType {
	case "orders":
		_ = cw.Write([]string{
			"order_id", "created_at", "status", "channel",
			"subtotal_cents", "tax_cents", "discount_cents", "total_cents",
			"waiter_id",
		})
		rows, err := m.db.QueryContext(r.Context(), `
			SELECT id::TEXT, created_at, status, COALESCE(channel,''),
			       COALESCE(subtotal,0), COALESCE(tax_amount,0),
			       COALESCE(discount_amount,0), COALESCE(total,0),
			       COALESCE(waiter_id::TEXT,'')
			FROM tickets
			WHERE tenant_id = $1
			  AND is_deleted = FALSE
			  AND created_at >= $2 AND created_at <= $3
			ORDER BY created_at ASC
		`, tenantID, from, to)
		if err != nil {
			slog.Error("reports: export orders", "error", err)
			return
		}
		defer rows.Close()
		for rows.Next() {
			var id, status, channel, waiterID string
			var createdAt time.Time
			var subtotal, taxAmt, discountAmt, total int64
			if rows.Scan(&id, &createdAt, &status, &channel,
				&subtotal, &taxAmt, &discountAmt, &total, &waiterID) != nil {
				continue
			}
			_ = cw.Write([]string{
				id,
				createdAt.UTC().Format(time.RFC3339),
				status,
				channel,
				strconv.FormatInt(subtotal, 10),
				strconv.FormatInt(taxAmt, 10),
				strconv.FormatInt(discountAmt, 10),
				strconv.FormatInt(total, 10),
				waiterID,
			})
		}
	case "menu":
		_ = cw.Write([]string{
			"product_id", "product_name", "category",
			"sold_qty", "revenue_cents", "order_count",
		})
		rows, err := m.db.QueryContext(r.Context(), `
			SELECT oi.product_id::TEXT, oi.product_name,
			       COALESCE(c.name, '') AS category,
			       COALESCE(SUM(oi.quantity), 0) AS qty,
			       COALESCE(SUM(oi.subtotal), 0) AS revenue,
			       COUNT(DISTINCT t.id) AS orders
			FROM order_items oi
			JOIN tickets t ON t.id = oi.ticket_id
			LEFT JOIN products p ON p.id = oi.product_id::UUID
			LEFT JOIN categories c ON c.id = p.category_id
			WHERE oi.tenant_id = $1
			  AND oi.is_deleted = FALSE
			  AND t.is_deleted  = FALSE
			  AND t.status NOT IN ('void','open')
			  AND t.created_at >= $2 AND t.created_at <= $3
			GROUP BY oi.product_id, oi.product_name, c.name
			ORDER BY revenue DESC
		`, tenantID, from, to)
		if err != nil {
			slog.Error("reports: export menu", "error", err)
			return
		}
		defer rows.Close()
		for rows.Next() {
			var pid, name, cat string
			var qty float64
			var revenue int64
			var orderCount int
			if rows.Scan(&pid, &name, &cat, &qty, &revenue, &orderCount) != nil {
				continue
			}
			_ = cw.Write([]string{
				pid,
				name,
				cat,
				strconv.FormatFloat(qty, 'f', 2, 64),
				strconv.FormatInt(revenue, 10),
				strconv.Itoa(orderCount),
			})
		}
	}
}
