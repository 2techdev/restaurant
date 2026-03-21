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

// resolveTenant returns the tenant ID from JWT context or ?tenant_id= query param.
func resolveTenant(r *http.Request) string {
	if t := middleware.GetTenantID(r.Context()); t != "" {
		return t
	}
	return r.URL.Query().Get("tenant_id")
}

// ---------------------------------------------------------------------------
// Items — list
// ---------------------------------------------------------------------------

// handleListItems returns all inventory items for the tenant.
// GET /api/v1/inventory/items?low_stock=true
func (m *Module) handleListItems(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	lowStockOnly := r.URL.Query().Get("low_stock") == "true"

	query := `
		SELECT id, tenant_id, name, COALESCE(sku,''), unit,
		       current_qty, min_qty, max_qty, cost_per_unit,
		       COALESCE(supplier,''), COALESCE(notes,''),
		       is_active, created_at, updated_at
		FROM inventory_items
		WHERE tenant_id = $1 AND is_deleted = false`
	if lowStockOnly {
		query += ` AND current_qty <= min_qty`
	}
	query += ` ORDER BY name ASC`

	rows, err := m.db.QueryContext(r.Context(), query, tenantID)
	if err != nil {
		slog.Error("inventory: list items", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch inventory items")
		return
	}
	defer rows.Close()

	items := []InventoryItem{}
	for rows.Next() {
		item, err := scanItem(rows)
		if err != nil {
			continue
		}
		items = append(items, item)
	}
	response.Paginated(w, items, "", false)
}

// ---------------------------------------------------------------------------
// Items — create
// ---------------------------------------------------------------------------

// handleCreateItem creates a new inventory item.
// POST /api/v1/inventory/items
func (m *Module) handleCreateItem(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	var req struct {
		Name        string   `json:"name"`
		SKU         *string  `json:"sku"`
		Unit        string   `json:"unit"`
		CurrentQty  float64  `json:"current_qty"`
		MinQty      float64  `json:"min_qty"`
		MaxQty      *float64 `json:"max_qty"`
		CostPerUnit *int64   `json:"cost_per_unit"`
		Supplier    *string  `json:"supplier"`
		Notes       *string  `json:"notes"`
		IsActive    bool     `json:"is_active"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "name is required")
		return
	}
	if req.Unit == "" {
		req.Unit = "unit"
	}

	id := uuid.New()
	now := time.Now().UTC()

	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO inventory_items (
			id, tenant_id, name, sku, unit,
			current_qty, min_qty, max_qty, cost_per_unit,
			supplier, notes, is_active, created_at, updated_at, is_deleted
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$13,false)
	`, id, tenantID, req.Name,
		nullableString(req.SKU), req.Unit,
		req.CurrentQty, req.MinQty,
		nullableFloat64(req.MaxQty), nullableInt64(req.CostPerUnit),
		nullableString(req.Supplier), nullableString(req.Notes),
		req.IsActive, now,
	)
	if err != nil {
		slog.Error("inventory: create item", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create inventory item")
		return
	}

	item := InventoryItem{
		ID:          id,
		TenantID:    tenantID,
		Name:        req.Name,
		SKU:         req.SKU,
		Unit:        req.Unit,
		CurrentQty:  req.CurrentQty,
		MinQty:      req.MinQty,
		MaxQty:      req.MaxQty,
		CostPerUnit: req.CostPerUnit,
		Supplier:    req.Supplier,
		Notes:       req.Notes,
		IsActive:    req.IsActive,
		IsLow:       req.CurrentQty <= req.MinQty,
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	// Emit sync event so other devices pick up the new item.
	m.emitSyncEvent(r, tenantID, id, "insert", item)

	response.Created(w, item)
}

// ---------------------------------------------------------------------------
// Items — get single
// ---------------------------------------------------------------------------

// handleGetItem returns a single inventory item.
// GET /api/v1/inventory/items/{id}
func (m *Module) handleGetItem(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")

	row := m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, name, COALESCE(sku,''), unit,
		       current_qty, min_qty, max_qty, cost_per_unit,
		       COALESCE(supplier,''), COALESCE(notes,''),
		       is_active, created_at, updated_at
		FROM inventory_items
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID)

	item, err := scanItemRow(row)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Inventory item not found")
		return
	}
	if err != nil {
		slog.Error("inventory: get item", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch inventory item")
		return
	}
	response.JSON(w, http.StatusOK, item)
}

// ---------------------------------------------------------------------------
// Items — update
// ---------------------------------------------------------------------------

// handleUpdateItem updates an inventory item's metadata (not quantity).
// PUT /api/v1/inventory/items/{id}
func (m *Module) handleUpdateItem(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")

	var req struct {
		Name        string   `json:"name"`
		SKU         *string  `json:"sku"`
		Unit        string   `json:"unit"`
		MinQty      float64  `json:"min_qty"`
		MaxQty      *float64 `json:"max_qty"`
		CostPerUnit *int64   `json:"cost_per_unit"`
		Supplier    *string  `json:"supplier"`
		Notes       *string  `json:"notes"`
		IsActive    bool     `json:"is_active"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	res, err := m.db.ExecContext(r.Context(), `
		UPDATE inventory_items
		SET name=$1, sku=$2, unit=$3, min_qty=$4, max_qty=$5,
		    cost_per_unit=$6, supplier=$7, notes=$8, is_active=$9, updated_at=NOW()
		WHERE id=$10 AND tenant_id=$11 AND is_deleted=false
	`, req.Name,
		nullableString(req.SKU), req.Unit, req.MinQty,
		nullableFloat64(req.MaxQty), nullableInt64(req.CostPerUnit),
		nullableString(req.Supplier), nullableString(req.Notes),
		req.IsActive, id, tenantID,
	)
	if err != nil {
		slog.Error("inventory: update item", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update inventory item")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Inventory item not found")
		return
	}

	// Emit sync event.
	m.emitSyncEvent(r, tenantID, id, "update", map[string]any{"id": id})

	response.JSON(w, http.StatusOK, map[string]string{"id": id, "status": "updated"})
}

// ---------------------------------------------------------------------------
// Items — delete
// ---------------------------------------------------------------------------

// handleDeleteItem soft-deletes an inventory item.
// DELETE /api/v1/inventory/items/{id}
func (m *Module) handleDeleteItem(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")

	res, err := m.db.ExecContext(r.Context(), `
		UPDATE inventory_items SET is_deleted=true, updated_at=NOW()
		WHERE id=$1 AND tenant_id=$2 AND is_deleted=false
	`, id, tenantID)
	if err != nil {
		slog.Error("inventory: delete item", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete inventory item")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Inventory item not found")
		return
	}

	m.emitSyncEvent(r, tenantID, id, "delete", map[string]any{"id": id})

	response.NoContent(w)
}

// ---------------------------------------------------------------------------
// Movements — list
// ---------------------------------------------------------------------------

// handleListMovements returns stock movements for the tenant, optionally filtered by item.
// GET /api/v1/inventory/movements?item_id=<uuid>&limit=50
func (m *Module) handleListMovements(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	itemID := r.URL.Query().Get("item_id")
	limit := 100

	var rows *sql.Rows
	var err error
	if itemID != "" {
		rows, err = m.db.QueryContext(r.Context(), `
			SELECT sm.id, sm.tenant_id, sm.item_id, COALESCE(ii.name,''),
			       sm.movement_type, sm.qty, sm.qty_before, sm.qty_after,
			       COALESCE(sm.reference,''), COALESCE(sm.notes,''),
			       sm.performed_by, sm.created_at
			FROM stock_movements sm
			LEFT JOIN inventory_items ii ON ii.id = sm.item_id
			WHERE sm.tenant_id = $1 AND sm.item_id = $2
			ORDER BY sm.created_at DESC
			LIMIT $3
		`, tenantID, itemID, limit)
	} else {
		rows, err = m.db.QueryContext(r.Context(), `
			SELECT sm.id, sm.tenant_id, sm.item_id, COALESCE(ii.name,''),
			       sm.movement_type, sm.qty, sm.qty_before, sm.qty_after,
			       COALESCE(sm.reference,''), COALESCE(sm.notes,''),
			       sm.performed_by, sm.created_at
			FROM stock_movements sm
			LEFT JOIN inventory_items ii ON ii.id = sm.item_id
			WHERE sm.tenant_id = $1
			ORDER BY sm.created_at DESC
			LIMIT $2
		`, tenantID, limit)
	}
	if err != nil {
		slog.Error("inventory: list movements", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch stock movements")
		return
	}
	defer rows.Close()

	movements := []StockMovement{}
	for rows.Next() {
		var mv StockMovement
		var ref, notes, performedBy, itemName string
		if err := rows.Scan(
			&mv.ID, &mv.TenantID, &mv.ItemID, &itemName,
			&mv.MovementType, &mv.Qty, &mv.QtyBefore, &mv.QtyAfter,
			&ref, &notes,
			&performedBy, &mv.CreatedAt,
		); err != nil {
			continue
		}
		mv.ItemName = itemName
		if ref != "" {
			mv.Reference = &ref
		}
		if notes != "" {
			mv.Notes = &notes
		}
		if performedBy != "" {
			mv.PerformedBy = &performedBy
		}
		movements = append(movements, mv)
	}
	response.Paginated(w, movements, "", false)
}

// ---------------------------------------------------------------------------
// Movements — create
// ---------------------------------------------------------------------------

// handleCreateMovement records a stock movement and updates the item's current_qty.
// POST /api/v1/inventory/movements
//
// movement_type: stock_in | restock | stock_out | waste | adjustment
//   - stock_in, restock → add qty
//   - stock_out, waste  → subtract qty
//   - adjustment        → set current_qty to (qty_before + qty) where qty may be negative
func (m *Module) handleCreateMovement(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	var req struct {
		ItemID       string  `json:"item_id"`
		MovementType string  `json:"movement_type"`
		Qty          float64 `json:"qty"` // always positive for stock_in/out/waste/restock; signed for adjustment
		Reference    *string `json:"reference"`
		Notes        *string `json:"notes"`
		PerformedBy  *string `json:"performed_by"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.ItemID == "" || req.MovementType == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "item_id and movement_type are required")
		return
	}
	validTypes := map[string]bool{
		"stock_in": true, "stock_out": true,
		"waste": true, "restock": true, "adjustment": true,
	}
	if !validTypes[req.MovementType] {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR",
			"movement_type must be one of: stock_in, stock_out, waste, restock, adjustment")
		return
	}

	// ── Fetch current qty inside a transaction ──────────────────────────────
	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		slog.Error("inventory: begin tx", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to begin transaction")
		return
	}
	defer tx.Rollback()

	var qtyBefore float64
	err = tx.QueryRowContext(r.Context(), `
		SELECT current_qty FROM inventory_items
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
		FOR UPDATE
	`, req.ItemID, tenantID).Scan(&qtyBefore)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Inventory item not found")
		return
	}
	if err != nil {
		slog.Error("inventory: fetch item for movement", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch inventory item")
		return
	}

	// ── Calculate new qty ───────────────────────────────────────────────────
	var qtyAfter float64
	switch req.MovementType {
	case "stock_in", "restock":
		qtyAfter = qtyBefore + req.Qty
	case "stock_out", "waste":
		qtyAfter = qtyBefore - req.Qty
		if qtyAfter < 0 {
			qtyAfter = 0 // clamp to zero — no negative stock
		}
	case "adjustment":
		qtyAfter = qtyBefore + req.Qty // qty may be negative for downward adjustment
	}

	// ── Persist movement ────────────────────────────────────────────────────
	movID := uuid.New()
	now := time.Now().UTC()

	_, err = tx.ExecContext(r.Context(), `
		INSERT INTO stock_movements (
			id, tenant_id, item_id, movement_type,
			qty, qty_before, qty_after,
			reference, notes, performed_by, created_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
	`, movID, tenantID, req.ItemID, req.MovementType,
		req.Qty, qtyBefore, qtyAfter,
		nullableString(req.Reference), nullableString(req.Notes),
		nullableString(req.PerformedBy), now,
	)
	if err != nil {
		slog.Error("inventory: insert movement", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to record stock movement")
		return
	}

	// ── Update item's current_qty ───────────────────────────────────────────
	_, err = tx.ExecContext(r.Context(), `
		UPDATE inventory_items SET current_qty=$1, updated_at=NOW()
		WHERE id=$2 AND tenant_id=$3
	`, qtyAfter, req.ItemID, tenantID)
	if err != nil {
		slog.Error("inventory: update item qty", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update inventory quantity")
		return
	}

	if err := tx.Commit(); err != nil {
		slog.Error("inventory: commit tx", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to commit transaction")
		return
	}

	mv := StockMovement{
		ID:           movID,
		TenantID:     tenantID,
		ItemID:       req.ItemID,
		MovementType: req.MovementType,
		Qty:          req.Qty,
		QtyBefore:    qtyBefore,
		QtyAfter:     qtyAfter,
		Reference:    req.Reference,
		Notes:        req.Notes,
		PerformedBy:  req.PerformedBy,
		CreatedAt:    now,
	}

	// Emit sync events for both the movement and the updated item quantity.
	m.emitSyncEvent(r, tenantID, movID, "insert", mv)
	m.emitSyncEvent(r, tenantID, req.ItemID, "update", map[string]any{
		"id": req.ItemID, "current_qty": qtyAfter,
	})

	response.Created(w, mv)
}

// ---------------------------------------------------------------------------
// Sync event helper
// ---------------------------------------------------------------------------

// emitSyncEvent inserts a sync_events record so other devices can pick up the change.
// device_id is set to "server" for server-originated events.
func (m *Module) emitSyncEvent(r *http.Request, tenantID, recordID, operation string, payload any) {
	raw, err := json.Marshal(payload)
	if err != nil {
		return
	}
	eventID := uuid.New()
	now := time.Now().UTC()
	_, err = m.db.ExecContext(r.Context(), `
		INSERT INTO sync_events (id, tenant_id, device_id, table_name, record_id, operation, payload, created_at, received_at)
		VALUES ($1, $2, 'server', 'inventory_items', $3, $4, $5::jsonb, $6, $6)
		ON CONFLICT (id) DO NOTHING
	`, eventID, tenantID, recordID, operation, raw, now)
	if err != nil {
		slog.Warn("inventory: emit sync event", "error", err)
	}
}

// ---------------------------------------------------------------------------
// DB scan helpers
// ---------------------------------------------------------------------------

type rowScanner interface {
	Scan(dest ...any) error
}

func scanItem(s rowScanner) (InventoryItem, error) {
	var item InventoryItem
	var sku, supplier, notes string
	var maxQty sql.NullFloat64
	var costPerUnit sql.NullInt64
	err := s.Scan(
		&item.ID, &item.TenantID, &item.Name, &sku, &item.Unit,
		&item.CurrentQty, &item.MinQty, &maxQty, &costPerUnit,
		&supplier, &notes,
		&item.IsActive, &item.CreatedAt, &item.UpdatedAt,
	)
	if err != nil {
		return item, err
	}
	if sku != "" {
		item.SKU = &sku
	}
	if maxQty.Valid {
		item.MaxQty = &maxQty.Float64
	}
	if costPerUnit.Valid {
		item.CostPerUnit = &costPerUnit.Int64
	}
	if supplier != "" {
		item.Supplier = &supplier
	}
	if notes != "" {
		item.Notes = &notes
	}
	item.IsLow = item.CurrentQty <= item.MinQty
	return item, nil
}

func scanItemRow(row *sql.Row) (InventoryItem, error) {
	var item InventoryItem
	var sku, supplier, notes string
	var maxQty sql.NullFloat64
	var costPerUnit sql.NullInt64
	err := row.Scan(
		&item.ID, &item.TenantID, &item.Name, &sku, &item.Unit,
		&item.CurrentQty, &item.MinQty, &maxQty, &costPerUnit,
		&supplier, &notes,
		&item.IsActive, &item.CreatedAt, &item.UpdatedAt,
	)
	if err != nil {
		return item, err
	}
	if sku != "" {
		item.SKU = &sku
	}
	if maxQty.Valid {
		item.MaxQty = &maxQty.Float64
	}
	if costPerUnit.Valid {
		item.CostPerUnit = &costPerUnit.Int64
	}
	if supplier != "" {
		item.Supplier = &supplier
	}
	if notes != "" {
		item.Notes = &notes
	}
	item.IsLow = item.CurrentQty <= item.MinQty
	return item, nil
}

// ---------------------------------------------------------------------------
// Null helpers
// ---------------------------------------------------------------------------

func nullableString(s *string) any {
	if s == nil || *s == "" {
		return nil
	}
	return *s
}

func nullableFloat64(f *float64) any {
	if f == nil {
		return nil
	}
	return *f
}

func nullableInt64(n *int64) any {
	if n == nil {
		return nil
	}
	return *n
}
