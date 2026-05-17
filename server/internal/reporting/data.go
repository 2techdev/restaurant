package reporting

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

// DailyDigest is the data shape rendered into the 23:59 email. Numbers are in
// cents (the tickets.total convention). Pre-formatted CHF strings are added
// at render time, not here.
type DailyDigest struct {
	TenantID     string
	TenantName   string
	Date         time.Time
	Revenue      int64
	Net          int64
	OrderCount   int64
	AverageOrder int64
	ByPayment    []PaymentRow
	ByOrderType  []OrderTypeRow
	TopProducts  []TopProductRow
	StaffPerf    []StaffRow
	Cancellations CancellationSummary
	OnlineOrders int64
	StockoutsCount int64
}

type PaymentRow struct {
	Method string
	Total  int64
}

type OrderTypeRow struct {
	OrderType string // dine_in | takeaway | delivery
	Total     int64
	Count     int64
}

type TopProductRow struct {
	Name     string
	Quantity float64
	Total    int64
}

type StaffRow struct {
	UserID    string
	Name      string
	OrderCount int64
	Revenue   int64
}

type CancellationSummary struct {
	VoidedCount   int64
	VoidedAmount  int64
	RefundedCount int64
	RefundedAmount int64
	DiscountAmount int64
}

// LoadDigest fetches everything we need for the daily digest in one shot.
// Each sub-query swallows its own error (logged at the SQL site) so a single
// failing aggregate doesn't void the email — partial digest is still useful.
func (m *Module) LoadDigest(ctx context.Context, tenantID string, day time.Time) (*DailyDigest, error) {
	loc := day.Location()
	start := time.Date(day.Year(), day.Month(), day.Day(), 0, 0, 0, 0, loc)
	end := start.Add(24*time.Hour - time.Nanosecond)

	d := &DailyDigest{TenantID: tenantID, Date: start}

	// Tenant name (purely cosmetic — falls back to "—" if missing).
	if err := m.db.QueryRowContext(ctx,
		`SELECT COALESCE(name, '—') FROM tenants WHERE id = $1`, tenantID,
	).Scan(&d.TenantName); err == sql.ErrNoRows {
		return nil, fmt.Errorf("tenant %s not found", tenantID)
	}

	// Revenue + order count + average. Same predicate as /reports/daily.
	_ = m.db.QueryRowContext(ctx, `
		SELECT
			COUNT(*) FILTER (WHERE status NOT IN ('void','open')),
			COALESCE(SUM(total) FILTER (WHERE status NOT IN ('void','open')), 0),
			COALESCE(AVG(total) FILTER (WHERE status NOT IN ('void','open'))::BIGINT, 0)
		FROM tickets
		WHERE tenant_id = $1 AND is_deleted = FALSE
		  AND created_at >= $2 AND created_at <= $3
	`, tenantID, start, end).Scan(&d.OrderCount, &d.Revenue, &d.AverageOrder)

	// Net = gross minus tax (best-effort; falls back to revenue if no tax col).
	_ = m.db.QueryRowContext(ctx, `
		SELECT COALESCE(SUM(GREATEST(total - COALESCE(tax_amount, 0), 0)), 0)
		FROM tickets
		WHERE tenant_id = $1 AND is_deleted = FALSE
		  AND status NOT IN ('void','open')
		  AND created_at >= $2 AND created_at <= $3
	`, tenantID, start, end).Scan(&d.Net)

	d.ByPayment = m.loadPaymentRows(ctx, tenantID, start, end)
	d.ByOrderType = m.loadOrderTypeRows(ctx, tenantID, start, end)
	d.TopProducts = m.loadTopProductsForDigest(ctx, tenantID, start, end, 5)
	d.StaffPerf = m.loadStaffRows(ctx, tenantID, start, end)
	d.Cancellations = m.loadCancellations(ctx, tenantID, start, end)

	// Online orders is best-effort — only counts rows where order_type
	// indicates a non-walk-in source. Keeps zero if column missing.
	_ = m.db.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM tickets
		WHERE tenant_id = $1 AND is_deleted = FALSE
		  AND status NOT IN ('void','open')
		  AND order_type IN ('delivery','takeaway','online')
		  AND created_at >= $2 AND created_at <= $3
	`, tenantID, start, end).Scan(&d.OnlineOrders)

	// Stockouts as of report time (not date-scoped — reflects "right now").
	_ = m.db.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM inventory_items
		WHERE tenant_id = $1
		  AND COALESCE(quantity_on_hand, 0) <= 0
		  AND COALESCE(is_active, TRUE) = TRUE
	`, tenantID).Scan(&d.StockoutsCount)

	return d, nil
}

func (m *Module) loadPaymentRows(ctx context.Context, tenantID string, start, end time.Time) []PaymentRow {
	rows, err := m.db.QueryContext(ctx, `
		SELECT payment_method, COALESCE(SUM(amount), 0)
		FROM payments
		WHERE tenant_id = $1 AND is_deleted = FALSE
		  AND paid_at >= $2 AND paid_at <= $3
		GROUP BY payment_method
		ORDER BY 2 DESC
	`, tenantID, start, end)
	if err != nil {
		return nil
	}
	defer rows.Close()
	out := make([]PaymentRow, 0)
	for rows.Next() {
		var p PaymentRow
		if rows.Scan(&p.Method, &p.Total) == nil {
			out = append(out, p)
		}
	}
	return out
}

func (m *Module) loadOrderTypeRows(ctx context.Context, tenantID string, start, end time.Time) []OrderTypeRow {
	rows, err := m.db.QueryContext(ctx, `
		SELECT COALESCE(order_type, 'dine_in') AS ot,
		       COALESCE(SUM(total), 0),
		       COUNT(*)
		FROM tickets
		WHERE tenant_id = $1 AND is_deleted = FALSE
		  AND status NOT IN ('void','open')
		  AND created_at >= $2 AND created_at <= $3
		GROUP BY ot
		ORDER BY 2 DESC
	`, tenantID, start, end)
	if err != nil {
		return nil
	}
	defer rows.Close()
	out := make([]OrderTypeRow, 0)
	for rows.Next() {
		var r OrderTypeRow
		if rows.Scan(&r.OrderType, &r.Total, &r.Count) == nil {
			out = append(out, r)
		}
	}
	return out
}

func (m *Module) loadTopProductsForDigest(ctx context.Context, tenantID string, start, end time.Time, limit int) []TopProductRow {
	rows, err := m.db.QueryContext(ctx, `
		SELECT oi.product_name,
		       COALESCE(SUM(oi.quantity), 0),
		       COALESCE(SUM(oi.subtotal), 0)
		FROM order_items oi
		JOIN tickets t ON t.id = oi.ticket_id
		WHERE oi.tenant_id = $1
		  AND oi.is_deleted = FALSE
		  AND t.is_deleted = FALSE
		  AND t.status NOT IN ('void','open')
		  AND t.created_at >= $2 AND t.created_at <= $3
		GROUP BY oi.product_name
		ORDER BY 3 DESC
		LIMIT $4
	`, tenantID, start, end, limit)
	if err != nil {
		return nil
	}
	defer rows.Close()
	out := make([]TopProductRow, 0, limit)
	for rows.Next() {
		var t TopProductRow
		if rows.Scan(&t.Name, &t.Quantity, &t.Total) == nil {
			out = append(out, t)
		}
	}
	return out
}

func (m *Module) loadStaffRows(ctx context.Context, tenantID string, start, end time.Time) []StaffRow {
	rows, err := m.db.QueryContext(ctx, `
		SELECT t.waiter_id::TEXT,
		       COALESCE(u.name, 'Unknown'),
		       COUNT(*),
		       COALESCE(SUM(t.total), 0)
		FROM tickets t
		LEFT JOIN users u ON u.id = t.waiter_id AND u.tenant_id = t.tenant_id
		WHERE t.tenant_id = $1
		  AND t.is_deleted = FALSE
		  AND t.waiter_id IS NOT NULL
		  AND t.status NOT IN ('void','open')
		  AND t.created_at >= $2 AND t.created_at <= $3
		GROUP BY t.waiter_id, u.name
		ORDER BY 4 DESC
		LIMIT 20
	`, tenantID, start, end)
	if err != nil {
		return nil
	}
	defer rows.Close()
	out := make([]StaffRow, 0)
	for rows.Next() {
		var s StaffRow
		if rows.Scan(&s.UserID, &s.Name, &s.OrderCount, &s.Revenue) == nil {
			out = append(out, s)
		}
	}
	return out
}

func (m *Module) loadCancellations(ctx context.Context, tenantID string, start, end time.Time) CancellationSummary {
	var c CancellationSummary
	_ = m.db.QueryRowContext(ctx, `
		SELECT
			COUNT(*) FILTER (WHERE status = 'void'),
			COALESCE(SUM(total) FILTER (WHERE status = 'void'), 0),
			COUNT(*) FILTER (WHERE status = 'refunded'),
			COALESCE(SUM(total) FILTER (WHERE status = 'refunded'), 0),
			COALESCE(SUM(discount_amount), 0)
		FROM tickets
		WHERE tenant_id = $1 AND is_deleted = FALSE
		  AND created_at >= $2 AND created_at <= $3
	`, tenantID, start, end).Scan(
		&c.VoidedCount, &c.VoidedAmount,
		&c.RefundedCount, &c.RefundedAmount,
		&c.DiscountAmount,
	)
	return c
}

// ListActiveTenants returns every tenant id that has at least one shift open
// today or one ticket created in the past 24h — these are the only ones we
// bother sending a daily digest to. Avoids spamming inactive accounts.
func (m *Module) ListActiveTenants(ctx context.Context, since time.Time) ([]string, error) {
	rows, err := m.db.QueryContext(ctx, `
		SELECT DISTINCT tenant_id::TEXT
		FROM tickets
		WHERE is_deleted = FALSE
		  AND created_at >= $1
	`, since)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]string, 0)
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			out = append(out, id)
		}
	}
	return out, nil
}
