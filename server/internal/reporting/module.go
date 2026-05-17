// Package reporting wires the email-driven side of the reports system:
// scheduled email reports (daily digest, weekly summary, monthly P&L) and
// business-metric threshold alerts.
//
// Three subsystems share the same module and db handle:
//
//   - data.go        — read-only aggregations used to assemble report bodies
//   - templates.go   — html/template rendering, 5-locale email body
//   - scheduler.go   — in-process ticker that finds due reports + alerts
//   - handlers_*.go  — tenant CRUD endpoints + "send now" manual trigger
//
// The package depends on internal/email for SMTP delivery; if SMTP is not
// configured, Send returns nil after logging and a report_logs row records
// `success` with a "dry-run" note so the UI still shows activity in dev.
package reporting

import (
	"context"
	"database/sql"
	"net/http"

	"github.com/gastrocore/server/internal/email"
	"github.com/gastrocore/server/internal/shared/config"
)

type Module struct {
	db     *sql.DB
	cfg    *config.Config
	mailer *email.Sender
}

func NewModule(db *sql.DB, cfg *config.Config) *Module {
	return &Module{
		db:     db,
		cfg:    cfg,
		mailer: email.NewSender(cfg),
	}
}

// RegisterRoutes wires REST endpoints onto the shared mux. Tenant scope is
// enforced inside each handler via middleware.GetTenantID().
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// scheduled_reports CRUD + manual trigger
	mux.HandleFunc("GET    /api/v1/reporting/scheduled", m.handleScheduledList)
	mux.HandleFunc("POST   /api/v1/reporting/scheduled", m.handleScheduledCreate)
	mux.HandleFunc("PUT    /api/v1/reporting/scheduled/{id}", m.handleScheduledUpdate)
	mux.HandleFunc("DELETE /api/v1/reporting/scheduled/{id}", m.handleScheduledDelete)
	mux.HandleFunc("POST   /api/v1/reporting/scheduled/{id}/send-now", m.handleScheduledSendNow)
	mux.HandleFunc("GET    /api/v1/reporting/logs", m.handleReportLogs)

	// threshold_alerts CRUD + test trigger
	mux.HandleFunc("GET    /api/v1/reporting/alerts", m.handleAlertList)
	mux.HandleFunc("POST   /api/v1/reporting/alerts", m.handleAlertCreate)
	mux.HandleFunc("PUT    /api/v1/reporting/alerts/{id}", m.handleAlertUpdate)
	mux.HandleFunc("DELETE /api/v1/reporting/alerts/{id}", m.handleAlertDelete)
	mux.HandleFunc("POST   /api/v1/reporting/alerts/{id}/test", m.handleAlertTest)
	mux.HandleFunc("GET    /api/v1/reporting/alerts/logs", m.handleAlertLogs)

	// Daily digest preview — useful before subscribing tenants.
	mux.HandleFunc("GET    /api/v1/reporting/digest/preview", m.handleDigestPreview)
}

// StartScheduler launches a goroutine that ticks every minute and runs:
//   - scheduled_reports whose next_run_at <= now()
//   - threshold_alerts evaluation (every 5 minutes)
//   - daily digest scan for tenants without an explicit daily_digest schedule
//     (every 5 minutes; sends once per tenant per day at/after 23:59 local)
//
// Stops when ctx is cancelled.
func (m *Module) StartScheduler(ctx context.Context) {
	go m.runScheduler(ctx)
}
