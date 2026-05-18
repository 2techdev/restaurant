package loyalty

import (
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

// generateCode produces a GC-XXXX-XXXX style human-shareable code.
// Uses crypto/rand against an unambiguous alphabet (no 0/O/1/I/L).
const codeAlphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"

func generateGiftCardCode() (string, error) {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	var sb strings.Builder
	sb.WriteString("GC-")
	for i, v := range b {
		if i == 4 {
			sb.WriteByte('-')
		}
		sb.WriteByte(codeAlphabet[int(v)%len(codeAlphabet)])
	}
	return sb.String(), nil
}

func (m *Module) generateUniqueCode(r *http.Request) (string, error) {
	for attempt := 0; attempt < 8; attempt++ {
		code, err := generateGiftCardCode()
		if err != nil {
			return "", err
		}
		var existing string
		err = m.db.QueryRowContext(r.Context(),
			`SELECT id FROM gift_cards WHERE code = $1`, code).Scan(&existing)
		if errors.Is(err, sql.ErrNoRows) {
			return code, nil
		}
		if err != nil {
			return "", err
		}
	}
	return "", fmt.Errorf("could not generate unique gift card code after retries")
}

func canManageGiftCards(role string) bool {
	switch role {
	case "OWNER", "MANAGER", "HQ_ADMIN", "HQ_MANAGER":
		return true
	}
	return false
}

// ---------------------------------------------------------------------------
// GET /api/v1/giftcards
// ---------------------------------------------------------------------------

func (m *Module) handleListGiftCards(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	statusFilter := r.URL.Query().Get("status")
	q := `
		SELECT id, tenant_id, code, denomination_cents, balance_cents,
		       issued_to_customer_id, issued_by_user_id, issued_at, expires_at,
		       status, notes, created_at, updated_at
		FROM gift_cards
		WHERE tenant_id = $1
	`
	args := []any{tenantID}
	if statusFilter != "" {
		q += ` AND status = $2`
		args = append(args, statusFilter)
	}
	q += ` ORDER BY issued_at DESC LIMIT 500`
	rows, err := m.db.QueryContext(r.Context(), q, args...)
	if err != nil {
		slog.Error("loyalty: list gift cards", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list gift cards")
		return
	}
	defer rows.Close()
	out := make([]GiftCard, 0)
	for rows.Next() {
		var g GiftCard
		var custID, byUser, notes sql.NullString
		if err := rows.Scan(&g.ID, &g.TenantID, &g.Code, &g.DenominationCents, &g.BalanceCents,
			&custID, &byUser, &g.IssuedAt, &g.ExpiresAt, &g.Status, &notes,
			&g.CreatedAt, &g.UpdatedAt); err != nil {
			continue
		}
		if custID.Valid {
			g.IssuedToCustomerID = &custID.String
		}
		if byUser.Valid {
			g.IssuedByUserID = &byUser.String
		}
		if notes.Valid {
			g.Notes = &notes.String
		}
		out = append(out, g)
	}
	response.JSON(w, http.StatusOK, map[string]any{"giftcards": out})
}

// ---------------------------------------------------------------------------
// GET /api/v1/giftcards/{code}
//   ?balance — returns just balance (POS-friendly compact)
// ---------------------------------------------------------------------------

func (m *Module) handleGetGiftCard(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	code := strings.ToUpper(r.PathValue("code"))
	g, err := m.loadGiftCard(r, tenantID, code)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			response.Error(w, http.StatusNotFound, "NOT_FOUND", "Gift card not found")
			return
		}
		slog.Error("loyalty: get gift card", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load gift card")
		return
	}
	if _, ok := r.URL.Query()["balance"]; ok {
		response.JSON(w, http.StatusOK, map[string]any{
			"code":          g.Code,
			"balance_cents": g.BalanceCents,
			"status":        g.Status,
			"expires_at":    g.ExpiresAt,
		})
		return
	}
	response.JSON(w, http.StatusOK, g)
}

func (m *Module) loadGiftCard(r *http.Request, tenantID, code string) (*GiftCard, error) {
	var g GiftCard
	var custID, byUser, notes sql.NullString
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, code, denomination_cents, balance_cents,
		       issued_to_customer_id, issued_by_user_id, issued_at, expires_at,
		       status, notes, created_at, updated_at
		FROM gift_cards
		WHERE tenant_id = $1 AND code = $2
	`, tenantID, code).Scan(&g.ID, &g.TenantID, &g.Code, &g.DenominationCents, &g.BalanceCents,
		&custID, &byUser, &g.IssuedAt, &g.ExpiresAt, &g.Status, &notes, &g.CreatedAt, &g.UpdatedAt)
	if err != nil {
		return nil, err
	}
	if custID.Valid {
		g.IssuedToCustomerID = &custID.String
	}
	if byUser.Valid {
		g.IssuedByUserID = &byUser.String
	}
	if notes.Valid {
		g.Notes = &notes.String
	}
	return &g, nil
}

// ---------------------------------------------------------------------------
// POST /api/v1/giftcards
// ---------------------------------------------------------------------------

func (m *Module) handleIssueGiftCard(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" || !canManageGiftCards(middleware.GetRole(r.Context())) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
		return
	}
	var req IssueGiftCardRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if req.DenominationCents <= 0 {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "denomination_cents must be positive")
		return
	}
	expires := time.Now().UTC().AddDate(5, 0, 0) // Swiss legal min — 5 years
	if req.ExpiresAt != nil {
		// Cap to 5 years if shorter offered? Swiss law: consumer can demand 5 years.
		// Keep operator's value if longer, else default.
		if req.ExpiresAt.After(expires) {
			expires = *req.ExpiresAt
		}
	}
	g, err := m.createGiftCard(r, tenantID, req.DenominationCents, req.IssuedToCustomerID, req.Notes, expires)
	if err != nil {
		slog.Error("loyalty: issue gift card", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to issue gift card")
		return
	}
	response.Created(w, g)
}

func (m *Module) createGiftCard(r *http.Request, tenantID string, denomCents int64,
	customerID *string, notes *string, expires time.Time) (*GiftCard, error) {

	code, err := m.generateUniqueCode(r)
	if err != nil {
		return nil, err
	}
	id := uuid.New()
	byUser := middleware.GetUserID(r.Context())
	now := time.Now().UTC()

	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()

	if _, err := tx.ExecContext(r.Context(), `
		INSERT INTO gift_cards
		  (id, tenant_id, code, denomination_cents, balance_cents,
		   issued_to_customer_id, issued_by_user_id, issued_at, expires_at,
		   status, notes, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$4, $5,$6,$7,$8,'active',$9,$7,$7)
	`, id, tenantID, code, denomCents, customerID, nullable(byUser), now, expires, notes); err != nil {
		return nil, err
	}
	if _, err := tx.ExecContext(r.Context(), `
		INSERT INTO gift_card_transactions
		  (id, gift_card_id, tenant_id, type, amount_cents, balance_after_cents,
		   description, created_by_user_id, created_at)
		VALUES ($1,$2,$3,'issue',$4,$4,'Initial issuance',$5,$6)
	`, uuid.New(), id, tenantID, denomCents, nullable(byUser), now); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return &GiftCard{
		ID: id, TenantID: tenantID, Code: code,
		DenominationCents: denomCents, BalanceCents: denomCents,
		IssuedToCustomerID: customerID, IssuedByUserID: nullableStr(byUser),
		IssuedAt: now, ExpiresAt: expires, Status: "active",
		Notes: notes, CreatedAt: now, UpdatedAt: now,
	}, nil
}

func nullableStr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// ---------------------------------------------------------------------------
// POST /api/v1/giftcards/bulk
// ---------------------------------------------------------------------------

func (m *Module) handleBulkIssueGiftCards(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" || !canManageGiftCards(middleware.GetRole(r.Context())) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
		return
	}
	var req BulkIssueGiftCardsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if req.Quantity <= 0 || req.Quantity > 500 || req.DenominationCents <= 0 {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "quantity 1..500 and positive denomination required")
		return
	}
	expires := time.Now().UTC().AddDate(5, 0, 0)
	if req.ExpiresAt != nil && req.ExpiresAt.After(expires) {
		expires = *req.ExpiresAt
	}
	out := make([]*GiftCard, 0, req.Quantity)
	for i := 0; i < req.Quantity; i++ {
		g, err := m.createGiftCard(r, tenantID, req.DenominationCents, nil, req.Notes, expires)
		if err != nil {
			slog.Error("loyalty: bulk issue gift card", "error", err)
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed mid-bulk; some cards may have been created")
			return
		}
		out = append(out, g)
	}
	response.JSON(w, http.StatusCreated, map[string]any{"giftcards": out})
}

// ---------------------------------------------------------------------------
// POST /api/v1/giftcards/{code}/redeem
// ---------------------------------------------------------------------------

func (m *Module) handleRedeemGiftCard(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	code := strings.ToUpper(r.PathValue("code"))
	var req RedeemGiftCardRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if req.AmountCents <= 0 {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "amount_cents must be positive")
		return
	}

	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to begin tx")
		return
	}
	defer func() { _ = tx.Rollback() }()

	var id string
	var balance int64
	var status string
	var expiresAt time.Time
	err = tx.QueryRowContext(r.Context(), `
		SELECT id, balance_cents, status, expires_at FROM gift_cards
		WHERE tenant_id = $1 AND code = $2 FOR UPDATE
	`, tenantID, code).Scan(&id, &balance, &status, &expiresAt)
	if errors.Is(err, sql.ErrNoRows) {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Gift card not found")
		return
	}
	if err != nil {
		slog.Error("loyalty: redeem giftcard — lock", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to lock gift card")
		return
	}
	if status != "active" {
		response.Error(w, http.StatusConflict, "NOT_ACTIVE", "Gift card is "+status)
		return
	}
	if time.Now().After(expiresAt) {
		_, _ = tx.ExecContext(r.Context(),
			`UPDATE gift_cards SET status='expired', updated_at=NOW() WHERE id=$1`, id)
		_ = tx.Commit()
		response.Error(w, http.StatusConflict, "EXPIRED", "Gift card has expired")
		return
	}
	if req.AmountCents > balance {
		response.Error(w, http.StatusBadRequest, "INSUFFICIENT_BALANCE",
			fmt.Sprintf("Requested %d cents exceeds balance %d", req.AmountCents, balance))
		return
	}
	newBalance := balance - req.AmountCents
	newStatus := status
	if newBalance == 0 {
		newStatus = "redeemed"
	}
	now := time.Now().UTC()
	if _, err := tx.ExecContext(r.Context(), `
		UPDATE gift_cards SET balance_cents = $1, status = $2, updated_at = NOW()
		WHERE id = $3
	`, newBalance, newStatus, id); err != nil {
		slog.Error("loyalty: redeem giftcard — update", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update gift card")
		return
	}
	byUser := middleware.GetUserID(r.Context())
	if _, err := tx.ExecContext(r.Context(), `
		INSERT INTO gift_card_transactions
		  (id, gift_card_id, tenant_id, type, amount_cents, order_id, balance_after_cents,
		   description, created_by_user_id, created_at)
		VALUES ($1,$2,$3,'redeem',$4,$5,$6,$7,$8,$9)
	`, uuid.New(), id, tenantID, -req.AmountCents, req.OrderID, newBalance,
		req.Description, nullable(byUser), now); err != nil {
		slog.Error("loyalty: redeem giftcard — tx insert", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to record transaction")
		return
	}
	if err := tx.Commit(); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to commit")
		return
	}
	response.JSON(w, http.StatusOK, map[string]any{
		"code":          code,
		"redeemed":      req.AmountCents,
		"balance_cents": newBalance,
		"status":        newStatus,
	})
}

// ---------------------------------------------------------------------------
// POST /api/v1/giftcards/{code}/refund — credit back to card (e.g. order cancel)
// ---------------------------------------------------------------------------

func (m *Module) handleRefundGiftCard(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" || !canManageGiftCards(middleware.GetRole(r.Context())) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
		return
	}
	code := strings.ToUpper(r.PathValue("code"))
	var req RefundGiftCardRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if req.AmountCents <= 0 {
		response.Error(w, http.StatusBadRequest, "INVALID_INPUT", "amount_cents must be positive")
		return
	}

	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to begin tx")
		return
	}
	defer func() { _ = tx.Rollback() }()

	var id string
	var balance, denom int64
	var status string
	err = tx.QueryRowContext(r.Context(), `
		SELECT id, balance_cents, denomination_cents, status FROM gift_cards
		WHERE tenant_id = $1 AND code = $2 FOR UPDATE
	`, tenantID, code).Scan(&id, &balance, &denom, &status)
	if errors.Is(err, sql.ErrNoRows) {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Gift card not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to lock gift card")
		return
	}
	if status == "voided" {
		response.Error(w, http.StatusConflict, "VOIDED", "Cannot refund a voided card")
		return
	}
	newBalance := balance + req.AmountCents
	if newBalance > denom {
		response.Error(w, http.StatusBadRequest, "EXCEEDS_DENOMINATION",
			"Refund would exceed original denomination")
		return
	}
	if _, err := tx.ExecContext(r.Context(), `
		UPDATE gift_cards SET balance_cents = $1, status = 'active', updated_at = NOW()
		WHERE id = $2
	`, newBalance, id); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update gift card")
		return
	}
	byUser := middleware.GetUserID(r.Context())
	if _, err := tx.ExecContext(r.Context(), `
		INSERT INTO gift_card_transactions
		  (id, gift_card_id, tenant_id, type, amount_cents, order_id, balance_after_cents,
		   description, created_by_user_id, created_at)
		VALUES ($1,$2,$3,'refund',$4,$5,$6,$7,$8,NOW())
	`, uuid.New(), id, tenantID, req.AmountCents, req.OrderID, newBalance,
		req.Description, nullable(byUser)); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to record transaction")
		return
	}
	if err := tx.Commit(); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to commit")
		return
	}
	response.JSON(w, http.StatusOK, map[string]any{
		"code":          code,
		"refunded":      req.AmountCents,
		"balance_cents": newBalance,
		"status":        "active",
	})
}

// ---------------------------------------------------------------------------
// PATCH /api/v1/giftcards/{code}/void
// ---------------------------------------------------------------------------

func (m *Module) handleVoidGiftCard(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" || !canManageGiftCards(middleware.GetRole(r.Context())) {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
		return
	}
	code := strings.ToUpper(r.PathValue("code"))
	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to begin tx")
		return
	}
	defer func() { _ = tx.Rollback() }()

	var id string
	var balance int64
	var status string
	err = tx.QueryRowContext(r.Context(), `
		SELECT id, balance_cents, status FROM gift_cards
		WHERE tenant_id = $1 AND code = $2 FOR UPDATE
	`, tenantID, code).Scan(&id, &balance, &status)
	if errors.Is(err, sql.ErrNoRows) {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Gift card not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to lock gift card")
		return
	}
	if status == "voided" {
		response.NoContent(w)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `
		UPDATE gift_cards SET status = 'voided', updated_at = NOW() WHERE id = $1
	`, id); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to void gift card")
		return
	}
	byUser := middleware.GetUserID(r.Context())
	if _, err := tx.ExecContext(r.Context(), `
		INSERT INTO gift_card_transactions
		  (id, gift_card_id, tenant_id, type, amount_cents, balance_after_cents,
		   description, created_by_user_id, created_at)
		VALUES ($1,$2,$3,'void',$4,$5,'Voided by operator',$6,NOW())
	`, uuid.New(), id, tenantID, -balance, 0, nullable(byUser)); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to record transaction")
		return
	}
	if err := tx.Commit(); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to commit")
		return
	}
	response.NoContent(w)
}
