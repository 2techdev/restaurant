package dashboard

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

// handleStats returns today's dashboard statistics.
// GET /api/v1/dashboard/stats
func (m *Module) handleStats(w http.ResponseWriter, r *http.Request) {
	today := time.Now().Format("2006-01-02")

	// Total revenue + order count for today.
	var totalRevenue, orderCount int
	err := m.db.QueryRowContext(r.Context(), `
		SELECT
			COALESCE(SUM(total_amount), 0),
			COUNT(*)
		FROM tickets
		WHERE DATE(created_at) = $1
		  AND status NOT IN ('cancelled')
		  AND is_deleted = false
	`, today).Scan(&totalRevenue, &orderCount)
	if err != nil {
		slog.Error("dashboard: stats revenue query", "error", err)
	}

	// Average ticket value (avoid division by zero).
	avgTicket := 0
	if orderCount > 0 {
		avgTicket = totalRevenue / orderCount
	}

	// Active (open) orders.
	var activeOrders int
	_ = m.db.QueryRowContext(r.Context(), `
		SELECT COUNT(*) FROM tickets
		WHERE status IN ('open','items_added','sent_to_kitchen','preparing','partially_served')
		  AND is_deleted = false
	`).Scan(&activeOrders)

	// Tables currently occupied.
	var tablesOccupied int
	_ = m.db.QueryRowContext(r.Context(), `
		SELECT COUNT(DISTINCT table_number) FROM tickets
		WHERE status IN ('open','items_added','sent_to_kitchen','preparing','partially_served')
		  AND table_number IS NOT NULL
		  AND is_deleted = false
	`).Scan(&tablesOccupied)

	// Staff on shift (open shifts).
	var staffOnShift int
	_ = m.db.QueryRowContext(r.Context(), `
		SELECT COUNT(*) FROM shifts
		WHERE closed_at IS NULL
		  AND is_deleted = false
	`).Scan(&staffOnShift)

	// Top 5 selling items today.
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT
			oi.product_name,
			SUM(oi.quantity)        AS qty,
			SUM(oi.quantity * oi.unit_price) AS rev
		FROM order_items oi
		JOIN tickets t ON t.id = oi.ticket_id
		WHERE DATE(t.created_at) = $1
		  AND t.status NOT IN ('cancelled')
		  AND t.is_deleted = false
		  AND oi.is_deleted = false
		GROUP BY oi.product_name
		ORDER BY qty DESC
		LIMIT 5
	`, today)

	type topItem struct {
		Name     string `json:"name"`
		Quantity int    `json:"quantity"`
		Revenue  int    `json:"revenue"`
	}
	topItems := []topItem{}
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var item topItem
			if err := rows.Scan(&item.Name, &item.Quantity, &item.Revenue); err == nil {
				topItems = append(topItems, item)
			}
		}
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"date":            today,
		"total_revenue":   totalRevenue,
		"order_count":     orderCount,
		"avg_ticket":      avgTicket,
		"active_orders":   activeOrders,
		"tables_occupied": tablesOccupied,
		"open_orders":     activeOrders,
		"staff_on_shift":  staffOnShift,
		"top_items":       topItems,
	})
}

// handleRevenue returns revenue data over a time period for the chart.
// GET /api/v1/dashboard/revenue?period=7d|30d|90d
func (m *Module) handleRevenue(w http.ResponseWriter, r *http.Request) {
	period := r.URL.Query().Get("period")
	days := 7
	switch period {
	case "30d":
		days = 30
	case "90d":
		days = 90
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT
			DATE(created_at)           AS day,
			COALESCE(SUM(total_amount), 0) AS revenue,
			COUNT(*)                   AS orders
		FROM tickets
		WHERE created_at >= NOW() - ($1 || ' days')::INTERVAL
		  AND status NOT IN ('cancelled')
		  AND is_deleted = false
		GROUP BY day
		ORDER BY day ASC
	`, days)

	type dataPoint struct {
		Date    string `json:"date"`
		Revenue int    `json:"revenue"`
		Orders  int    `json:"orders"`
	}
	points := []dataPoint{}
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var dp dataPoint
			if err := rows.Scan(&dp.Date, &dp.Revenue, &dp.Orders); err == nil {
				points = append(points, dp)
			}
		}
	} else {
		slog.Error("dashboard: revenue query", "error", err)
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"period": period,
		"days":   days,
		"data":   points,
	})
}
