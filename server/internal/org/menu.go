package org

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

// ─────────────────────────────────────────────────────────────
// Master menu storage strategy
// ─────────────────────────────────────────────────────────────
// The HQ master menu is stored as ordinary categories/products/modifiers
// rows scoped to the org's master tenant (organization_memberships.is_master).
// This means:
//   * Existing menu CRUD tooling, snapshot machinery, and JSON shapes work
//     unchanged for the master tenant.
//   * The master tenant's published menu doubles as the org master snapshot.
//   * Per-org isolation is preserved through tenant_id and the membership
//     uniqueness constraint.
//
// "Publish" composes a snapshot from the master tenant's categories /
// products / modifiers, persists it as a master_menu_versions row, then
// fans it out to every member tenant by writing a merged snapshot to
// menu_versions per follower (see publish.go).

// ensureMasterTenant returns the master tenant id, creating one and a
// matching membership row when missing. The caller must be authorized.
func (m *Module) ensureMasterTenant(ctx context.Context, orgID, userID string) (string, error) {
	tid, err := m.masterTenantID(ctx, orgID)
	if err == nil {
		return tid, nil
	}
	if !errors.Is(err, errMasterMissing) {
		return "", err
	}

	tid = uuid.New()
	tx, err := m.db.BeginTx(ctx, nil)
	if err != nil {
		return "", err
	}
	defer tx.Rollback()

	if _, err := tx.ExecContext(ctx, `
		INSERT INTO tenants (id, name, organization_id, created_at, updated_at)
		VALUES ($1, $2, $3, NOW(), NOW())
	`, tid, "HQ Master", orgID); err != nil {
		return "", err
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO organization_memberships (organization_id, tenant_id, joined_at, is_master)
		VALUES ($1, $2, NOW(), TRUE)
	`, orgID, tid); err != nil {
		return "", err
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO master_menus (organization_id, current_version, updated_at)
		VALUES ($1, 0, NOW())
		ON CONFLICT (organization_id) DO NOTHING
	`, orgID); err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", err
	}
	return tid, nil
}

// ─────────────────────────────────────────────────────────────
// GET /api/v1/org/{orgId}/master-menu
// ─────────────────────────────────────────────────────────────
func (m *Module) handleGetMasterMenu(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	info, ok := m.hqOnly(w, r, orgID)
	if !ok {
		return
	}
	tid, err := m.ensureMasterTenant(r.Context(), orgID, info.UserID)
	if err != nil {
		slog.Error("org/master-menu: ensure", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load master menu")
		return
	}

	snap, err := m.buildSnapshotFromTenant(r.Context(), tid)
	if err != nil {
		slog.Error("org/master-menu: snapshot", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to build menu snapshot")
		return
	}
	snap.OrganizationID = orgID
	snap.Source = "master"

	var current int
	if err := m.db.QueryRowContext(r.Context(), `
		SELECT COALESCE(current_version,0) FROM master_menus WHERE organization_id = $1
	`, orgID).Scan(&current); err != nil && err != sql.ErrNoRows {
		slog.Warn("org/master-menu: current version", "error", err)
	}
	snap.Version = current

	response.JSON(w, http.StatusOK, map[string]any{
		"organization_id":  orgID,
		"master_tenant_id": tid,
		"current_version":  current,
		"snapshot":         snap,
	})
}

// ─────────────────────────────────────────────────────────────
// POST /api/v1/org/{orgId}/master-menu/categories
// ─────────────────────────────────────────────────────────────
func (m *Module) handleCreateMasterCategory(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	info, ok := m.hqOnly(w, r, orgID)
	if !ok {
		return
	}
	tid, err := m.ensureMasterTenant(r.Context(), orgID, info.UserID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to ensure master tenant")
		return
	}

	var req struct {
		Name         string  `json:"name"`
		DisplayOrder int     `json:"display_order"`
		Color        *string `json:"color"`
		Icon         *string `json:"icon"`
		ParentID     *string `json:"parent_id"`
		IsActive     *bool   `json:"is_active"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "name is required")
		return
	}

	id := uuid.New()
	now := time.Now().UTC()
	active := true
	if req.IsActive != nil {
		active = *req.IsActive
	}

	_, err = m.db.ExecContext(r.Context(), `
		INSERT INTO categories (id, tenant_id, name, display_order, color, icon, parent_id, is_active,
		                       created_at, updated_at, sync_status, is_deleted)
		VALUES ($1,$2,$3,$4,$5,$6,$7::uuid,$8,$9,$9,0,FALSE)
	`, id, tid, req.Name, req.DisplayOrder,
		nullableStr(req.Color), nullableStr(req.Icon), nullableStr(req.ParentID),
		active, now)
	if err != nil {
		slog.Error("org/master-menu: create category", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create category")
		return
	}

	response.Created(w, map[string]any{
		"id":              id,
		"organization_id": orgID,
		"tenant_id":       tid,
		"name":            req.Name,
	})
}

// PUT /api/v1/org/{orgId}/master-menu/categories/{id}
func (m *Module) handleUpdateMasterCategory(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	info, ok := m.hqOnly(w, r, orgID)
	if !ok {
		return
	}
	tid, err := m.masterTenantID(r.Context(), orgID)
	if err != nil {
		response.Error(w, http.StatusNotFound, "NO_MASTER", "Master tenant not configured")
		return
	}
	_ = info
	id := r.PathValue("id")
	if !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_ID", "Invalid id")
		return
	}

	var req struct {
		Name         string  `json:"name"`
		DisplayOrder int     `json:"display_order"`
		Color        *string `json:"color"`
		Icon         *string `json:"icon"`
		IsActive     bool    `json:"is_active"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	res, err := m.db.ExecContext(r.Context(), `
		UPDATE categories
		SET name=$1, display_order=$2, color=$3, icon=$4, is_active=$5, updated_at=NOW()
		WHERE id=$6 AND tenant_id=$7 AND is_deleted=FALSE
	`, req.Name, req.DisplayOrder,
		nullableStr(req.Color), nullableStr(req.Icon),
		req.IsActive, id, tid)
	if err != nil {
		slog.Error("org/master-menu: update category", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update category")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Category not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"id": id, "status": "updated"})
}

// DELETE /api/v1/org/{orgId}/master-menu/categories/{id}
func (m *Module) handleDeleteMasterCategory(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	if _, ok := m.hqOnly(w, r, orgID); !ok {
		return
	}
	tid, err := m.masterTenantID(r.Context(), orgID)
	if err != nil {
		response.Error(w, http.StatusNotFound, "NO_MASTER", "Master tenant not configured")
		return
	}
	id := r.PathValue("id")
	if !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_ID", "Invalid id")
		return
	}

	res, err := m.db.ExecContext(r.Context(), `
		UPDATE categories SET is_deleted=TRUE, updated_at=NOW()
		WHERE id=$1 AND tenant_id=$2 AND is_deleted=FALSE
	`, id, tid)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete category")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Category not found")
		return
	}
	response.NoContent(w)
}

// POST /api/v1/org/{orgId}/master-menu/products
func (m *Module) handleCreateMasterProduct(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	info, ok := m.hqOnly(w, r, orgID)
	if !ok {
		return
	}
	tid, err := m.ensureMasterTenant(r.Context(), orgID, info.UserID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to ensure master tenant")
		return
	}

	var req struct {
		CategoryID      string  `json:"category_id"`
		Name            string  `json:"name"`
		Description     *string `json:"description"`
		Price           int64   `json:"price"`
		CostPrice       int64   `json:"cost_price"`
		TaxGroup        string  `json:"tax_group"`
		ImagePath       *string `json:"image_path"`
		Barcode         *string `json:"barcode"`
		IsActive        *bool   `json:"is_active"`
		DisplayOrder    int     `json:"display_order"`
		PrepTimeMinutes *int    `json:"prep_time_minutes"`
		PrinterGroup    string  `json:"printer_group"`
		DefaultGang     *int    `json:"default_gang"`

		// Optional inline policy creation:
		LockType *string `json:"lock_type,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.Name == "" || req.CategoryID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "name and category_id are required")
		return
	}
	if req.TaxGroup == "" {
		req.TaxGroup = "default"
	}
	if req.PrinterGroup == "" {
		req.PrinterGroup = "kitchen"
	}
	active := true
	if req.IsActive != nil {
		active = *req.IsActive
	}

	id := uuid.New()
	now := time.Now().UTC()
	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to start transaction")
		return
	}
	defer tx.Rollback()

	if _, err := tx.ExecContext(r.Context(), `
		INSERT INTO products (
		  id, tenant_id, category_id, name, description, price, cost_price,
		  tax_group, image_path, barcode, is_active, display_order,
		  prep_time_minutes, printer_group, default_gang,
		  created_at, updated_at, sync_status, is_deleted
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$16,0,FALSE)
	`, id, tid, req.CategoryID, req.Name,
		nullableStr(req.Description), req.Price, req.CostPrice,
		req.TaxGroup, nullableStr(req.ImagePath), nullableStr(req.Barcode),
		active, req.DisplayOrder,
		nullableInt(req.PrepTimeMinutes), req.PrinterGroup,
		nullableInt(req.DefaultGang), now); err != nil {
		slog.Error("org/master-menu: create product", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create product")
		return
	}

	if req.LockType != nil && ValidLockTypes[*req.LockType] {
		if _, err := tx.ExecContext(r.Context(), `
			INSERT INTO menu_policies (id, organization_id, product_id, lock_type, allow_local_additions, allow_local_disable, created_at, updated_at)
			VALUES (gen_random_uuid(), $1, $2, $3, TRUE, TRUE, NOW(), NOW())
			ON CONFLICT (organization_id, product_id) DO UPDATE SET lock_type = EXCLUDED.lock_type, updated_at = NOW()
		`, orgID, id, *req.LockType); err != nil {
			slog.Error("org/master-menu: inline policy", "error", err)
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create inline policy")
			return
		}
	}

	if err := tx.Commit(); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to commit")
		return
	}

	response.Created(w, map[string]any{"id": id, "tenant_id": tid, "organization_id": orgID})
}

// PUT /api/v1/org/{orgId}/master-menu/products/{id}
func (m *Module) handleUpdateMasterProduct(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	if _, ok := m.hqOnly(w, r, orgID); !ok {
		return
	}
	tid, err := m.masterTenantID(r.Context(), orgID)
	if err != nil {
		response.Error(w, http.StatusNotFound, "NO_MASTER", "Master tenant not configured")
		return
	}
	id := r.PathValue("id")
	if !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_ID", "Invalid id")
		return
	}

	var req struct {
		CategoryID      string  `json:"category_id"`
		Name            string  `json:"name"`
		Description     *string `json:"description"`
		Price           int64   `json:"price"`
		CostPrice       int64   `json:"cost_price"`
		TaxGroup        string  `json:"tax_group"`
		ImagePath       *string `json:"image_path"`
		IsActive        bool    `json:"is_active"`
		DisplayOrder    int     `json:"display_order"`
		PrepTimeMinutes *int    `json:"prep_time_minutes"`
		DefaultGang     *int    `json:"default_gang"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	res, err := m.db.ExecContext(r.Context(), `
		UPDATE products SET
		  name=$1, description=$2, price=$3, cost_price=$4, tax_group=$5,
		  image_path=$6, is_active=$7, display_order=$8,
		  prep_time_minutes=$9, category_id=$10, default_gang=$11, updated_at=NOW()
		WHERE id=$12 AND tenant_id=$13 AND is_deleted=FALSE
	`, req.Name, nullableStr(req.Description), req.Price, req.CostPrice, req.TaxGroup,
		nullableStr(req.ImagePath), req.IsActive, req.DisplayOrder,
		nullableInt(req.PrepTimeMinutes), req.CategoryID, nullableInt(req.DefaultGang),
		id, tid)
	if err != nil {
		slog.Error("org/master-menu: update product", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update product")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Product not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"id": id, "status": "updated"})
}

// DELETE /api/v1/org/{orgId}/master-menu/products/{id}
func (m *Module) handleDeleteMasterProduct(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	if _, ok := m.hqOnly(w, r, orgID); !ok {
		return
	}
	tid, err := m.masterTenantID(r.Context(), orgID)
	if err != nil {
		response.Error(w, http.StatusNotFound, "NO_MASTER", "Master tenant not configured")
		return
	}
	id := r.PathValue("id")
	if !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_ID", "Invalid id")
		return
	}

	res, err := m.db.ExecContext(r.Context(), `
		UPDATE products SET is_deleted=TRUE, updated_at=NOW()
		WHERE id=$1 AND tenant_id=$2 AND is_deleted=FALSE
	`, id, tid)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete product")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Product not found")
		return
	}
	response.NoContent(w)
}

// nullableStr converts a *string to nil when nil/empty. Mirrors the helper
// in the menu module, kept package-local to avoid cross-module imports.
func nullableStr(s *string) any {
	if s == nil || *s == "" {
		return nil
	}
	return *s
}

// nullableInt converts a *int to nil when nil.
func nullableInt(n *int) any {
	if n == nil {
		return nil
	}
	return *n
}
