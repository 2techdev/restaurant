package menu

import (
	"context"
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// Snooze ("86'd") — products with is_snoozed=true are filtered out of the POS
// catalog. snooze_until is an optional auto-reset deadline. When it's NULL
// the item stays snoozed until manually toggled; when it's set, the
// background reaper (StartSnoozeReaper) flips is_snoozed back to false once
// the timestamp passes.

type snoozeRequest struct {
	// Snoozed flips the flag. When Until is null and Snoozed is true, the
	// item stays snoozed indefinitely. When Snoozed is false, Until is
	// ignored and cleared.
	Snoozed bool       `json:"snoozed"`
	Until   *time.Time `json:"until,omitempty"`
}

func (m *Module) handleSnoozeProduct(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	var req snoozeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	var until any
	if req.Snoozed && req.Until != nil {
		until = *req.Until
	}
	// When un-snoozing, clear the deadline too so the row doesn't carry a
	// stale timestamp.
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE products
		   SET is_snoozed   = $1,
		       snooze_until = CASE WHEN $1 THEN $2::timestamptz ELSE NULL END,
		       updated_at   = NOW()
		 WHERE id = $3 AND tenant_id = $4
	`, req.Snoozed, until, id, tenantID)
	if err != nil {
		slog.Error("menu: snooze", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update snooze")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Product not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]any{
		"status":   "updated",
		"snoozed":  req.Snoozed,
		"until":    req.Until,
	})
}

type snoozeBulkRequest struct {
	ProductIDs []string   `json:"product_ids"`
	Snoozed    bool       `json:"snoozed"`
	Until      *time.Time `json:"until,omitempty"`
}

func (m *Module) handleSnoozeBulk(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	var req snoozeBulkRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	if len(req.ProductIDs) == 0 {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "product_ids required")
		return
	}
	var until any
	if req.Snoozed && req.Until != nil {
		until = *req.Until
	}
	// pq.Array would be nicer but we don't import pq here. Build the IN
	// clause manually — fine for the dozens-of-IDs scale the bulk action
	// will ever reach (UI caps at a single page selection).
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE products
		   SET is_snoozed   = $1,
		       snooze_until = CASE WHEN $1 THEN $2::timestamptz ELSE NULL END,
		       updated_at   = NOW()
		 WHERE tenant_id = $3
		   AND id = ANY($4::uuid[])
	`, req.Snoozed, until, tenantID, pgUUIDArray(req.ProductIDs))
	if err != nil {
		slog.Error("menu: snooze bulk", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update")
		return
	}
	n, _ := res.RowsAffected()
	response.JSON(w, http.StatusOK, map[string]any{
		"status":  "updated",
		"updated": n,
	})
}

func pgUUIDArray(items []string) string {
	if len(items) == 0 {
		return "{}"
	}
	out := "{"
	for i, s := range items {
		if i > 0 {
			out += ","
		}
		out += s
	}
	out += "}"
	return out
}

// StartSnoozeReaper launches a goroutine that, every minute, clears
// is_snoozed on rows whose snooze_until has passed. Cheap: indexed partial
// scan over only-active-snoozes, single UPDATE. Logs at INFO when it acts.
//
// Call once from cmd/server/main.go after the module is constructed.
func (m *Module) StartSnoozeReaper(ctx context.Context) {
	go func() {
		ticker := time.NewTicker(60 * time.Second)
		defer ticker.Stop()
		slog.Info("snooze-reaper: started", "interval_s", 60)
		for {
			select {
			case <-ctx.Done():
				slog.Info("snooze-reaper: stopped")
				return
			case <-ticker.C:
				m.reapExpiredSnoozes(ctx)
			}
		}
	}()
}

func (m *Module) reapExpiredSnoozes(ctx context.Context) {
	res, err := m.db.ExecContext(ctx, `
		UPDATE products
		   SET is_snoozed   = false,
		       snooze_until = NULL,
		       updated_at   = NOW()
		 WHERE is_snoozed   = true
		   AND snooze_until IS NOT NULL
		   AND snooze_until < NOW()
	`)
	if err != nil {
		slog.Error("snooze-reaper: update failed", "error", err)
		return
	}
	if n, _ := res.RowsAffected(); n > 0 {
		slog.Info("snooze-reaper: reset", "count", n)
	}
}

// Ensure database/sql import isn't unused on partial builds.
var _ = sql.ErrNoRows
