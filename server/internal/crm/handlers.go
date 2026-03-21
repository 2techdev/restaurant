package crm

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

// handleListCustomers returns paginated customers for a tenant.
// GET /api/v1/crm/customers?tenant_id=&search=&cursor=&limit=
func (m *Module) handleListCustomers(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	tenantID := q.Get("tenant_id")
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}
	search := q.Get("search")
	limit := 50
	if l := q.Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 && n <= 200 {
			limit = n
		}
	}
	cursor := q.Get("cursor")

	var cursorTime time.Time
	if cursor != "" {
		if t, err := time.Parse(time.RFC3339Nano, cursor); err == nil {
			cursorTime = t
		}
	}

	query := `
		SELECT id, tenant_id, name, phone, email, birthday, notes,
		       loyalty_points, total_visits, total_spent_cents, last_visit_at,
		       created_at, updated_at, is_deleted
		FROM customers
		WHERE tenant_id = $1
		  AND is_deleted = false
		  AND ($2 = '' OR name ILIKE '%' || $2 || '%' OR phone ILIKE '%' || $2 || '%')
		  AND created_at > $3
		ORDER BY created_at ASC
		LIMIT $4
	`

	rows, err := m.db.QueryContext(r.Context(), query, tenantID, search, cursorTime, limit+1)
	if err != nil {
		slog.Error("crm: list customers", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to query customers")
		return
	}
	defer rows.Close()

	customers := make([]Customer, 0)
	for rows.Next() {
		var c Customer
		var phone, email, birthday, notes sql.NullString
		var lastVisit sql.NullTime
		if err := rows.Scan(
			&c.ID, &c.TenantID, &c.Name, &phone, &email, &birthday, &notes,
			&c.LoyaltyPoints, &c.TotalVisits, &c.TotalSpentCents, &lastVisit,
			&c.CreatedAt, &c.UpdatedAt, &c.IsDeleted,
		); err != nil {
			slog.Error("crm: scan customer", "error", err)
			continue
		}
		if phone.Valid {
			c.Phone = &phone.String
		}
		if email.Valid {
			c.Email = &email.String
		}
		if birthday.Valid {
			c.Birthday = &birthday.String
		}
		if notes.Valid {
			c.Notes = &notes.String
		}
		if lastVisit.Valid {
			c.LastVisitAt = &lastVisit.Time
		}
		customers = append(customers, c)
	}
	if err := rows.Err(); err != nil {
		slog.Error("crm: rows error", "error", err)
	}

	hasMore := len(customers) > limit
	if hasMore {
		customers = customers[:limit]
	}
	nextCursor := ""
	if hasMore && len(customers) > 0 {
		nextCursor = customers[len(customers)-1].CreatedAt.UTC().Format(time.RFC3339Nano)
	}

	response.Paginated(w, customers, nextCursor, hasMore)
}

// handleCreateCustomer creates a new customer record.
// POST /api/v1/crm/customers
func (m *Module) handleCreateCustomer(w http.ResponseWriter, r *http.Request) {
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	var req CreateCustomerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_body", "invalid JSON")
		return
	}
	if req.Name == "" {
		response.Error(w, http.StatusBadRequest, "validation_error", "name required")
		return
	}
	if req.ID == "" {
		response.Error(w, http.StatusBadRequest, "validation_error", "id required")
		return
	}

	now := time.Now().UTC()
	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO customers (id, tenant_id, name, phone, email, birthday, notes,
		                       loyalty_points, total_visits, total_spent_cents,
		                       created_at, updated_at, is_deleted)
		VALUES ($1,$2,$3,$4,$5,$6,$7, 0, 0, 0, $8, $8, false)
		ON CONFLICT (id) DO NOTHING
	`, req.ID, tenantID, req.Name, req.Phone, req.Email, req.Birthday, req.Notes, now)
	if err != nil {
		slog.Error("crm: create customer", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to create customer")
		return
	}

	m.publishSyncEvent(r.Context(), tenantID, "customers", req.ID, "insert", req)

	customer := Customer{
		ID:        req.ID,
		TenantID:  tenantID,
		Name:      req.Name,
		Phone:     req.Phone,
		Email:     req.Email,
		Birthday:  req.Birthday,
		Notes:     req.Notes,
		CreatedAt: now,
		UpdatedAt: now,
	}
	response.Created(w, customer)
}

// handleGetCustomer returns a single customer by ID.
// GET /api/v1/crm/customers/{id}
func (m *Module) handleGetCustomer(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	var c Customer
	var phone, email, birthday, notes sql.NullString
	var lastVisit sql.NullTime
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, name, phone, email, birthday, notes,
		       loyalty_points, total_visits, total_spent_cents, last_visit_at,
		       created_at, updated_at, is_deleted
		FROM customers
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID).Scan(
		&c.ID, &c.TenantID, &c.Name, &phone, &email, &birthday, &notes,
		&c.LoyaltyPoints, &c.TotalVisits, &c.TotalSpentCents, &lastVisit,
		&c.CreatedAt, &c.UpdatedAt, &c.IsDeleted,
	)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "not_found", "customer not found")
		return
	}
	if err != nil {
		slog.Error("crm: get customer", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to get customer")
		return
	}
	if phone.Valid {
		c.Phone = &phone.String
	}
	if email.Valid {
		c.Email = &email.String
	}
	if birthday.Valid {
		c.Birthday = &birthday.String
	}
	if notes.Valid {
		c.Notes = &notes.String
	}
	if lastVisit.Valid {
		c.LastVisitAt = &lastVisit.Time
	}

	response.JSON(w, http.StatusOK, c)
}

// handleUpdateCustomer updates an existing customer.
// PUT /api/v1/crm/customers/{id}
func (m *Module) handleUpdateCustomer(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	var req UpdateCustomerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_body", "invalid JSON")
		return
	}

	now := time.Now().UTC()
	result, err := m.db.ExecContext(r.Context(), `
		UPDATE customers
		SET name     = COALESCE($3, name),
		    phone    = COALESCE($4, phone),
		    email    = COALESCE($5, email),
		    birthday = COALESCE($6, birthday),
		    notes    = COALESCE($7, notes),
		    updated_at = $8
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID, req.Name, req.Phone, req.Email, req.Birthday, req.Notes, now)
	if err != nil {
		slog.Error("crm: update customer", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to update customer")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "not_found", "customer not found")
		return
	}

	m.publishSyncEvent(r.Context(), tenantID, "customers", id, "update", req)
	response.NoContent(w)
}

// handleDeleteCustomer soft-deletes a customer.
// DELETE /api/v1/crm/customers/{id}
func (m *Module) handleDeleteCustomer(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	now := time.Now().UTC()
	result, err := m.db.ExecContext(r.Context(), `
		UPDATE customers SET is_deleted = true, updated_at = $3
		WHERE id = $1 AND tenant_id = $2
	`, id, tenantID, now)
	if err != nil {
		slog.Error("crm: delete customer", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to delete customer")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "not_found", "customer not found")
		return
	}

	m.publishSyncEvent(r.Context(), tenantID, "customers", id, "delete", map[string]string{"id": id})
	response.NoContent(w)
}

// handleAddLoyalty records a loyalty transaction and updates the customer's balance.
// POST /api/v1/crm/customers/{id}/loyalty
func (m *Module) handleAddLoyalty(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	var req LoyaltyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_body", "invalid JSON")
		return
	}
	if req.ID == "" {
		response.Error(w, http.StatusBadRequest, "validation_error", "id required")
		return
	}
	if req.Type != "earn" && req.Type != "redeem" && req.Type != "adjust" {
		response.Error(w, http.StatusBadRequest, "validation_error", "type must be earn, redeem, or adjust")
		return
	}

	now := time.Now().UTC()
	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to begin transaction")
		return
	}
	defer tx.Rollback()

	// Insert loyalty transaction
	_, err = tx.ExecContext(r.Context(), `
		INSERT INTO loyalty_transactions (id, tenant_id, customer_id, points, type, description, ticket_id, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
		ON CONFLICT (id) DO NOTHING
	`, req.ID, tenantID, id, req.Points, req.Type, req.Description, req.TicketID, now)
	if err != nil {
		slog.Error("crm: insert loyalty tx", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to record loyalty transaction")
		return
	}

	// Update customer balance + visit count
	var visitIncr int
	if req.Type == "earn" {
		visitIncr = 1
	}
	_, err = tx.ExecContext(r.Context(), `
		UPDATE customers
		SET loyalty_points = loyalty_points + $3,
		    total_visits   = total_visits + $4,
		    last_visit_at  = CASE WHEN $4 > 0 THEN $5 ELSE last_visit_at END,
		    updated_at     = $5
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID, req.Points, visitIncr, now)
	if err != nil {
		slog.Error("crm: update loyalty balance", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to update loyalty balance")
		return
	}

	if err := tx.Commit(); err != nil {
		slog.Error("crm: commit loyalty tx", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "transaction commit failed")
		return
	}

	m.publishSyncEvent(r.Context(), tenantID, "loyalty_transactions", req.ID, "insert", req)

	txn := LoyaltyTransaction{
		ID:          req.ID,
		TenantID:    tenantID,
		CustomerID:  id,
		Points:      req.Points,
		Type:        req.Type,
		Description: req.Description,
		TicketID:    req.TicketID,
		CreatedAt:   now,
	}
	response.Created(w, txn)
}

// handleListLoyalty returns loyalty transaction history for a customer.
// GET /api/v1/crm/customers/{id}/loyalty
func (m *Module) handleListLoyalty(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, customer_id, points, type, description, ticket_id, created_at
		FROM loyalty_transactions
		WHERE customer_id = $1 AND tenant_id = $2
		ORDER BY created_at DESC
		LIMIT 100
	`, id, tenantID)
	if err != nil {
		slog.Error("crm: list loyalty", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to query loyalty")
		return
	}
	defer rows.Close()

	txns := make([]LoyaltyTransaction, 0)
	for rows.Next() {
		var t LoyaltyTransaction
		var desc, ticketID sql.NullString
		if err := rows.Scan(
			&t.ID, &t.TenantID, &t.CustomerID, &t.Points, &t.Type,
			&desc, &ticketID, &t.CreatedAt,
		); err != nil {
			continue
		}
		if desc.Valid {
			t.Description = &desc.String
		}
		if ticketID.Valid {
			t.TicketID = &ticketID.String
		}
		txns = append(txns, t)
	}

	response.JSON(w, http.StatusOK, txns)
}
