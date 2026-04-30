package inventory

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

// handleAdjust is a convenience wrapper around the stock_movements ledger.
// It records a single movement and updates the item's current_qty atomically.
//
// POST /api/v1/inventory/{id}/adjust
//
// body: { "delta": -3.5, "reason": "spillage", "notes": "..." }
//
//	delta > 0  → restock,
//	delta < 0  → stock_out,
//	delta == 0 → no-op (still records an audit movement of type "adjustment").
func (m *Module) handleAdjust(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	itemID := r.PathValue("id")

	var req struct {
		Delta  float64 `json:"delta"`
		Reason *string `json:"reason"`
		Notes  *string `json:"notes"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}

	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to begin tx")
		return
	}
	defer tx.Rollback()

	var qtyBefore float64
	err = tx.QueryRowContext(r.Context(), `
		SELECT current_qty FROM inventory_items
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
		FOR UPDATE
	`, itemID, tenantID).Scan(&qtyBefore)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Inventory item not found")
		return
	}
	if err != nil {
		slog.Error("inventory: adjust load", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load item")
		return
	}

	qtyAfter := qtyBefore + req.Delta
	if qtyAfter < 0 {
		qtyAfter = 0
	}

	movementType := "adjustment"
	switch {
	case req.Delta > 0:
		movementType = "restock"
	case req.Delta < 0:
		movementType = "stock_out"
	}

	// Movement qty is always positive (sign derived from movement_type).
	absQty := req.Delta
	if absQty < 0 {
		absQty = -absQty
	}

	movID := uuid.New()
	now := time.Now().UTC()
	performedBy := middleware.GetUserID(r.Context())

	_, err = tx.ExecContext(r.Context(), `
		INSERT INTO stock_movements (
			id, tenant_id, item_id, movement_type,
			qty, qty_before, qty_after,
			reference, notes, performed_by, created_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
	`, movID, tenantID, itemID, movementType,
		absQty, qtyBefore, qtyAfter,
		nullableString(req.Reason), nullableString(req.Notes),
		nullablePerformer(performedBy), now)
	if err != nil {
		slog.Error("inventory: adjust insert", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to record adjustment")
		return
	}

	_, err = tx.ExecContext(r.Context(), `
		UPDATE inventory_items SET current_qty = $1, updated_at = NOW()
		WHERE id = $2 AND tenant_id = $3
	`, qtyAfter, itemID, tenantID)
	if err != nil {
		slog.Error("inventory: adjust update", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update qty")
		return
	}

	if err := tx.Commit(); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to commit")
		return
	}

	m.emitSyncEvent(r, tenantID, itemID, "update", map[string]any{
		"id":          itemID,
		"current_qty": qtyAfter,
	})

	response.JSON(w, http.StatusOK, map[string]any{
		"id":            itemID,
		"qty_before":    qtyBefore,
		"qty_after":     qtyAfter,
		"delta":         req.Delta,
		"movement_id":   movID,
		"movement_type": movementType,
	})
}

// handleLowStock returns items whose current_qty has dropped to or below
// min_qty (the reorder threshold). Sorts by largest deficit first.
// GET /api/v1/inventory/low-stock
func (m *Module) handleLowStock(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, name, COALESCE(sku,''), unit,
		       current_qty, min_qty, max_qty, cost_per_unit,
		       COALESCE(supplier,''), COALESCE(notes,''),
		       is_active, created_at, updated_at
		FROM inventory_items
		WHERE tenant_id = $1 AND is_deleted = false AND is_active = true
		  AND current_qty <= min_qty
		ORDER BY (min_qty - current_qty) DESC, name ASC
	`, tenantID)
	if err != nil {
		slog.Error("inventory: low-stock", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load low-stock items")
		return
	}
	defer rows.Close()

	items := make([]InventoryItem, 0)
	for rows.Next() {
		item, err := scanItem(rows)
		if err != nil {
			continue
		}
		items = append(items, item)
	}
	response.JSON(w, http.StatusOK, map[string]any{
		"count": len(items),
		"items": items,
	})
}

func nullablePerformer(s string) any {
	if s == "" {
		return nil
	}
	if !uuid.IsValid(s) {
		return nil
	}
	return s
}
