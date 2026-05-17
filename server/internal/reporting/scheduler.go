package reporting

import (
	"context"
	"database/sql"
	"errors"
	"log/slog"
	"time"

	"github.com/gastrocore/server/internal/email"
	"github.com/lib/pq"
)

// runScheduler is the long-running loop. Every minute it:
//   1. picks up any scheduled_reports whose next_run_at <= now and dispatches
//   2. every 5 minutes, re-evaluates threshold_alerts
//
// The tick wakes once per minute regardless of clock skew — Go's time.Ticker
// drifts but for daily reports a few seconds doesn't matter.
func (m *Module) runScheduler(ctx context.Context) {
	slog.Info("reporting: scheduler started")

	// Backfill next_run_at on rows that don't have one (first boot after the
	// migration applied or after a row was inserted via SQL without setting it).
	m.backfillNextRunAt(ctx)

	tick := time.NewTicker(1 * time.Minute)
	defer tick.Stop()

	// Run alerts every 5 minutes to avoid hammering the DB.
	alertEvery := 5
	tickCount := 0

	for {
		select {
		case <-ctx.Done():
			slog.Info("reporting: scheduler stopping")
			return
		case <-tick.C:
			m.runDueReports(ctx)
			tickCount++
			if tickCount%alertEvery == 0 {
				m.evaluateAlerts(ctx)
			}
		}
	}
}

// runDueReports picks up due scheduled_reports rows and sends them. It
// updates next_run_at + last_sent_at + last_status atomically.
func (m *Module) runDueReports(ctx context.Context) {
	rows, err := m.db.QueryContext(ctx, `
		SELECT id, tenant_id, report_type, schedule_cron, recipients_emails,
		       format, filters_jsonb, locale
		FROM scheduled_reports
		WHERE is_active = TRUE
		  AND (next_run_at IS NULL OR next_run_at <= NOW())
		ORDER BY next_run_at ASC NULLS FIRST
		LIMIT 50
	`)
	if err != nil {
		slog.Error("reporting: list due", "error", err)
		return
	}
	due := make([]scheduledRow, 0)
	for rows.Next() {
		var r scheduledRow
		if err := rows.Scan(
			&r.ID, &r.TenantID, &r.ReportType, &r.ScheduleCron,
			pq.Array(&r.Recipients), &r.Format, &r.FiltersJSON, &r.Locale,
		); err == nil {
			due = append(due, r)
		}
	}
	rows.Close()

	for _, r := range due {
		m.sendScheduled(ctx, r, "scheduler")
	}
}

// scheduledRow is the in-memory shape of one scheduled_reports row.
type scheduledRow struct {
	ID           string
	TenantID     string
	ReportType   string
	ScheduleCron string
	Recipients   []string
	Format       string
	FiltersJSON  []byte
	Locale       string
}

// sendScheduled runs one scheduled report and persists the result. trigger
// is one of "scheduler" | "manual" | "digest_cron".
func (m *Module) sendScheduled(ctx context.Context, r scheduledRow, trigger string) {
	startedAt := time.Now()
	subj, body, err := m.renderReport(ctx, r)
	status := "success"
	errMsg := ""
	if err != nil {
		status = "failed"
		errMsg = err.Error()
		slog.Error("reporting: render", "id", r.ID, "type", r.ReportType, "error", err)
	}

	if status == "success" && len(r.Recipients) > 0 {
		if err := m.mailer.Send(email.Message{
			To:       r.Recipients,
			Subject:  subj,
			HTMLBody: body,
		}); err != nil {
			status = "failed"
			errMsg = err.Error()
			slog.Error("reporting: send", "id", r.ID, "error", err)
		}
	}

	// Compute next_run_at from cron.
	var nextRun *time.Time
	if expr, perr := parseCron(r.ScheduleCron); perr == nil {
		n := expr.Next(time.Now())
		if !n.IsZero() {
			nextRun = &n
		}
	}

	_, _ = m.db.ExecContext(ctx, `
		UPDATE scheduled_reports
		   SET last_sent_at = NOW(),
		       last_status  = $2,
		       next_run_at  = $3,
		       updated_at   = NOW()
		 WHERE id = $1
	`, r.ID, status, nextRun)

	_, _ = m.db.ExecContext(ctx, `
		INSERT INTO report_logs
			(scheduled_report_id, tenant_id, report_type, sent_to_emails,
			 sent_recipients_count, status, error_message, duration_ms,
			 trigger_source)
		VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7,''), $8, $9)
	`, r.ID, r.TenantID, r.ReportType, pq.Array(r.Recipients),
		len(r.Recipients), status, errMsg,
		int(time.Since(startedAt).Milliseconds()), trigger,
	)
}

// renderReport dispatches by report_type. For now only daily_digest is fully
// rendered — others fall back to the digest of the previous day. (V1 ships
// the most-used variant; the table values are kept for forward compat.)
func (m *Module) renderReport(ctx context.Context, r scheduledRow) (subject, body string, err error) {
	day := time.Now().AddDate(0, 0, -1) // "yesterday" for nightly digests
	d, err := m.LoadDigest(ctx, r.TenantID, day)
	if err != nil {
		return "", "", err
	}
	locale := r.Locale
	if locale == "" {
		locale = "tr"
	}
	return m.RenderDigest(d, locale)
}

// backfillNextRunAt populates next_run_at for any active scheduled_report
// that hasn't been scheduled yet. Called once at startup.
func (m *Module) backfillNextRunAt(ctx context.Context) {
	rows, err := m.db.QueryContext(ctx, `
		SELECT id, schedule_cron
		  FROM scheduled_reports
		 WHERE is_active = TRUE AND next_run_at IS NULL
	`)
	if err != nil {
		return
	}
	defer rows.Close()
	type pending struct {
		id   string
		cron string
	}
	work := make([]pending, 0)
	for rows.Next() {
		var p pending
		if rows.Scan(&p.id, &p.cron) == nil {
			work = append(work, p)
		}
	}
	for _, p := range work {
		expr, perr := parseCron(p.cron)
		if perr != nil {
			continue
		}
		n := expr.Next(time.Now())
		if n.IsZero() {
			continue
		}
		_, _ = m.db.ExecContext(ctx, `
			UPDATE scheduled_reports SET next_run_at = $2 WHERE id = $1
		`, p.id, n)
	}
}

// scheduledFromID fetches one row by id; used by manual "send now".
func (m *Module) scheduledFromID(ctx context.Context, id, tenantID string) (scheduledRow, error) {
	var r scheduledRow
	err := m.db.QueryRowContext(ctx, `
		SELECT id, tenant_id, report_type, schedule_cron, recipients_emails,
		       format, filters_jsonb, locale
		  FROM scheduled_reports
		 WHERE id = $1 AND tenant_id = $2
	`, id, tenantID).Scan(
		&r.ID, &r.TenantID, &r.ReportType, &r.ScheduleCron,
		pq.Array(&r.Recipients), &r.Format, &r.FiltersJSON, &r.Locale,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return r, errNotFound
	}
	return r, err
}

var errNotFound = errors.New("not found")
