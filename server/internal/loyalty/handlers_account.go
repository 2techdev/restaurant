package loyalty

import (
	"database/sql"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

// ---------------------------------------------------------------------------
// GET /api/v1/loyalty/account/{customer_id}
// ---------------------------------------------------------------------------

func (m *Module) handleAccount(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	customerID := r.PathValue("customer_id")
	if customerID == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "customer_id required")
		return
	}

	var acc Account
	var tier sql.NullString
	var upgradeAt sql.NullTime
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, name, loyalty_points, total_earned, current_tier, tier_upgrade_at
		FROM customers
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, customerID, tenantID).Scan(&acc.CustomerID, &acc.Name, &acc.Points, &acc.TotalEarned, &tier, &upgradeAt)
	if errors.Is(err, sql.ErrNoRows) {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Customer not found")
		return
	}
	if err != nil {
		slog.Error("loyalty: account select", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load account")
		return
	}
	if tier.Valid {
		acc.CurrentTier = &tier.String
	}
	if upgradeAt.Valid {
		acc.TierUpgradeAt = &upgradeAt.Time
	}

	// Next tier preview — first tier with min_points > current points.
	var nextCode string
	var nextMin int
	err = m.db.QueryRowContext(r.Context(), `
		SELECT code, min_points FROM loyalty_tiers
		WHERE tenant_id = $1 AND is_active = true AND min_points > $2
		ORDER BY min_points ASC LIMIT 1
	`, tenantID, acc.TotalEarned).Scan(&nextCode, &nextMin)
	if err == nil {
		delta := nextMin - acc.TotalEarned
		acc.NextTier = &nextCode
		acc.PointsToNext = &delta
	}

	response.JSON(w, http.StatusOK, acc)
}

// ---------------------------------------------------------------------------
// POST /api/v1/loyalty/earn
// ---------------------------------------------------------------------------

// computeTier picks the right tier code for a given total_earned snapshot.
// Tiers are matched by [min_points, max_points] window; tier with NULL max is
// the top-end fallback.
func (m *Module) computeTier(r *http.Request, tenantID string, totalEarned int) (string, error) {
	var code string
	err := m.db.QueryRowContext(r.Context(), `
		SELECT code FROM loyalty_tiers
		WHERE tenant_id = $1 AND is_active = true
		  AND min_points <= $2
		  AND (max_points IS NULL OR max_points >= $2)
		ORDER BY min_points DESC LIMIT 1
	`, tenantID, totalEarned).Scan(&code)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	return code, err
}

// activeBonusMultiplier returns the highest currently-active bonus multiplier,
// or 1.0 if none. Also returns the campaign id when applied.
func (m *Module) activeBonusMultiplier(r *http.Request, tenantID string) (float64, *string) {
	var id string
	var mult float64
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, multiplier FROM loyalty_bonus_campaigns
		WHERE tenant_id = $1 AND is_active = true
		  AND starts_at <= NOW() AND ends_at >= NOW()
		ORDER BY multiplier DESC LIMIT 1
	`, tenantID).Scan(&id, &mult)
	if err != nil {
		return 1.0, nil
	}
	return mult, &id
}

func (m *Module) handleEarn(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	var req EarnRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if req.CustomerID == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "customer_id required")
		return
	}
	if req.Points == nil && req.AmountCents <= 0 {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "points or amount_cents required")
		return
	}

	settings, err := m.loadSettings(r, tenantID)
	if err != nil {
		slog.Error("loyalty: earn — load settings", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load settings")
		return
	}
	if !settings.IsEnabled {
		response.Error(w, http.StatusForbidden, "DISABLED", "Loyalty program is disabled for this tenant")
		return
	}

	// Resolve tier-aware earn rate.
	multiplier := 1.0
	if req.Points == nil {
		// Pre-fetch current tier multiplier for this customer.
		var totalEarned int
		_ = m.db.QueryRowContext(r.Context(),
			`SELECT total_earned FROM customers WHERE id=$1 AND tenant_id=$2`,
			req.CustomerID, tenantID).Scan(&totalEarned)
		code, _ := m.computeTier(r, tenantID, totalEarned)
		if code != "" {
			_ = m.db.QueryRowContext(r.Context(),
				`SELECT multiplier FROM loyalty_tiers WHERE tenant_id=$1 AND code=$2`,
				tenantID, code).Scan(&multiplier)
		}
	}
	bonusMult, bonusID := m.activeBonusMultiplier(r, tenantID)
	multiplier *= bonusMult

	var points int
	if req.Points != nil {
		points = *req.Points
	} else {
		chf := float64(req.AmountCents) / 100.0
		points = int(chf * settings.EarnRatePointsPerCHF * multiplier)
	}
	if points <= 0 {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "Computed points must be positive")
		return
	}

	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to begin tx")
		return
	}
	defer func() { _ = tx.Rollback() }()

	// Lock customer row + read current tier.
	var balance, totalEarned int
	var tierBefore sql.NullString
	err = tx.QueryRowContext(r.Context(), `
		SELECT loyalty_points, total_earned, current_tier
		FROM customers WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
		FOR UPDATE
	`, req.CustomerID, tenantID).Scan(&balance, &totalEarned, &tierBefore)
	if errors.Is(err, sql.ErrNoRows) {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Customer not found")
		return
	}
	if err != nil {
		slog.Error("loyalty: earn — lock customer", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to lock customer")
		return
	}

	newBalance := balance + points
	newTotalEarned := totalEarned + points
	tierAfter, _ := m.computeTier(r, tenantID, newTotalEarned)

	desc := "earn"
	if req.Description != nil {
		desc = *req.Description
	}
	now := time.Now().UTC()
	var ticketID *string
	if req.OrderID != "" {
		ticketID = &req.OrderID
	}
	if _, err := tx.ExecContext(r.Context(), `
		INSERT INTO loyalty_transactions (id, tenant_id, customer_id, points, type, description, ticket_id, created_at)
		VALUES ($1, $2, $3, $4, 'earn', $5, $6, $7)
	`, uuid.New(), tenantID, req.CustomerID, points, desc, ticketID, now); err != nil {
		slog.Error("loyalty: earn — insert tx", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to record transaction")
		return
	}

	upgraded := tierAfter != "" && (!tierBefore.Valid || tierBefore.String != tierAfter)
	var upgradeAt any = nil
	if upgraded {
		upgradeAt = now
	}
	if _, err := tx.ExecContext(r.Context(), `
		UPDATE customers
		SET loyalty_points = $1,
		    total_earned = $2,
		    current_tier = COALESCE($3, current_tier),
		    tier_upgrade_at = COALESCE($4::timestamptz, tier_upgrade_at),
		    updated_at = NOW()
		WHERE id = $5 AND tenant_id = $6
	`, newBalance, newTotalEarned, nullable(tierAfter), upgradeAt, req.CustomerID, tenantID); err != nil {
		slog.Error("loyalty: earn — update customer", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update customer")
		return
	}

	if err := tx.Commit(); err != nil {
		slog.Error("loyalty: earn — commit", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to commit")
		return
	}

	resp := EarnResponse{
		PointsEarned:    points,
		PointsBalance:   newBalance,
		TierUpgraded:    upgraded,
		MultiplierUsed:  multiplier,
		BonusCampaignID: bonusID,
	}
	if tierBefore.Valid {
		v := tierBefore.String
		resp.TierBefore = &v
	}
	if tierAfter != "" {
		resp.TierAfter = &tierAfter
	}
	response.JSON(w, http.StatusOK, resp)
}

func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// ---------------------------------------------------------------------------
// POST /api/v1/loyalty/redeem
// ---------------------------------------------------------------------------

func (m *Module) handleRedeem(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	var req RedeemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if req.CustomerID == "" || req.Points <= 0 {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "customer_id and positive points required")
		return
	}
	settings, err := m.loadSettings(r, tenantID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load settings")
		return
	}
	if !settings.IsEnabled {
		response.Error(w, http.StatusForbidden, "DISABLED", "Loyalty program is disabled")
		return
	}

	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to begin tx")
		return
	}
	defer func() { _ = tx.Rollback() }()

	var balance int
	err = tx.QueryRowContext(r.Context(), `
		SELECT loyalty_points FROM customers
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false FOR UPDATE
	`, req.CustomerID, tenantID).Scan(&balance)
	if errors.Is(err, sql.ErrNoRows) {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Customer not found")
		return
	}
	if err != nil {
		slog.Error("loyalty: redeem — lock", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to lock customer")
		return
	}
	if balance < req.Points {
		response.Error(w, http.StatusBadRequest, "INSUFFICIENT_POINTS", "Customer has insufficient points")
		return
	}

	newBalance := balance - req.Points
	desc := "redeem"
	if req.Description != nil {
		desc = *req.Description
	}
	var ticketID *string
	if req.OrderID != "" {
		ticketID = &req.OrderID
	}
	if _, err := tx.ExecContext(r.Context(), `
		INSERT INTO loyalty_transactions (id, tenant_id, customer_id, points, type, description, ticket_id, created_at)
		VALUES ($1, $2, $3, $4, 'redeem', $5, $6, NOW())
	`, uuid.New(), tenantID, req.CustomerID, -req.Points, desc, ticketID); err != nil {
		slog.Error("loyalty: redeem — insert tx", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to record transaction")
		return
	}
	if _, err := tx.ExecContext(r.Context(), `
		UPDATE customers SET loyalty_points = $1, updated_at = NOW()
		WHERE id = $2 AND tenant_id = $3
	`, newBalance, req.CustomerID, tenantID); err != nil {
		slog.Error("loyalty: redeem — update customer", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update customer")
		return
	}
	if err := tx.Commit(); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to commit")
		return
	}

	chfValue := 0.0
	if settings.RedeemRatePointsPerCHF > 0 {
		chfValue = float64(req.Points) / settings.RedeemRatePointsPerCHF
	}
	response.JSON(w, http.StatusOK, RedeemResponse{
		PointsRedeemed:   req.Points,
		PointsBalance:    newBalance,
		CHFValueRedeemed: chfValue,
	})
}
