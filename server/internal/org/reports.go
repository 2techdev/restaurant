package org

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
	"github.com/lib/pq"
)

// parseRange reads from/to query params (RFC3339 or YYYY-MM-DD). Defaults
// to last 30 days when unspecified.
func parseRange(r *http.Request) (time.Time, time.Time, error) {
	now := time.Now().UTC()
	from := now.AddDate(0, 0, -30)
	to := now

	if s := r.URL.Query().Get("from"); s != "" {
		t, err := parseDateLoose(s)
		if err != nil {
			return time.Time{}, time.Time{}, err
		}
		from = t
	}
	if s := r.URL.Query().Get("to"); s != "" {
		t, err := parseDateLoose(s)
		if err != nil {
			return time.Time{}, time.Time{}, err
		}
		to = t
	}
	if from.After(to) {
		return time.Time{}, time.Time{}, errors.New("from must be <= to")
	}
	return from, to, nil
}

func parseDateLoose(s string) (time.Time, error) {
	for _, layout := range []string{time.RFC3339, "2006-01-02T15:04:05", "2006-01-02"} {
		if t, err := time.Parse(layout, s); err == nil {
			return t, nil
		}
	}
	return time.Time{}, errors.New("unparseable date: " + s)
}

// ─────────────────────────────────────────────────────────────
// GET /api/v1/org/{orgId}/reports/aggregate?from=&to=
// ─────────────────────────────────────────────────────────────
func (m *Module) handleAggregateReport(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	if _, ok := m.hqOnly(w, r, orgID); !ok {
		return
	}
	from, to, err := parseRange(r)
	if err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_RANGE", err.Error())
		return
	}

	tenantIDs, err := m.memberTenantIDs(r.Context(), orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list members")
		return
	}
	rep := AggregateReport{
		OrganizationID: orgID,
		From:           from,
		To:             to,
		RestaurantCnt:  len(tenantIDs),
		TopProducts:    []TopProduct{},
		Comparison:     []RestaurantKV{},
	}
	if len(tenantIDs) == 0 {
		response.JSON(w, http.StatusOK, rep)
		return
	}

	// Totals
	if err := m.db.QueryRowContext(r.Context(), `
		SELECT COALESCE(SUM(total),0)::bigint, COUNT(*)::bigint
		FROM tickets
		WHERE tenant_id = ANY($1::uuid[])
		  AND is_deleted = FALSE AND status = 'closed'
		  AND closed_at >= $2 AND closed_at <= $3
	`, pq.Array(tenantIDs), from, to).Scan(&rep.TotalRevenue, &rep.OrderCount); err != nil {
		slog.Error("org/aggregate: totals", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to compute totals")
		return
	}
	if rep.OrderCount > 0 {
		rep.AvgTicket = rep.TotalRevenue / rep.OrderCount
	}

	// Top products (across all member tenants)
	rep.TopProducts = m.queryTopProducts(r.Context(), tenantIDs, from, to, 10)

	// Per-restaurant comparison (revenue)
	cmpRows, err := m.db.QueryContext(r.Context(), `
		SELECT t.id::text, COALESCE(t.name,''),
		       COALESCE(SUM(tk.total),0)::bigint
		FROM tenants t
		LEFT JOIN tickets tk ON tk.tenant_id = t.id
		     AND tk.is_deleted = FALSE
		     AND tk.status = 'closed'
		     AND tk.closed_at >= $2 AND tk.closed_at <= $3
		WHERE t.id = ANY($1::uuid[])
		GROUP BY t.id, t.name
		ORDER BY SUM(tk.total) DESC NULLS LAST
	`, pq.Array(tenantIDs), from, to)
	if err == nil {
		defer cmpRows.Close()
		for cmpRows.Next() {
			var kv RestaurantKV
			if err := cmpRows.Scan(&kv.TenantID, &kv.Name, &kv.Value); err == nil {
				rep.Comparison = append(rep.Comparison, kv)
			}
		}
	} else {
		slog.Warn("org/aggregate: comparison", "error", err)
	}

	response.JSON(w, http.StatusOK, rep)
}

// queryTopProducts is shared by aggregate (across all) and by-restaurant (per tid).
func (m *Module) queryTopProducts(ctx context.Context, tenantIDs []string, from, to time.Time, limit int) []TopProduct {
	rows, err := m.db.QueryContext(ctx, `
		SELECT oi.product_id::text, oi.product_name,
		       SUM(oi.quantity)::float8 AS qty,
		       SUM(oi.subtotal)::bigint  AS rev
		FROM order_items oi
		JOIN tickets tk ON tk.id = oi.ticket_id
		WHERE oi.is_deleted = FALSE
		  AND tk.is_deleted = FALSE
		  AND tk.status = 'closed'
		  AND oi.tenant_id = ANY($1::uuid[])
		  AND tk.closed_at >= $2 AND tk.closed_at <= $3
		GROUP BY oi.product_id, oi.product_name
		ORDER BY qty DESC
		LIMIT $4
	`, pq.Array(tenantIDs), from, to, limit)
	if err != nil {
		slog.Warn("org/reports: top products", "error", err)
		return []TopProduct{}
	}
	defer rows.Close()
	out := []TopProduct{}
	for rows.Next() {
		var tp TopProduct
		if err := rows.Scan(&tp.ProductID, &tp.ProductName, &tp.Quantity, &tp.Revenue); err == nil {
			out = append(out, tp)
		}
	}
	return out
}

// ─────────────────────────────────────────────────────────────
// GET /api/v1/org/{orgId}/reports/by-restaurant?from=&to=
// ─────────────────────────────────────────────────────────────
func (m *Module) handleByRestaurantReport(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	if _, ok := m.hqOnly(w, r, orgID); !ok {
		return
	}
	from, to, err := parseRange(r)
	if err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_RANGE", err.Error())
		return
	}

	tenantIDs, err := m.memberTenantIDs(r.Context(), orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list members")
		return
	}
	out := ByRestaurantReport{
		OrganizationID: orgID,
		From:           from,
		To:             to,
		Restaurants:    []ByRestaurantRow{},
	}
	if len(tenantIDs) == 0 {
		response.JSON(w, http.StatusOK, out)
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT t.id::text, COALESCE(t.name,''),
		       COALESCE(SUM(tk.total),0)::bigint AS revenue,
		       COUNT(tk.id) FILTER (WHERE tk.id IS NOT NULL)::bigint AS orders
		FROM tenants t
		LEFT JOIN tickets tk ON tk.tenant_id = t.id
		     AND tk.is_deleted = FALSE
		     AND tk.status = 'closed'
		     AND tk.closed_at >= $2 AND tk.closed_at <= $3
		WHERE t.id = ANY($1::uuid[])
		GROUP BY t.id, t.name
		ORDER BY revenue DESC NULLS LAST
	`, pq.Array(tenantIDs), from, to)
	if err != nil {
		slog.Error("org/by-restaurant: rows", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to compute breakdown")
		return
	}
	defer rows.Close()

	rowsOut := []ByRestaurantRow{}
	for rows.Next() {
		var row ByRestaurantRow
		if err := rows.Scan(&row.TenantID, &row.Name, &row.Revenue, &row.OrderCount); err != nil {
			continue
		}
		if row.OrderCount > 0 {
			row.AvgTicket = row.Revenue / row.OrderCount
		}
		rowsOut = append(rowsOut, row)
	}

	// Top product per restaurant — single roundtrip per row, OK for small N.
	for i := range rowsOut {
		tp := m.queryTopProducts(r.Context(), []string{rowsOut[i].TenantID}, from, to, 1)
		if len(tp) > 0 {
			rowsOut[i].TopProduct = &tp[0]
		}
	}
	out.Restaurants = rowsOut

	response.JSON(w, http.StatusOK, out)
}

