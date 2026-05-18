package tasks

import (
	"context"
	"database/sql"
	"log/slog"
	"net/http"
	"sync"
	"time"
)

// Module exposes /api/v1/tasks/... and owns a background cron goroutine.
type Module struct {
	db *sql.DB

	cronOnce sync.Once
	cronStop chan struct{}
}

// NewModule returns a tasks module with a database handle. Call
// [Module.RegisterRoutes] to attach HTTP handlers and [Module.StartCron]
// to begin the background scheduler.
func NewModule(db *sql.DB) *Module {
	return &Module{
		db:       db,
		cronStop: make(chan struct{}),
	}
}

// RegisterRoutes mounts the public REST surface for the HACCP module.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	// Templates — admin CRUD
	mux.HandleFunc("GET /api/v1/tasks/templates", m.handleListTemplates)
	mux.HandleFunc("POST /api/v1/tasks/templates", m.handleCreateTemplate)
	mux.HandleFunc("GET /api/v1/tasks/templates/{id}", m.handleGetTemplate)
	mux.HandleFunc("PUT /api/v1/tasks/templates/{id}", m.handleUpdateTemplate)
	mux.HandleFunc("DELETE /api/v1/tasks/templates/{id}", m.handleDeleteTemplate)

	// Instances — operator-facing
	mux.HandleFunc("GET /api/v1/tasks/today", m.handleToday)
	mux.HandleFunc("GET /api/v1/tasks/instances", m.handleListInstances)
	mux.HandleFunc("GET /api/v1/tasks/instances/{id}", m.handleGetInstance)
	mux.HandleFunc("POST /api/v1/tasks/instances/{id}/complete", m.handleComplete)
	mux.HandleFunc("POST /api/v1/tasks/instances/{id}/correction", m.handleCorrection)

	// Alerts + reports
	mux.HandleFunc("GET /api/v1/tasks/alerts", m.handleListAlerts)
	mux.HandleFunc("POST /api/v1/tasks/alerts/{id}/resolve", m.handleResolveAlert)
	mux.HandleFunc("GET /api/v1/tasks/reports/summary", m.handleReportSummary)

	// Manual cron trigger — handy for tests and for operators who want
	// to materialise instances immediately after creating a template.
	mux.HandleFunc("POST /api/v1/tasks/cron/run", m.handleCronTrigger)
}

// StartCron launches the background scheduler. Safe to call multiple
// times — second and later invocations are no-ops.
func (m *Module) StartCron(ctx context.Context) {
	m.cronOnce.Do(func() {
		go m.cronLoop(ctx)
	})
}

// Stop signals the cron goroutine to exit. Used by graceful-shutdown
// hooks in the main binary.
func (m *Module) Stop() {
	select {
	case <-m.cronStop:
		// already closed
	default:
		close(m.cronStop)
	}
}

// cronLoop ticks every five minutes. It evaluates every active template
// in the database, materialises any due instances, and runs the
// late-detector for older pending instances.
func (m *Module) cronLoop(ctx context.Context) {
	// Run once at boot so a fresh deploy doesn't wait five minutes for
	// the first instance to appear.
	m.runCronTick(ctx, time.Now().UTC())

	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-m.cronStop:
			return
		case t := <-ticker.C:
			m.runCronTick(ctx, t.UTC())
		}
	}
}

// runCronTick is the per-tick body, broken out for tests. Errors are
// logged and swallowed so a single misbehaving template can't take down
// the whole scheduler.
func (m *Module) runCronTick(ctx context.Context, now time.Time) {
	if err := m.materialiseDueInstances(ctx, now); err != nil {
		slog.Error("tasks cron: materialise failed", "error", err)
	}
	if err := m.markMissedInstances(ctx, now); err != nil {
		slog.Error("tasks cron: missed-detector failed", "error", err)
	}
}
