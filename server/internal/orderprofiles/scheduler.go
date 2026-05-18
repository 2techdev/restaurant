package orderprofiles

import (
	"context"
	"database/sql"
	"encoding/json"
	"log/slog"
	"strings"
	"sync"
	"time"
)

// scheduler walks every tenant once a minute, recomputes the active-profile
// set, and broadcasts a `profile_changed` WS event when the winner ID flips
// from last tick.  Initial-tick broadcasts are suppressed (we don't want
// every boot to spam POS clients with a "no change" event).

type scheduler struct {
	mu          sync.Mutex
	lastWinner  map[string]string // tenantID -> winner profile ID
	initialised map[string]bool   // suppress first-tick broadcast per tenant
}

func newScheduler() *scheduler {
	return &scheduler{
		lastWinner:  map[string]string{},
		initialised: map[string]bool{},
	}
}

// Start kicks off the background ticker.  ctx cancels the loop on shutdown.
// Ticker interval is exposed for tests; production uses 60s.
func (m *Module) startScheduler(ctx context.Context, interval time.Duration) {
	if interval <= 0 {
		interval = time.Minute
	}
	t := time.NewTicker(interval)
	go func() {
		defer t.Stop()
		// Tick once at startup so the in-memory map seeds before the first
		// real interval elapses; this primes the suppress-initial-broadcast
		// gate above.
		m.tick(ctx)
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				m.tick(ctx)
			}
		}
	}()
}

func (m *Module) tick(ctx context.Context) {
	tenants, err := m.listActiveTenantIDs(ctx)
	if err != nil {
		slog.Warn("order-profiles: tick tenant list failed", "error", err)
		return
	}
	now := time.Now()
	for _, tenantID := range tenants {
		profiles, err := m.listProfiles(ctx, tenantID)
		if err != nil {
			slog.Warn("order-profiles: tick load failed", "tenant", tenantID, "error", err)
			continue
		}
		summary := computeActive(profiles, now, tenantID)
		newWinner := ""
		if summary.WinnerID != nil {
			newWinner = *summary.WinnerID
		}

		m.sched.mu.Lock()
		prev := m.sched.lastWinner[tenantID]
		seen := m.sched.initialised[tenantID]
		m.sched.lastWinner[tenantID] = newWinner
		m.sched.initialised[tenantID] = true
		m.sched.mu.Unlock()

		if !seen {
			continue // first observation — no baseline to diff against
		}
		if prev == newWinner {
			continue
		}
		// Winner flipped — fan out so connected POS terminals re-price the
		// cart immediately rather than waiting for their next pull.
		if m.hub != nil {
			evt, _ := json.Marshal(map[string]any{
				"type":            "profile_changed",
				"tenant_id":       tenantID,
				"winner_id":       summary.WinnerID,
				"active_ids":      summary.ActiveIDs,
				"computed_at":     summary.ComputedAt.Format(time.RFC3339),
				"previous_winner": prev,
			})
			m.hub.BroadcastTenant(tenantID, evt)
		}
		slog.Info("order-profiles: winner changed",
			"tenant", tenantID, "prev", prev, "new", newWinner)
	}
}

// notifyChanged is called by CRUD handlers; it's a "schedule changed,
// recompute NOW" signal so the operator doesn't have to wait 60s to see
// their edit reflected at POS terminals.  Cheap because it walks only the
// one tenant.
func (m *Module) notifyChanged(ctx context.Context, tenantID string) {
	profiles, err := m.listProfiles(ctx, tenantID)
	if err != nil {
		return
	}
	summary := computeActive(profiles, time.Now(), tenantID)
	newWinner := ""
	if summary.WinnerID != nil {
		newWinner = *summary.WinnerID
	}
	m.sched.mu.Lock()
	prev := m.sched.lastWinner[tenantID]
	m.sched.lastWinner[tenantID] = newWinner
	m.sched.initialised[tenantID] = true
	m.sched.mu.Unlock()

	// Always broadcast on explicit edits — operators want immediate
	// feedback in test mode even when the winner didn't change (e.g. they
	// only edited the pricing rules of the currently-winning profile).
	if m.hub == nil {
		return
	}
	evt, _ := json.Marshal(map[string]any{
		"type":            "profile_changed",
		"tenant_id":       tenantID,
		"winner_id":       summary.WinnerID,
		"active_ids":      summary.ActiveIDs,
		"computed_at":     summary.ComputedAt.Format(time.RFC3339),
		"previous_winner": prev,
		"reason":          "edit",
	})
	m.hub.BroadcastTenant(tenantID, evt)
}

// listActiveTenantIDs reads tenants that have at least one row in
// order_profiles — there's no point recomputing for tenants that haven't
// opted in.  A future filter could also skip tenants whose pos_api_key
// is null (no live POS to notify).
func (m *Module) listActiveTenantIDs(ctx context.Context) ([]string, error) {
	rows, err := m.db.QueryContext(ctx, `
		SELECT DISTINCT tenant_id::text FROM order_profiles
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var id sql.NullString
		if err := rows.Scan(&id); err == nil && id.Valid {
			out = append(out, strings.TrimSpace(id.String))
		}
	}
	return out, nil
}
