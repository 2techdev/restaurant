package reporting

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"html"
	"log/slog"
	"time"

	"github.com/gastrocore/server/internal/email"
	"github.com/lib/pq"
)

// alertRow mirrors the DB row.
type alertRow struct {
	ID              string
	TenantID        string
	Name            string
	AlertType       string
	ThresholdJSON   []byte
	Recipients      []string
	CooldownMinutes int
	Locale          string
	LastTriggeredAt sql.NullTime
}

// evaluateAlerts iterates every active threshold_alert and evaluates it.
// Suppresses re-firing inside its cooldown window. One row per evaluation
// is written to alert_logs.
func (m *Module) evaluateAlerts(ctx context.Context) {
	rows, err := m.db.QueryContext(ctx, `
		SELECT id, tenant_id, name, alert_type, threshold_jsonb,
		       recipients_emails, cooldown_minutes, locale, last_triggered_at
		  FROM threshold_alerts
		 WHERE is_active = TRUE
	`)
	if err != nil {
		slog.Error("alerts: list", "error", err)
		return
	}
	defer rows.Close()

	now := time.Now()
	for rows.Next() {
		var a alertRow
		if err := rows.Scan(
			&a.ID, &a.TenantID, &a.Name, &a.AlertType, &a.ThresholdJSON,
			pq.Array(&a.Recipients), &a.CooldownMinutes, &a.Locale, &a.LastTriggeredAt,
		); err != nil {
			continue
		}
		m.evaluateOne(ctx, a, now)
	}
}

func (m *Module) evaluateOne(ctx context.Context, a alertRow, now time.Time) {
	fire, value, msg, err := m.checkAlert(ctx, a)
	if err != nil {
		slog.Warn("alerts: check failed", "id", a.ID, "type", a.AlertType, "error", err)
		return
	}
	if !fire {
		return
	}
	// Cooldown gate.
	if a.LastTriggeredAt.Valid {
		nextAllowed := a.LastTriggeredAt.Time.Add(time.Duration(a.CooldownMinutes) * time.Minute)
		if now.Before(nextAllowed) {
			_, _ = m.db.ExecContext(ctx, `
				INSERT INTO alert_logs (alert_id, tenant_id, value, message, status)
				VALUES ($1, $2, $3, $4, 'suppressed_cooldown')
			`, a.ID, a.TenantID, value, msg)
			return
		}
	}

	// Deliver email.
	status := "fired"
	errMsg := ""
	if len(a.Recipients) > 0 {
		subj, body := renderAlertEmail(a, value, msg)
		if err := m.mailer.Send(email.Message{
			To: a.Recipients, Subject: subj, HTMLBody: body,
		}); err != nil {
			status = "send_failed"
			errMsg = err.Error()
			slog.Error("alerts: send", "id", a.ID, "error", err)
		}
	}

	_, _ = m.db.ExecContext(ctx, `
		INSERT INTO alert_logs (alert_id, tenant_id, value, message, sent_to, status, error_message)
		VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7,''))
	`, a.ID, a.TenantID, value, msg, pq.Array(a.Recipients), status, errMsg)

	if status == "fired" {
		_, _ = m.db.ExecContext(ctx, `
			UPDATE threshold_alerts
			   SET last_triggered_at = NOW(),
			       last_value        = $2,
			       updated_at        = NOW()
			 WHERE id = $1
		`, a.ID, value)
	}
}

// checkAlert dispatches by alert_type. Returns (fire, metricValue, message, err).
func (m *Module) checkAlert(ctx context.Context, a alertRow) (bool, float64, string, error) {
	var cfg map[string]any
	_ = json.Unmarshal(a.ThresholdJSON, &cfg)

	switch a.AlertType {
	case "sales_drop":
		percent := asFloat(cfg["percent"], 20)
		return m.checkSalesDrop(ctx, a.TenantID, percent)

	case "stockout_count":
		threshold := int(asFloat(cfg["count"], 5))
		return m.checkStockoutCount(ctx, a.TenantID, threshold)

	case "online_ack_delay":
		mins := int(asFloat(cfg["minutes"], 10))
		return m.checkOnlineAckDelay(ctx, a.TenantID, mins)

	case "revenue_target":
		amount := int64(asFloat(cfg["amount_cents"], 0))
		return m.checkRevenueTarget(ctx, a.TenantID, amount)

	case "refund_spike":
		count := int(asFloat(cfg["count_today"], 5))
		return m.checkRefundSpike(ctx, a.TenantID, count)

	case "failed_payments":
		count := int(asFloat(cfg["count_today"], 3))
		return m.checkFailedPayments(ctx, a.TenantID, count)
	}
	return false, 0, "", fmt.Errorf("unknown alert_type %s", a.AlertType)
}

func (m *Module) checkSalesDrop(ctx context.Context, tenantID string, percentThreshold float64) (bool, float64, string, error) {
	now := time.Now()
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	weekStart := todayStart.AddDate(0, 0, -7)

	var todayRev, weekRev int64
	err := m.db.QueryRowContext(ctx, `
		SELECT
			COALESCE(SUM(total) FILTER (WHERE created_at >= $2), 0),
			COALESCE(SUM(total) FILTER (WHERE created_at >= $3 AND created_at < $2), 0)
		FROM tickets
		WHERE tenant_id = $1 AND is_deleted = FALSE
		  AND status NOT IN ('void','open')
	`, tenantID, todayStart, weekStart).Scan(&todayRev, &weekRev)
	if err != nil {
		return false, 0, "", err
	}
	if weekRev == 0 {
		return false, 0, "", nil
	}
	avg := float64(weekRev) / 7.0
	if avg == 0 {
		return false, 0, "", nil
	}
	drop := (avg - float64(todayRev)) / avg * 100
	if drop >= percentThreshold {
		return true, drop, fmt.Sprintf("Bugünkü satış son 7 gün ortalamasının %%%.1f altında.", drop), nil
	}
	return false, drop, "", nil
}

func (m *Module) checkStockoutCount(ctx context.Context, tenantID string, threshold int) (bool, float64, string, error) {
	var count int64
	err := m.db.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM inventory_items
		 WHERE tenant_id = $1
		   AND COALESCE(quantity_on_hand, 0) <= 0
		   AND COALESCE(is_active, TRUE) = TRUE
	`, tenantID).Scan(&count)
	if err != nil {
		return false, 0, "", err
	}
	if count >= int64(threshold) {
		return true, float64(count), fmt.Sprintf("%d ürün stokta yok (eşik: %d).", count, threshold), nil
	}
	return false, float64(count), "", nil
}

func (m *Module) checkOnlineAckDelay(ctx context.Context, tenantID string, minutes int) (bool, float64, string, error) {
	var delayedCount int64
	err := m.db.QueryRowContext(ctx, `
		SELECT COUNT(*)
		  FROM tickets
		 WHERE tenant_id = $1 AND is_deleted = FALSE
		   AND order_type IN ('delivery','online','takeaway')
		   AND status = 'open'
		   AND created_at < NOW() - ($2 || ' minutes')::interval
	`, tenantID, fmt.Sprintf("%d", minutes)).Scan(&delayedCount)
	if err != nil {
		return false, 0, "", err
	}
	if delayedCount > 0 {
		return true, float64(delayedCount), fmt.Sprintf("%d online sipariş %d dakikadan fazla bekliyor.", delayedCount, minutes), nil
	}
	return false, 0, "", nil
}

func (m *Module) checkRevenueTarget(ctx context.Context, tenantID string, target int64) (bool, float64, string, error) {
	now := time.Now()
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	var rev int64
	err := m.db.QueryRowContext(ctx, `
		SELECT COALESCE(SUM(total), 0)
		  FROM tickets
		 WHERE tenant_id = $1 AND is_deleted = FALSE
		   AND status NOT IN ('void','open')
		   AND created_at >= $2
	`, tenantID, todayStart).Scan(&rev)
	if err != nil {
		return false, 0, "", err
	}
	// Fire only AFTER the day is mostly done (after 21:00) and target not met.
	if now.Hour() >= 21 && rev < target {
		return true, float64(rev), fmt.Sprintf("Günlük hedef %s, gerçekleşen %s.", formatCHF(target), formatCHF(rev)), nil
	}
	return false, float64(rev), "", nil
}

func (m *Module) checkRefundSpike(ctx context.Context, tenantID string, count int) (bool, float64, string, error) {
	now := time.Now()
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	var n int64
	err := m.db.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM tickets
		 WHERE tenant_id = $1 AND is_deleted = FALSE
		   AND status = 'refunded' AND created_at >= $2
	`, tenantID, todayStart).Scan(&n)
	if err != nil {
		return false, 0, "", err
	}
	if n >= int64(count) {
		return true, float64(n), fmt.Sprintf("Bugün %d iade kaydı var (eşik: %d).", n, count), nil
	}
	return false, float64(n), "", nil
}

func (m *Module) checkFailedPayments(ctx context.Context, tenantID string, count int) (bool, float64, string, error) {
	now := time.Now()
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	// `payments.status='failed'` is best-effort; if column missing, query returns 0.
	var n int64
	err := m.db.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM payments
		 WHERE tenant_id = $1 AND is_deleted = FALSE
		   AND status = 'failed' AND paid_at >= $2
	`, tenantID, todayStart).Scan(&n)
	if err != nil {
		return false, 0, "", nil // best-effort, swallow
	}
	if n >= int64(count) {
		return true, float64(n), fmt.Sprintf("Bugün %d ödeme başarısız oldu (eşik: %d).", n, count), nil
	}
	return false, float64(n), "", nil
}

// renderAlertEmail produces a small HTML body. Same branding style as digest
// but a single-message card.
func renderAlertEmail(a alertRow, value float64, msg string) (subject, body string) {
	subject = fmt.Sprintf("⚠ %s — GastroCore Uyarı", a.Name)
	body = fmt.Sprintf(`<!DOCTYPE html>
<html><body style="margin:0;padding:24px;background:#f6f7f9;font-family:-apple-system,sans-serif;color:#1a1a1a">
  <table role="presentation" width="600" cellspacing="0" cellpadding="0" border="0" style="max-width:600px;margin:0 auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.06)">
    <tr><td style="background:#b91c1c;color:#fff;padding:20px 28px">
      <div style="font-size:12px;letter-spacing:1px;opacity:0.85;text-transform:uppercase">GastroCore Alert</div>
      <h1 style="margin:4px 0 0;font-size:20px">%s</h1>
    </td></tr>
    <tr><td style="padding:24px 28px">
      <p style="margin:0 0 12px;font-size:15px">%s</p>
      <p style="margin:0;font-size:13px;color:#64748b">Eşik tipi: <b style="color:#0f172a">%s</b> · Ölçülen değer: <b style="color:#0f172a">%.2f</b></p>
    </td></tr>
    <tr><td style="background:#f8fafc;padding:12px 28px;font-size:12px;color:#94a3b8">GastroCore Otomatik Uyarı Sistemi</td></tr>
  </table>
</body></html>`,
		html_escape(a.Name), html_escape(msg), html_escape(a.AlertType), value)
	return
}

// asFloat coerces a JSON-decoded value to float; defaults if absent.
func asFloat(v any, def float64) float64 {
	switch x := v.(type) {
	case float64:
		return x
	case int:
		return float64(x)
	case int64:
		return float64(x)
	case string:
		var f float64
		_, err := fmt.Sscanf(x, "%f", &f)
		if err == nil {
			return f
		}
	}
	return def
}

// html_escape escapes the five XML special chars via stdlib so the small
// alert body is safe even with operator-supplied alert names.
func html_escape(s string) string { return html.EscapeString(s) }
