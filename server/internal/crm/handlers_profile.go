package crm

import (
	"context"
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

// ── Extended profile (read-only aggregate view) ─────────────────────────────

// handleExtendedProfile returns the Customer record + a small set of derived
// roll-ups (recent orders, loyalty totals, matching segments, top product).
//
// GET /api/v1/crm/customers/{id}/profile-extended
func (m *Module) handleExtendedProfile(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	// 1. Base customer row.
	row := m.db.QueryRowContext(r.Context(), `
		SELECT `+customerColumns+`
		FROM customers
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID)
	cust, err := scanCustomer(row)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "not_found", "customer not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to load customer")
		return
	}

	out := ExtendedProfile{Customer: cust, SegmentIDs: []string{}}

	// 2. Loyalty totals (earn vs redeem) + 90-day order count via loyalty ledger.
	_ = m.db.QueryRowContext(r.Context(), `
		SELECT
		    COALESCE(SUM(CASE WHEN points > 0 THEN points ELSE 0 END), 0) AS earned,
		    COALESCE(SUM(CASE WHEN points < 0 THEN -points ELSE 0 END), 0) AS redeemed,
		    COUNT(*) FILTER (WHERE created_at > now() - interval '90 days') AS recent,
		    COUNT(*) AS total
		FROM loyalty_transactions
		WHERE customer_id = $1 AND tenant_id = $2
	`, id, tenantID).Scan(&out.LoyaltyEarned, &out.LoyaltyRedeemed, &out.RecentOrders, &out.OrderCount)

	// 3. Favorite product (resolved name).
	if cust.FavoriteProductID != nil && *cust.FavoriteProductID != "" {
		var fav FavoriteProductRef
		var catID sql.NullString
		if err := m.db.QueryRowContext(r.Context(), `
			SELECT id::TEXT, name, category_id::TEXT
			FROM products
			WHERE id::TEXT = $1 AND is_deleted = false
		`, *cust.FavoriteProductID).Scan(&fav.ProductID, &fav.Name, &catID); err == nil {
			if catID.Valid {
				fav.CategoryID = &catID.String
			}
			out.FavoriteProduct = &fav
		}
	}

	// 4. Segments the customer currently matches (small N — operator segments
	// are tens, not millions; we iterate and probe membership).
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, definition FROM customer_segments
		WHERE tenant_id = $1 AND is_deleted = false
	`, tenantID)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var sid string
			var defJSON []byte
			if err := rows.Scan(&sid, &defJSON); err != nil {
				continue
			}
			var def SegmentDefinition
			if err := json.Unmarshal(defJSON, &def); err != nil {
				continue
			}
			if m.customerMatchesSegment(r.Context(), tenantID, id, def) {
				out.SegmentIDs = append(out.SegmentIDs, sid)
			}
		}
	}

	response.JSON(w, http.StatusOK, out)
}

// customerMatchesSegment returns true when the given customer satisfies the
// segment definition right now.
func (m *Module) customerMatchesSegment(ctx context.Context, tenantID, customerID string, def SegmentDefinition) bool {
	where, args, err := buildSegmentWhere(def, 3)
	if err != nil {
		return false
	}
	query := `SELECT 1 FROM customers WHERE tenant_id = $1 AND id = $2 AND is_deleted = false`
	if where != "" {
		query += " AND " + where
	}
	allArgs := append([]any{tenantID, customerID}, args...)
	var hit int
	if err := m.db.QueryRowContext(ctx, query, allArgs...).Scan(&hit); err != nil {
		return false
	}
	return hit == 1
}

// ── Aggregate refresh job ───────────────────────────────────────────────────

// handleRefreshAggregates recomputes total_visits, total_spent_cents,
// avg_ticket_cents, first/last_visit_at, preferred_hour_bucket,
// favorite_product_id/favorite_category_id and preferred_payment_method for
// every customer in the current tenant by joining tickets (status='paid')
// either through loyalty_transactions.ticket_id or by case-insensitive
// match on tickets.customer_name (the same fallback the order-history
// handler already uses).
//
// POST /api/v1/crm/aggregates/refresh
func (m *Module) handleRefreshAggregates(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}
	start := time.Now()

	var total int
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT COUNT(*) FROM customers WHERE tenant_id = $1 AND is_deleted = false`,
		tenantID,
	).Scan(&total)

	// 1. Visit / spend / first+last visit / preferred hour roll-up.
	res, err := m.db.ExecContext(r.Context(), `
		WITH ct AS (
			SELECT c.id AS customer_id, t.id AS ticket_id, t.total::bigint AS total, t.opened_at
			FROM customers c
			JOIN tickets t ON t.tenant_id::TEXT = c.tenant_id
			              AND t.is_deleted = false
			              AND t.status IN ('paid','closed','completed','served')
			              AND (
			                  LOWER(COALESCE(t.customer_name,'')) = LOWER(c.name)
			                  OR t.id::TEXT IN (
			                      SELECT ticket_id FROM loyalty_transactions
			                      WHERE customer_id = c.id AND ticket_id IS NOT NULL
			                  )
			              )
			WHERE c.tenant_id = $1 AND c.is_deleted = false
		),
		agg AS (
			SELECT customer_id,
			       COUNT(DISTINCT ticket_id) AS visits,
			       COALESCE(SUM(total), 0)::bigint AS spend,
			       CASE WHEN COUNT(DISTINCT ticket_id) > 0
			            THEN (COALESCE(SUM(total), 0) / COUNT(DISTINCT ticket_id))::bigint
			            ELSE 0 END AS avg_ticket,
			       MIN(opened_at) AS first_v,
			       MAX(opened_at) AS last_v,
			       MODE() WITHIN GROUP (ORDER BY EXTRACT(HOUR FROM opened_at)::int) AS hour_bucket
			FROM ct
			GROUP BY customer_id
		)
		UPDATE customers c
		SET total_visits        = agg.visits,
		    total_spent_cents   = agg.spend,
		    avg_ticket_cents    = agg.avg_ticket,
		    first_visit_at      = COALESCE(c.first_visit_at, agg.first_v),
		    last_visit_at       = COALESCE(agg.last_v, c.last_visit_at),
		    preferred_hour_bucket = COALESCE(agg.hour_bucket::int, c.preferred_hour_bucket),
		    updated_at          = now()
		FROM agg
		WHERE c.id = agg.customer_id
	`, tenantID)
	updated := int64(0)
	if err != nil {
		slog.Warn("crm: aggregate refresh visits", "error", err)
	} else if res != nil {
		updated, _ = res.RowsAffected()
	}

	// 2. Favorite product + category (DISTINCT ON top-quantity).
	_, err = m.db.ExecContext(r.Context(), `
		WITH ct AS (
			SELECT c.id AS customer_id, t.id AS ticket_id
			FROM customers c
			JOIN tickets t ON t.tenant_id::TEXT = c.tenant_id
			              AND t.is_deleted = false
			              AND t.status IN ('paid','closed','completed','served')
			              AND (
			                  LOWER(COALESCE(t.customer_name,'')) = LOWER(c.name)
			                  OR t.id::TEXT IN (
			                      SELECT ticket_id FROM loyalty_transactions
			                      WHERE customer_id = c.id AND ticket_id IS NOT NULL
			                  )
			              )
			WHERE c.tenant_id = $1 AND c.is_deleted = false
		),
		prod_stats AS (
			SELECT ct.customer_id,
			       oi.product_id::TEXT AS product_id,
			       p.category_id::TEXT AS category_id,
			       SUM(oi.quantity) AS qty
			FROM ct
			JOIN order_items oi ON oi.ticket_id = ct.ticket_id AND oi.is_deleted = false
			JOIN products p ON p.id = oi.product_id AND p.is_deleted = false
			GROUP BY ct.customer_id, oi.product_id, p.category_id
		),
		top_prod AS (
			SELECT DISTINCT ON (customer_id) customer_id, product_id, category_id
			FROM prod_stats
			ORDER BY customer_id, qty DESC NULLS LAST
		)
		UPDATE customers c
		SET favorite_product_id  = top_prod.product_id,
		    favorite_category_id = top_prod.category_id,
		    updated_at = now()
		FROM top_prod
		WHERE c.id = top_prod.customer_id
	`, tenantID)
	if err != nil {
		slog.Warn("crm: aggregate refresh favorite product", "error", err)
	}

	// 3. Preferred payment method (mode across linked bills).
	_, err = m.db.ExecContext(r.Context(), `
		WITH ct AS (
			SELECT c.id AS customer_id, t.id AS ticket_id
			FROM customers c
			JOIN tickets t ON t.tenant_id::TEXT = c.tenant_id
			              AND t.is_deleted = false
			              AND t.status IN ('paid','closed','completed','served')
			              AND (
			                  LOWER(COALESCE(t.customer_name,'')) = LOWER(c.name)
			                  OR t.id::TEXT IN (
			                      SELECT ticket_id FROM loyalty_transactions
			                      WHERE customer_id = c.id AND ticket_id IS NOT NULL
			                  )
			              )
			WHERE c.tenant_id = $1 AND c.is_deleted = false
		),
		pay_stats AS (
			SELECT ct.customer_id, p.payment_method, COUNT(*) AS uses
			FROM ct
			JOIN bills b ON b.ticket_id = ct.ticket_id AND b.is_deleted = false
			JOIN payments p ON p.bill_id = b.id AND p.is_deleted = false
			GROUP BY ct.customer_id, p.payment_method
		),
		top_pay AS (
			SELECT DISTINCT ON (customer_id) customer_id, payment_method
			FROM pay_stats
			ORDER BY customer_id, uses DESC NULLS LAST
		)
		UPDATE customers c
		SET preferred_payment_method = top_pay.payment_method,
		    updated_at = now()
		FROM top_pay
		WHERE c.id = top_pay.customer_id
	`, tenantID)
	if err != nil {
		slog.Warn("crm: aggregate refresh preferred payment", "error", err)
	}

	response.JSON(w, http.StatusOK, RefreshAggregatesResponse{
		TenantID:         tenantID,
		CustomersTotal:   total,
		CustomersUpdated: int(updated),
		DurationMs:       time.Since(start).Milliseconds(),
	})
}
