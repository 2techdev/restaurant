package org

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

// buildSnapshotFromTenant reads categories/products/modifier_groups/modifiers
// for the given tenant_id and returns a MenuSnapshot. Used both for the HQ
// master snapshot and for collecting per-tenant local data for merging.
func (m *Module) buildSnapshotFromTenant(ctx context.Context, tenantID string) (MenuSnapshot, error) {
	var snap MenuSnapshot
	snap.GeneratedAt = time.Now().UTC()
	snap.Source = "local"
	snap.Categories = []SnapshotCategory{}
	snap.Products = []SnapshotProduct{}
	snap.ModifierGroups = []SnapshotModifierGroup{}

	// Categories
	rows, err := m.db.QueryContext(ctx, `
		SELECT id::text, name, display_order,
		       COALESCE(color,''), COALESCE(icon,''),
		       COALESCE(parent_id::text,''), is_active
		FROM categories
		WHERE tenant_id = $1 AND is_deleted = FALSE
		ORDER BY display_order, name
	`, tenantID)
	if err != nil {
		return snap, fmt.Errorf("categories: %w", err)
	}
	for rows.Next() {
		var c SnapshotCategory
		var color, icon, parent string
		if err := rows.Scan(&c.ID, &c.Name, &c.DisplayOrder, &color, &icon, &parent, &c.IsActive); err != nil {
			rows.Close()
			return snap, err
		}
		if color != "" {
			c.Color = &color
		}
		if icon != "" {
			c.Icon = &icon
		}
		if parent != "" {
			c.ParentID = &parent
		}
		snap.Categories = append(snap.Categories, c)
	}
	rows.Close()

	// Products
	rows, err = m.db.QueryContext(ctx, `
		SELECT id::text, category_id::text, name, COALESCE(description,''),
		       price, cost_price, tax_group,
		       COALESCE(image_path,''), COALESCE(barcode,''),
		       is_active, display_order, prep_time_minutes,
		       COALESCE(printer_group,'kitchen'), default_gang
		FROM products
		WHERE tenant_id = $1 AND is_deleted = FALSE
		ORDER BY display_order, name
	`, tenantID)
	if err != nil {
		return snap, fmt.Errorf("products: %w", err)
	}
	for rows.Next() {
		var p SnapshotProduct
		var desc, image, barcode string
		var prep sql.NullInt64
		var dg sql.NullInt16
		if err := rows.Scan(&p.ID, &p.CategoryID, &p.Name, &desc,
			&p.Price, &p.CostPrice, &p.TaxGroup,
			&image, &barcode,
			&p.IsActive, &p.DisplayOrder, &prep,
			&p.PrinterGroup, &dg); err != nil {
			rows.Close()
			return snap, err
		}
		if desc != "" {
			p.Description = &desc
		}
		if image != "" {
			p.ImagePath = &image
		}
		if barcode != "" {
			p.Barcode = &barcode
		}
		if prep.Valid {
			v := int(prep.Int64)
			p.PrepTimeMinutes = &v
		}
		if dg.Valid {
			v := int(dg.Int16)
			p.DefaultGang = &v
		}
		snap.Products = append(snap.Products, p)
	}
	rows.Close()

	// Modifier groups
	rows, err = m.db.QueryContext(ctx, `
		SELECT id::text, name, selection_type, min_selections, max_selections,
		       is_required, display_order
		FROM modifier_groups
		WHERE tenant_id = $1 AND is_deleted = FALSE
		ORDER BY display_order
	`, tenantID)
	if err != nil {
		return snap, fmt.Errorf("modifier_groups: %w", err)
	}
	groupIdx := map[string]int{}
	for rows.Next() {
		var g SnapshotModifierGroup
		if err := rows.Scan(&g.ID, &g.Name, &g.SelectionType, &g.MinSelections, &g.MaxSelections,
			&g.IsRequired, &g.DisplayOrder); err != nil {
			rows.Close()
			return snap, err
		}
		g.Modifiers = []SnapshotModifier{}
		groupIdx[g.ID] = len(snap.ModifierGroups)
		snap.ModifierGroups = append(snap.ModifierGroups, g)
	}
	rows.Close()

	if len(snap.ModifierGroups) > 0 {
		rows, err = m.db.QueryContext(ctx, `
			SELECT id::text, group_id::text, name, price_delta, is_default, display_order
			FROM modifiers
			WHERE tenant_id = $1 AND is_deleted = FALSE
			ORDER BY display_order
		`, tenantID)
		if err != nil {
			return snap, fmt.Errorf("modifiers: %w", err)
		}
		for rows.Next() {
			var gid string
			var mod SnapshotModifier
			if err := rows.Scan(&mod.ID, &gid, &mod.Name, &mod.PriceDelta, &mod.IsDefault, &mod.DisplayOrder); err != nil {
				rows.Close()
				return snap, err
			}
			if i, ok := groupIdx[gid]; ok {
				snap.ModifierGroups[i].Modifiers = append(snap.ModifierGroups[i].Modifiers, mod)
			}
		}
		rows.Close()
	}

	return snap, nil
}

// mergeMasterIntoLocal applies a master snapshot onto a local snapshot,
// honouring the supplied policy map (productID -> lock_type).
//
// Rules per product:
//   - FULLY_LOCKED  → master version wins outright. Local copy (if any) is
//                      replaced; local edits ignored.
//   - PRICE_LOCKED  → master.price + cost_price + tax_group win. Local
//                      name/description/image/display_order are preserved
//                      when present.
//   - FLEXIBLE      → local version (if it exists) wins over master.
//                      Otherwise master is inherited.
//   - default       → treat as FLEXIBLE.
//
// Categories / modifier groups: master wins for matching ids; local-only
// entries are kept when allow_local_additions is implicitly true (default).
func mergeMasterIntoLocal(master, local MenuSnapshot, policies map[string]MenuPolicy) MenuSnapshot {
	// Index local by id
	localProducts := map[string]SnapshotProduct{}
	for _, p := range local.Products {
		localProducts[p.ID] = p
	}
	localCategories := map[string]SnapshotCategory{}
	for _, c := range local.Categories {
		localCategories[c.ID] = c
	}
	localGroups := map[string]SnapshotModifierGroup{}
	for _, g := range local.ModifierGroups {
		localGroups[g.ID] = g
	}

	merged := MenuSnapshot{
		Source:         "master",
		OrganizationID: master.OrganizationID,
		Version:        local.Version, // per-tenant version, set by caller
		MasterVersion:  &master.Version,
		GeneratedAt:    time.Now().UTC(),
		Categories:     []SnapshotCategory{},
		Products:       []SnapshotProduct{},
		ModifierGroups: []SnapshotModifierGroup{},
	}

	// Categories: master wins, local-only kept.
	seenCat := map[string]bool{}
	for _, c := range master.Categories {
		seenCat[c.ID] = true
		merged.Categories = append(merged.Categories, c)
	}
	for _, c := range local.Categories {
		if !seenCat[c.ID] {
			merged.Categories = append(merged.Categories, c)
		}
	}

	// Products: apply policy.
	seenProd := map[string]bool{}
	for _, mp := range master.Products {
		seenProd[mp.ID] = true
		mp.IsMaster = true
		pol, hasPol := policies[mp.ID]
		lockType := LockTypeFlexible
		if hasPol {
			lockType = pol.LockType
		}
		mp.LockType = lockType
		lp, hasLocal := localProducts[mp.ID]

		switch lockType {
		case LockTypeFullyLocked:
			merged.Products = append(merged.Products, mp)
		case LockTypePriceLocked:
			if hasLocal {
				// Keep local cosmetic fields, force master price.
				merged.Products = append(merged.Products, SnapshotProduct{
					ID:              mp.ID,
					CategoryID:      mp.CategoryID,
					Name:            stringOr(lp.Name, mp.Name),
					Description:     ptrOr(lp.Description, mp.Description),
					Price:           mp.Price,
					CostPrice:       mp.CostPrice,
					TaxGroup:        mp.TaxGroup,
					ImagePath:       ptrOr(lp.ImagePath, mp.ImagePath),
					Barcode:         ptrOr(lp.Barcode, mp.Barcode),
					IsActive:        lp.IsActive && mp.IsActive,
					DisplayOrder:    lp.DisplayOrder,
					PrepTimeMinutes: ptrOrInt(lp.PrepTimeMinutes, mp.PrepTimeMinutes),
					PrinterGroup:    stringOr(lp.PrinterGroup, mp.PrinterGroup),
					DefaultGang:     ptrOrInt(lp.DefaultGang, mp.DefaultGang),
					LockType:        lockType,
					IsMaster:        true,
				})
			} else {
				merged.Products = append(merged.Products, mp)
			}
		default: // FLEXIBLE
			if hasLocal {
				lp.LockType = lockType
				lp.IsMaster = true
				merged.Products = append(merged.Products, lp)
			} else {
				merged.Products = append(merged.Products, mp)
			}
		}
	}
	// Local-only products (LocalOnly = true)
	for id, lp := range localProducts {
		if seenProd[id] {
			continue
		}
		lp.LocalOnly = true
		merged.Products = append(merged.Products, lp)
	}

	// Modifier groups: master wins for matches, local-only kept.
	seenG := map[string]bool{}
	for _, g := range master.ModifierGroups {
		seenG[g.ID] = true
		merged.ModifierGroups = append(merged.ModifierGroups, g)
	}
	for _, g := range local.ModifierGroups {
		if !seenG[g.ID] {
			merged.ModifierGroups = append(merged.ModifierGroups, g)
		}
	}
	_ = localGroups // reserved for future per-modifier merging
	_ = localCategories

	return merged
}

func stringOr(a, b string) string {
	if a != "" {
		return a
	}
	return b
}
func ptrOr(a, b *string) *string {
	if a != nil && *a != "" {
		return a
	}
	return b
}
func ptrOrInt(a, b *int) *int {
	if a != nil {
		return a
	}
	return b
}

// loadOrgPolicies returns a productID->MenuPolicy map for the org.
func (m *Module) loadOrgPolicies(ctx context.Context, orgID string) (map[string]MenuPolicy, error) {
	rows, err := m.db.QueryContext(ctx, `
		SELECT id::text, organization_id::text, product_id::text, lock_type,
		       allow_local_additions, allow_local_disable, created_at, updated_at
		FROM menu_policies WHERE organization_id = $1
	`, orgID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]MenuPolicy{}
	for rows.Next() {
		var p MenuPolicy
		if err := rows.Scan(&p.ID, &p.OrganizationID, &p.ProductID, &p.LockType,
			&p.AllowLocalAdditions, &p.AllowLocalDisable, &p.CreatedAt, &p.UpdatedAt); err == nil {
			out[p.ProductID] = p
		}
	}
	return out, rows.Err()
}

// ─────────────────────────────────────────────────────────────
// POST /api/v1/org/{orgId}/master-menu/publish
// 1. Snapshot master tenant
// 2. Insert master_menu_versions row with new version
// 3. Update master_menus.current_version
// 4. For every member tenant: build local snapshot, merge with master,
//    insert per-tenant menu_versions row, broadcast WS notification.
// ─────────────────────────────────────────────────────────────
func (m *Module) handlePublishMasterMenu(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	info, ok := m.hqOnly(w, r, orgID)
	if !ok {
		return
	}

	masterTenant, err := m.ensureMasterTenant(r.Context(), orgID, info.UserID)
	if err != nil {
		slog.Error("org/publish: ensure master", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to ensure master tenant")
		return
	}

	masterSnap, err := m.buildSnapshotFromTenant(r.Context(), masterTenant)
	if err != nil {
		slog.Error("org/publish: master snapshot", "error", err)
		response.Error(w, http.StatusInternalServerError, "SNAPSHOT_ERROR", "Failed to build master snapshot")
		return
	}
	masterSnap.OrganizationID = orgID
	masterSnap.Source = "master"

	policies, err := m.loadOrgPolicies(r.Context(), orgID)
	if err != nil {
		slog.Warn("org/publish: load policies", "error", err)
		policies = map[string]MenuPolicy{}
	}

	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to begin transaction")
		return
	}
	defer tx.Rollback()

	// Compute next version
	var nextVer int
	if err := tx.QueryRowContext(r.Context(), `
		SELECT COALESCE(current_version,0) + 1 FROM master_menus WHERE organization_id = $1
	`, orgID).Scan(&nextVer); err != nil {
		if err == sql.ErrNoRows {
			nextVer = 1
			if _, err := tx.ExecContext(r.Context(), `
				INSERT INTO master_menus (organization_id, current_version, updated_at)
				VALUES ($1, 0, NOW()) ON CONFLICT (organization_id) DO NOTHING
			`, orgID); err != nil {
				response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to init master_menus")
				return
			}
		} else {
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to read current version")
			return
		}
	}
	masterSnap.Version = nextVer

	masterPayload, err := json.Marshal(masterSnap)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "JSON_ERROR", "Failed to marshal master snapshot")
		return
	}

	if _, err := tx.ExecContext(r.Context(), `
		INSERT INTO master_menu_versions (id, organization_id, version, snapshot, published_at, published_by)
		VALUES (gen_random_uuid(), $1, $2, $3, NOW(), NULLIF($4,'')::uuid)
	`, orgID, nextVer, masterPayload, info.UserID); err != nil {
		slog.Error("org/publish: insert master_menu_version", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to record master version")
		return
	}
	if _, err := tx.ExecContext(r.Context(), `
		UPDATE master_menus SET current_version = $2, updated_at = NOW() WHERE organization_id = $1
	`, orgID, nextVer); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to advance master version")
		return
	}

	// Fan out to all member tenants (including the master itself).
	memberIDs, err := m.memberTenantIDsTx(tx, r.Context(), orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list members")
		return
	}

	pushed := 0
	pushedTenants := make([]string, 0, len(memberIDs))
	for _, tid := range memberIDs {
		var local MenuSnapshot
		if tid == masterTenant {
			local = masterSnap
		} else {
			local, err = m.buildSnapshotFromTenant(r.Context(), tid)
			if err != nil {
				slog.Warn("org/publish: local snapshot failed", "tenant_id", tid, "error", err)
				continue
			}
		}
		merged := mergeMasterIntoLocal(masterSnap, local, policies)

		// Compute next per-tenant version
		var tNext int
		if err := tx.QueryRowContext(r.Context(), `
			SELECT COALESCE(MAX(version),0)+1 FROM menu_versions WHERE tenant_id = $1
		`, tid).Scan(&tNext); err != nil {
			slog.Warn("org/publish: next tenant version", "tenant_id", tid, "error", err)
			continue
		}
		merged.Version = tNext

		body, err := json.Marshal(merged)
		if err != nil {
			slog.Warn("org/publish: marshal merged", "tenant_id", tid, "error", err)
			continue
		}

		if _, err := tx.ExecContext(r.Context(), `
			INSERT INTO menu_versions (id, tenant_id, version, snapshot, source, organization_id, master_version, published_at, published_by)
			VALUES (gen_random_uuid(), $1, $2, $3, 'master', $4, $5, NOW(), NULLIF($6,'')::uuid)
		`, tid, tNext, body, orgID, nextVer, info.UserID); err != nil {
			slog.Warn("org/publish: insert tenant version", "tenant_id", tid, "error", err)
			continue
		}
		pushed++
		pushedTenants = append(pushedTenants, tid)
	}

	if err := tx.Commit(); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to commit publish")
		return
	}

	// Broadcast WS notification (best-effort, non-fatal).
	if m.hub != nil {
		for _, tid := range pushedTenants {
			m.hub.NotifyTenant(tid, middleware.GetDeviceID(r.Context()), 1)
		}
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"organization_id":    orgID,
		"master_version":     nextVer,
		"published_to":       pushed,
		"member_count":       len(memberIDs),
		"pushed_tenant_ids":  pushedTenants,
	})
}

// memberTenantIDsTx — same as memberTenantIDs but inside a transaction.
func (m *Module) memberTenantIDsTx(tx *sql.Tx, ctx context.Context, orgID string) ([]string, error) {
	rows, err := tx.QueryContext(ctx, `SELECT tenant_id::text FROM organization_memberships WHERE organization_id = $1`, orgID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	ids := make([]string, 0)
	for rows.Next() {
		var s string
		if err := rows.Scan(&s); err == nil {
			ids = append(ids, s)
		}
	}
	return ids, rows.Err()
}

// IsValidUUID is exported so other packages and tests can validate UUIDs
// without importing the shared/uuid package directly.
func IsValidUUID(s string) bool { return uuid.IsValid(s) }
