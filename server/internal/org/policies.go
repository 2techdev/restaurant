package org

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

// ─────────────────────────────────────────────────────────────
// GET /api/v1/org/{orgId}/policies
// ─────────────────────────────────────────────────────────────
func (m *Module) handleListPolicies(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	if _, ok := m.hqOnly(w, r, orgID); !ok {
		return
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id::text, organization_id::text, product_id::text, lock_type,
		       allow_local_additions, allow_local_disable, created_at, updated_at
		FROM menu_policies WHERE organization_id = $1
		ORDER BY created_at DESC
	`, orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list policies")
		return
	}
	defer rows.Close()
	out := make([]MenuPolicy, 0)
	for rows.Next() {
		var p MenuPolicy
		if err := rows.Scan(&p.ID, &p.OrganizationID, &p.ProductID, &p.LockType,
			&p.AllowLocalAdditions, &p.AllowLocalDisable, &p.CreatedAt, &p.UpdatedAt); err == nil {
			out = append(out, p)
		}
	}
	response.JSON(w, http.StatusOK, map[string]any{"data": out})
}

// ─────────────────────────────────────────────────────────────
// POST /api/v1/org/{orgId}/policies
// ─────────────────────────────────────────────────────────────
func (m *Module) handleCreatePolicy(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	if _, ok := m.hqOnly(w, r, orgID); !ok {
		return
	}
	var req struct {
		ProductID           string `json:"product_id"`
		LockType            string `json:"lock_type"`
		AllowLocalAdditions *bool  `json:"allow_local_additions"`
		AllowLocalDisable   *bool  `json:"allow_local_disable"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if !uuid.IsValid(req.ProductID) {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "product_id must be UUID")
		return
	}
	if !ValidLockTypes[req.LockType] {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "lock_type must be one of FULLY_LOCKED, PRICE_LOCKED, FLEXIBLE")
		return
	}
	allowAdd := true
	allowDis := true
	if req.AllowLocalAdditions != nil {
		allowAdd = *req.AllowLocalAdditions
	}
	if req.AllowLocalDisable != nil {
		allowDis = *req.AllowLocalDisable
	}

	id := uuid.New()
	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO menu_policies (id, organization_id, product_id, lock_type,
		                           allow_local_additions, allow_local_disable,
		                           created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
		ON CONFLICT (organization_id, product_id) DO UPDATE
		SET lock_type = EXCLUDED.lock_type,
		    allow_local_additions = EXCLUDED.allow_local_additions,
		    allow_local_disable   = EXCLUDED.allow_local_disable,
		    updated_at = NOW()
	`, id, orgID, req.ProductID, req.LockType, allowAdd, allowDis)
	if err != nil {
		slog.Error("org/policies: create", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create policy")
		return
	}
	response.Created(w, map[string]any{
		"id":              id,
		"organization_id": orgID,
		"product_id":      req.ProductID,
		"lock_type":       req.LockType,
	})
}

// ─────────────────────────────────────────────────────────────
// PUT /api/v1/org/{orgId}/policies/{policyId}
// ─────────────────────────────────────────────────────────────
func (m *Module) handleUpdatePolicy(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	if _, ok := m.hqOnly(w, r, orgID); !ok {
		return
	}
	pid := r.PathValue("policyId")
	if !uuid.IsValid(pid) {
		response.Error(w, http.StatusBadRequest, "INVALID_ID", "Invalid policy id")
		return
	}
	var req struct {
		LockType            *string `json:"lock_type"`
		AllowLocalAdditions *bool   `json:"allow_local_additions"`
		AllowLocalDisable   *bool   `json:"allow_local_disable"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.LockType != nil && !ValidLockTypes[*req.LockType] {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "lock_type must be one of FULLY_LOCKED, PRICE_LOCKED, FLEXIBLE")
		return
	}

	res, err := m.db.ExecContext(r.Context(), `
		UPDATE menu_policies SET
		  lock_type             = COALESCE($1, lock_type),
		  allow_local_additions = COALESCE($2, allow_local_additions),
		  allow_local_disable   = COALESCE($3, allow_local_disable),
		  updated_at = NOW()
		WHERE id = $4 AND organization_id = $5
	`, req.LockType, req.AllowLocalAdditions, req.AllowLocalDisable, pid, orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update policy")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Policy not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"id": pid, "status": "updated"})
}

// ─────────────────────────────────────────────────────────────
// DELETE /api/v1/org/{orgId}/policies/{policyId}
// ─────────────────────────────────────────────────────────────
func (m *Module) handleDeletePolicy(w http.ResponseWriter, r *http.Request) {
	orgID := r.PathValue("orgId")
	if _, ok := m.hqOnly(w, r, orgID); !ok {
		return
	}
	pid := r.PathValue("policyId")
	if !uuid.IsValid(pid) {
		response.Error(w, http.StatusBadRequest, "INVALID_ID", "Invalid policy id")
		return
	}
	res, err := m.db.ExecContext(r.Context(), `
		DELETE FROM menu_policies WHERE id = $1 AND organization_id = $2
	`, pid, orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete policy")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Policy not found")
		return
	}
	response.NoContent(w)
}

// ─────────────────────────────────────────────────────────────
// Lock enforcement helper used by the regular menu module.
// ─────────────────────────────────────────────────────────────

// CheckProductMutation returns an error when the requested mutation is
// disallowed by the org's policy. Designed to be called from
// internal/menu/handlers.go before applying a tenant-level product update.
//
// It looks up the tenant's organization (via organization_memberships)
// and the matching menu_policies row. When fields is non-empty it indicates
// which fields the caller intends to change; for PRICE_LOCKED only price /
// cost_price / tax_group changes are blocked, others pass through.
//
// db is taken as an argument so the menu module can call this without
// importing the org package's Module struct.
type Mutation struct {
	ProductID    string
	TenantID     string
	ChangePrice  bool // price / cost_price / tax_group changing
	ChangeOther  bool // any other field changing (name, description, etc.)
	Disable      bool // request setting is_active = false
	Delete       bool // soft-delete request
	IsBulkInsert bool // creating a new (local) product — never master-locked
}

// LockedError implements error.
type LockedError struct {
	Code     string
	Message  string
	LockType string
}

func (e LockedError) Error() string { return e.Message }

// ErrLocked is returned for FULLY_LOCKED master products that any local
// caller tries to mutate.
var ErrLocked = LockedError{Code: "PRODUCT_LOCKED", Message: "Bu ürün HQ tarafından kilitli", LockType: LockTypeFullyLocked}

// ErrPriceLocked is returned for PRICE_LOCKED products when price/cost/tax
// changes are attempted.
var ErrPriceLocked = LockedError{Code: "PRODUCT_PRICE_LOCKED", Message: "Bu ürünün fiyatı HQ tarafından kilitli", LockType: LockTypePriceLocked}

// CheckMutation looks up the org-level policy for the given product and
// returns a LockedError when the mutation is forbidden. nil means OK.
//
// Standalone function (not a method) so the menu package can call it via:
//   org.CheckMutation(r.Context(), db, org.Mutation{...})
func CheckMutation(ctx context.Context, db *sql.DB, mu Mutation) error {
	if !uuid.IsValid(mu.ProductID) || !uuid.IsValid(mu.TenantID) {
		return nil // unknown ids, let the caller produce the right error
	}
	var orgID sql.NullString
	var isMaster sql.NullBool
	if err := db.QueryRowContext(ctx, `
		SELECT organization_id::text, is_master FROM organization_memberships WHERE tenant_id = $1 LIMIT 1
	`, mu.TenantID).Scan(&orgID, &isMaster); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil
		}
		return err
	}
	if !orgID.Valid {
		return nil
	}
	// Master tenant is the source of truth — locks don't apply to it.
	if isMaster.Valid && isMaster.Bool {
		return nil
	}

	var lockType sql.NullString
	var allowDisable sql.NullBool
	if err := db.QueryRowContext(ctx, `
		SELECT lock_type, allow_local_disable FROM menu_policies
		WHERE organization_id = $1 AND product_id = $2
	`, orgID.String, mu.ProductID).Scan(&lockType, &allowDisable); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil
		}
		return err
	}

	switch lockType.String {
	case LockTypeFullyLocked:
		// Block any mutation, including disable/delete.
		return ErrLocked
	case LockTypePriceLocked:
		if mu.Delete {
			return ErrLocked
		}
		if mu.ChangePrice {
			return ErrPriceLocked
		}
		if mu.Disable && allowDisable.Valid && !allowDisable.Bool {
			return ErrLocked
		}
		return nil
	case LockTypeFlexible:
		return nil
	default:
		return nil
	}
}
