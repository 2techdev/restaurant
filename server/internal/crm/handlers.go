package crm

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/lib/pq"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// customerColumns is the canonical column list for the customers table.
// Keep in sync with scanCustomer() below.
const customerColumns = `
	id, tenant_id, name, phone, email, birthday, anniversary, notes,
	loyalty_points, total_visits, total_spent_cents, avg_ticket_cents,
	first_visit_at, last_visit_at,
	tags, allergens, dietary_tags,
	preferred_payment_method, preferred_hour_bucket,
	favorite_category_id, favorite_product_id,
	created_at, updated_at, is_deleted
`

// rowScanner is the minimal interface shared by *sql.Row and *sql.Rows.
type rowScanner interface {
	Scan(dest ...any) error
}

// scanCustomer reads one row from a query that selects `customerColumns` in
// order, populating a Customer with proper nullability + array handling.
func scanCustomer(s rowScanner) (Customer, error) {
	var c Customer
	var phone, email, birthday, anniversary, notes sql.NullString
	var prefPayment, favCat, favProd sql.NullString
	var prefHour sql.NullInt64
	var firstVisit, lastVisit sql.NullTime
	var tags, allergens, dietary pq.StringArray

	if err := s.Scan(
		&c.ID, &c.TenantID, &c.Name, &phone, &email, &birthday, &anniversary, &notes,
		&c.LoyaltyPoints, &c.TotalVisits, &c.TotalSpentCents, &c.AvgTicketCents,
		&firstVisit, &lastVisit,
		&tags, &allergens, &dietary,
		&prefPayment, &prefHour,
		&favCat, &favProd,
		&c.CreatedAt, &c.UpdatedAt, &c.IsDeleted,
	); err != nil {
		return c, err
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
	if anniversary.Valid {
		c.Anniversary = &anniversary.String
	}
	if notes.Valid {
		c.Notes = &notes.String
	}
	if firstVisit.Valid {
		c.FirstVisitAt = &firstVisit.Time
	}
	if lastVisit.Valid {
		c.LastVisitAt = &lastVisit.Time
	}
	if prefPayment.Valid {
		c.PreferredPaymentMethod = &prefPayment.String
	}
	if prefHour.Valid {
		h := int(prefHour.Int64)
		c.PreferredHourBucket = &h
	}
	if favCat.Valid {
		c.FavoriteCategoryID = &favCat.String
	}
	if favProd.Valid {
		c.FavoriteProductID = &favProd.String
	}
	c.Tags = []string(tags)
	c.Allergens = []string(allergens)
	c.DietaryTags = []string(dietary)
	if c.Tags == nil {
		c.Tags = []string{}
	}
	if c.Allergens == nil {
		c.Allergens = []string{}
	}
	if c.DietaryTags == nil {
		c.DietaryTags = []string{}
	}
	return c, nil
}

// resolveTenant picks the tenant id from the JWT context first, then falls
// back to the explicit tenant_id query parameter for legacy POS clients.
func resolveTenant(r *http.Request) string {
	if t := middleware.GetTenantID(r.Context()); t != "" {
		return t
	}
	return r.URL.Query().Get("tenant_id")
}

// handleListCustomers returns paginated customers for a tenant.
// GET /api/v1/crm/customers?tenant_id=&search=&cursor=&limit=
func (m *Module) handleListCustomers(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	tenantID := resolveTenant(r)
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
		SELECT ` + customerColumns + `
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
		c, err := scanCustomer(rows)
		if err != nil {
			slog.Error("crm: scan customer", "error", err)
			continue
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
	tenantID := resolveTenant(r)
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
		INSERT INTO customers (id, tenant_id, name, phone, email, birthday, anniversary, notes,
		                       loyalty_points, total_visits, total_spent_cents, avg_ticket_cents,
		                       tags, allergens, dietary_tags,
		                       created_at, updated_at, is_deleted)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8, 0, 0, 0, 0,
		        '{}'::text[], '{}'::text[], '{}'::text[],
		        $9, $9, false)
		ON CONFLICT (id) DO NOTHING
	`, req.ID, tenantID, req.Name, req.Phone, req.Email, req.Birthday, req.Anniversary, req.Notes, now)
	if err != nil {
		slog.Error("crm: create customer", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to create customer")
		return
	}

	m.publishSyncEvent(r.Context(), tenantID, "customers", req.ID, "insert", req)

	customer := Customer{
		ID:          req.ID,
		TenantID:    tenantID,
		Name:        req.Name,
		Phone:       req.Phone,
		Email:       req.Email,
		Birthday:    req.Birthday,
		Anniversary: req.Anniversary,
		Notes:       req.Notes,
		Tags:        []string{},
		Allergens:   []string{},
		DietaryTags: []string{},
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	response.Created(w, customer)
}

// handleGetCustomer returns a single customer by ID.
// GET /api/v1/crm/customers/{id}
func (m *Module) handleGetCustomer(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	row := m.db.QueryRowContext(r.Context(), `
		SELECT `+customerColumns+`
		FROM customers
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID)
	c, err := scanCustomer(row)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "not_found", "customer not found")
		return
	}
	if err != nil {
		slog.Error("crm: get customer", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to get customer")
		return
	}
	response.JSON(w, http.StatusOK, c)
}

// handleUpdateCustomer updates an existing customer.
// PUT /api/v1/crm/customers/{id}
func (m *Module) handleUpdateCustomer(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	var req UpdateCustomerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_body", "invalid JSON")
		return
	}

	// Array fields use a sentinel: NULL → keep existing, pq.Array(slice) → replace.
	var tagsArg, allergensArg, dietaryArg any
	if req.Tags != nil {
		tagsArg = pq.Array(*req.Tags)
	}
	if req.Allergens != nil {
		allergensArg = pq.Array(*req.Allergens)
	}
	if req.DietaryTags != nil {
		dietaryArg = pq.Array(*req.DietaryTags)
	}

	now := time.Now().UTC()
	result, err := m.db.ExecContext(r.Context(), `
		UPDATE customers
		SET name                     = COALESCE($3, name),
		    phone                    = COALESCE($4, phone),
		    email                    = COALESCE($5, email),
		    birthday                 = COALESCE($6, birthday),
		    anniversary              = COALESCE($7::DATE, anniversary),
		    notes                    = COALESCE($8, notes),
		    tags                     = COALESCE($9::text[], tags),
		    allergens                = COALESCE($10::text[], allergens),
		    dietary_tags             = COALESCE($11::text[], dietary_tags),
		    preferred_payment_method = COALESCE($12, preferred_payment_method),
		    updated_at               = $13
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`,
		id, tenantID,
		req.Name, req.Phone, req.Email, req.Birthday, req.Anniversary, req.Notes,
		tagsArg, allergensArg, dietaryArg,
		req.PreferredPaymentMethod,
		now,
	)
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
	tenantID := resolveTenant(r)
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
	tenantID := resolveTenant(r)
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

	// Update customer balance + visit count. Earn events also stamp last_visit_at
	// and back-fill first_visit_at when this is the customer's first visit.
	var visitIncr int
	if req.Type == "earn" {
		visitIncr = 1
	}
	_, err = tx.ExecContext(r.Context(), `
		UPDATE customers
		SET loyalty_points = loyalty_points + $3,
		    total_visits   = total_visits + $4,
		    first_visit_at = COALESCE(first_visit_at, CASE WHEN $4 > 0 THEN $5 END),
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
	tenantID := resolveTenant(r)
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

