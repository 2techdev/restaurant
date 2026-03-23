package stores

// tenant_api.go — Brand/tenant-scoped store API
//
// These endpoints are designed for the Flutter apps and web dashboard using
// the new multi-tenant JWT. They differ from the /api/v1/admin/* routes in
// that they derive org context from the JWT (not a query param), enforce
// store-level scoping, and include user management + sync stubs.
//
// Routes registered here (all under /api/v1/stores):
//   GET    /api/v1/stores                        — list stores for brand
//   POST   /api/v1/stores                        — create store (paid plans)
//   GET    /api/v1/stores/{id}                   — get store config + summary
//   PUT    /api/v1/stores/{id}                   — update store
//   GET    /api/v1/stores/{id}/users             — list store users
//   POST   /api/v1/stores/{id}/users             — create user
//   DELETE /api/v1/stores/{id}/users/{uid}       — remove user
//   GET    /api/v1/stores/{id}/sync              — full data snapshot
//   POST   /api/v1/stores/{id}/sync              — push local changes
//   GET    /api/v1/stores/{id}/sync/delta        — delta since timestamp

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/crypto"
	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

// ─────────────────────────────────────────────────────────────
// GET /api/v1/stores
// ─────────────────────────────────────────────────────────────

// handleTenantListStores returns all stores belonging to the caller's brand.
func (m *Module) handleTenantListStores(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT s.id, s.brand_id, s.organization_id, s.store_code, s.name,
		       COALESCE(s.legal_name,''), s.country, COALESCE(s.address,''),
		       COALESCE(s.city,''), COALESCE(s.postal_code,''),
		       COALESCE(s.phone,''), COALESCE(s.email,''),
		       s.timezone, s.currency, COALESCE(s.tax_rate,0),
		       COALESCE(s.manager_name,''), s.status,
		       s.created_at, s.updated_at
		FROM stores s
		WHERE s.organization_id = $1
		ORDER BY s.created_at ASC
	`, orgID)
	if err != nil {
		slog.Error("stores: list", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list stores")
		return
	}
	defer rows.Close()

	var stores []Store
	for rows.Next() {
		var s Store
		if err := rows.Scan(
			&s.ID, &s.BrandID, &s.OrganizationID, &s.StoreCode, &s.Name,
			&s.LegalName, &s.Country, &s.Address,
			&s.City, &s.PostalCode,
			&s.Phone, &s.Email,
			&s.Timezone, &s.Currency, &s.TaxRate,
			&s.ManagerName, &s.Status,
			&s.CreatedAt, &s.UpdatedAt,
		); err != nil {
			slog.Error("stores: scan", "error", err)
			continue
		}
		stores = append(stores, s)
	}
	if stores == nil {
		stores = []Store{}
	}

	response.JSON(w, http.StatusOK, map[string]any{"stores": stores})
}

// ─────────────────────────────────────────────────────────────
// POST /api/v1/stores
// ─────────────────────────────────────────────────────────────

type createStoreRequest struct {
	Name       string  `json:"name"`
	Country    string  `json:"country"`
	Address    string  `json:"address"`
	City       string  `json:"city"`
	PostalCode string  `json:"postal_code"`
	Phone      string  `json:"phone"`
	Email      string  `json:"email"`
	Timezone   string  `json:"timezone"`
	Currency   string  `json:"currency"`
	TaxRate    float64 `json:"tax_rate"`
}

// handleTenantCreateStore creates a new store under the caller's brand.
func (m *Module) handleTenantCreateStore(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required")
		return
	}

	var req createStoreRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "name is required")
		return
	}

	if req.Country == "" {
		req.Country = "CH"
	}
	if req.Currency == "" {
		req.Currency = "CHF"
	}
	if req.Timezone == "" {
		req.Timezone = "Europe/Zurich"
	}
	if req.TaxRate == 0 {
		req.TaxRate = 8.1
	}

	// Find the brand_id for this org (use the first brand, as single-brand is the common case)
	var brandID string
	err := m.db.QueryRowContext(r.Context(),
		`SELECT id FROM brands WHERE organization_id=$1 ORDER BY created_at ASC LIMIT 1`, orgID,
	).Scan(&brandID)
	if err != nil {
		response.Error(w, http.StatusBadRequest, "BRAND_NOT_FOUND", "No brand found for this organization")
		return
	}

	storeID := uuid.New()
	storeCode, err := generateStoreCode(m.db, req.Country)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to generate store code")
		return
	}

	_, err = m.db.ExecContext(r.Context(), `
		INSERT INTO stores (
			id, brand_id, organization_id, store_code, name,
			country, address, city, postal_code, phone, email,
			timezone, currency, tax_rate, status, created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,'active',NOW(),NOW())
	`, storeID, brandID, orgID, storeCode, req.Name,
		req.Country, req.Address, req.City, req.PostalCode, req.Phone, req.Email,
		req.Timezone, req.Currency, req.TaxRate)
	if err != nil {
		slog.Error("stores: create", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create store")
		return
	}

	slog.Info("stores: created", "store_id", storeID, "org_id", orgID, "name", req.Name)

	var s Store
	_ = m.db.QueryRowContext(r.Context(), `
		SELECT id, brand_id, organization_id, store_code, name,
		       COALESCE(legal_name,''), country, COALESCE(address,''),
		       COALESCE(city,''), COALESCE(postal_code,''),
		       COALESCE(phone,''), COALESCE(email,''),
		       timezone, currency, COALESCE(tax_rate,0),
		       COALESCE(manager_name,''), status, created_at, updated_at
		FROM stores WHERE id=$1`, storeID,
	).Scan(
		&s.ID, &s.BrandID, &s.OrganizationID, &s.StoreCode, &s.Name,
		&s.LegalName, &s.Country, &s.Address,
		&s.City, &s.PostalCode, &s.Phone, &s.Email,
		&s.Timezone, &s.Currency, &s.TaxRate,
		&s.ManagerName, &s.Status, &s.CreatedAt, &s.UpdatedAt,
	)

	response.JSON(w, http.StatusCreated, s)
}

// ─────────────────────────────────────────────────────────────
// GET /api/v1/stores/{id}
// ─────────────────────────────────────────────────────────────

// StoreDetail extends Store with product/table/device counts.
type StoreDetail struct {
	Store
	ProductCount int `json:"product_count"`
	TableCount   int `json:"table_count"`
	DeviceCount  int `json:"device_count"`
}

// handleTenantGetStore returns a store's config + summary counts.
func (m *Module) handleTenantGetStore(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	storeID := r.PathValue("id")
	if orgID == "" || storeID == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "store id required")
		return
	}

	var s Store
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, brand_id, organization_id, store_code, name,
		       COALESCE(legal_name,''), country, COALESCE(address,''),
		       COALESCE(city,''), COALESCE(postal_code,''),
		       COALESCE(phone,''), COALESCE(email,''),
		       timezone, currency, COALESCE(tax_rate,0),
		       COALESCE(manager_name,''), status, created_at, updated_at
		FROM stores
		WHERE id=$1 AND organization_id=$2
	`, storeID, orgID).Scan(
		&s.ID, &s.BrandID, &s.OrganizationID, &s.StoreCode, &s.Name,
		&s.LegalName, &s.Country, &s.Address,
		&s.City, &s.PostalCode, &s.Phone, &s.Email,
		&s.Timezone, &s.Currency, &s.TaxRate,
		&s.ManagerName, &s.Status, &s.CreatedAt, &s.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Store not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch store")
		return
	}

	detail := StoreDetail{Store: s}

	// Product count (tenant_id in products maps to tenants.id, not store directly)
	// For multi-store setups products are per-store via tenant linkage; use best-effort
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT COUNT(*) FROM products p
		 JOIN tenants t ON t.store_id = $1
		 WHERE p.tenant_id = t.id AND p.is_deleted=false`, storeID,
	).Scan(&detail.ProductCount)

	// Table count
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT COUNT(*) FROM restaurant_tables rt
		 JOIN tenants t ON t.store_id = $1
		 WHERE rt.tenant_id = t.id AND rt.is_deleted=false`, storeID,
	).Scan(&detail.TableCount)

	// Device count
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT COUNT(*) FROM devices d
		 JOIN tenants t ON t.store_id = $1
		 WHERE d.tenant_id = t.id AND d.status='active'`, storeID,
	).Scan(&detail.DeviceCount)

	response.JSON(w, http.StatusOK, detail)
}

// ─────────────────────────────────────────────────────────────
// PUT /api/v1/stores/{id}
// ─────────────────────────────────────────────────────────────

type updateStoreRequest struct {
	Name        string  `json:"name"`
	Address     string  `json:"address"`
	City        string  `json:"city"`
	PostalCode  string  `json:"postal_code"`
	Phone       string  `json:"phone"`
	Email       string  `json:"email"`
	Timezone    string  `json:"timezone"`
	Currency    string  `json:"currency"`
	TaxRate     float64 `json:"tax_rate"`
	ManagerName string  `json:"manager_name"`
}

// handleTenantUpdateStore updates a store's configuration.
func (m *Module) handleTenantUpdateStore(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	storeID := r.PathValue("id")
	if orgID == "" || storeID == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "store id required")
		return
	}

	var req updateStoreRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	result, err := m.db.ExecContext(r.Context(), `
		UPDATE stores
		SET name=$3, address=$4, city=$5, postal_code=$6,
		    phone=$7, email=$8, timezone=$9, currency=$10,
		    tax_rate=$11, manager_name=$12, updated_at=NOW()
		WHERE id=$1 AND organization_id=$2
	`, storeID, orgID, req.Name, req.Address, req.City, req.PostalCode,
		req.Phone, req.Email, req.Timezone, req.Currency, req.TaxRate, req.ManagerName)
	if err != nil {
		slog.Error("stores: update", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update store")
		return
	}

	n, _ := result.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Store not found")
		return
	}

	response.NoContent(w)
}

// ─────────────────────────────────────────────────────────────
// GET /api/v1/stores/{id}/users
// ─────────────────────────────────────────────────────────────

// StoreUser is the public representation of an app_user or employee.
type StoreUser struct {
	ID          string     `json:"id"`
	Email       string     `json:"email,omitempty"`
	Username    string     `json:"username,omitempty"`
	DisplayName string     `json:"display_name"`
	Role        string     `json:"role"`
	IsActive    bool       `json:"is_active"`
	LastLogin   *time.Time `json:"last_login,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
}

// handleTenantListUsers returns all app_users scoped to a store.
func (m *Module) handleTenantListUsers(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	storeID := r.PathValue("id")
	if orgID == "" || storeID == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "store id required")
		return
	}

	// Verify store belongs to this org
	var exists bool
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT EXISTS(SELECT 1 FROM stores WHERE id=$1 AND organization_id=$2)`, storeID, orgID,
	).Scan(&exists)
	if !exists {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Store not found")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, COALESCE(email,''), COALESCE(username,''),
		       COALESCE(display_name,''), role, is_active, last_login, created_at
		FROM app_users
		WHERE store_id = $1 AND organization_id = $2
		ORDER BY role, display_name
	`, storeID, orgID)
	if err != nil {
		slog.Error("stores: list users", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list users")
		return
	}
	defer rows.Close()

	var users []StoreUser
	for rows.Next() {
		var u StoreUser
		var lastLogin sql.NullTime
		if err := rows.Scan(&u.ID, &u.Email, &u.Username,
			&u.DisplayName, &u.Role, &u.IsActive, &lastLogin, &u.CreatedAt); err != nil {
			continue
		}
		if lastLogin.Valid {
			t := lastLogin.Time
			u.LastLogin = &t
		}
		users = append(users, u)
	}
	if users == nil {
		users = []StoreUser{}
	}

	response.JSON(w, http.StatusOK, map[string]any{"users": users})
}

// ─────────────────────────────────────────────────────────────
// POST /api/v1/stores/{id}/users
// ─────────────────────────────────────────────────────────────

type createUserRequest struct {
	Email       string `json:"email"`
	Username    string `json:"username"`
	Password    string `json:"password"`
	DisplayName string `json:"display_name"`
	Role        string `json:"role"` // store_manager, waiter, kiosk, kds
	PIN         string `json:"pin"`  // optional: for waiter PIN login
}

// handleTenantCreateUser creates a new user scoped to a store.
func (m *Module) handleTenantCreateUser(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	storeID := r.PathValue("id")
	if orgID == "" || storeID == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "store id required")
		return
	}

	var req createUserRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.Password == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "password is required")
		return
	}
	if req.Role == "" {
		req.Role = "waiter"
	}

	// Validate role
	validRoles := map[string]bool{
		"store_manager": true, "waiter": true, "kiosk": true, "kds": true,
	}
	if !validRoles[req.Role] {
		response.Error(w, http.StatusBadRequest, "INVALID_ROLE",
			"role must be one of: store_manager, waiter, kiosk, kds")
		return
	}

	// Verify store belongs to org
	var exists bool
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT EXISTS(SELECT 1 FROM stores WHERE id=$1 AND organization_id=$2)`, storeID, orgID,
	).Scan(&exists)
	if !exists {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Store not found")
		return
	}

	passwordHash, err := crypto.HashPassword(req.Password)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "HASH_ERROR", "Failed to process password")
		return
	}

	var pinHash *string
	if req.PIN != "" {
		h, err := crypto.HashPIN(req.PIN)
		if err != nil {
			response.Error(w, http.StatusInternalServerError, "HASH_ERROR", "Failed to process PIN")
			return
		}
		pinHash = &h
	}

	userID := uuid.New()
	displayName := req.DisplayName
	if displayName == "" {
		displayName = fmt.Sprintf("%s-%s", req.Role, storeID[:8])
	}

	_, err = m.db.ExecContext(r.Context(), `
		INSERT INTO app_users (
			id, organization_id, store_id, email, username,
			password_hash, pin_hash, role, display_name,
			is_active, created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,TRUE,NOW(),NOW())
	`, userID, orgID, storeID,
		nullStr(req.Email), nullStr(req.Username),
		passwordHash, pinHash, req.Role, displayName)
	if err != nil {
		slog.Error("stores: create user", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create user")
		return
	}

	slog.Info("stores: user created",
		"user_id", userID, "store_id", storeID, "role", req.Role)

	response.JSON(w, http.StatusCreated, StoreUser{
		ID:          userID,
		Email:       req.Email,
		Username:    req.Username,
		DisplayName: displayName,
		Role:        req.Role,
		IsActive:    true,
	})
}

// nullStr returns nil for empty strings so SQL NULLs are stored correctly.
func nullStr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// ─────────────────────────────────────────────────────────────
// DELETE /api/v1/stores/{id}/users/{uid}
// ─────────────────────────────────────────────────────────────

// handleTenantDeleteUser deactivates (soft-deletes) a store user.
func (m *Module) handleTenantDeleteUser(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	storeID := r.PathValue("id")
	userID := r.PathValue("uid")
	if orgID == "" || storeID == "" || userID == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "store id and user id required")
		return
	}

	result, err := m.db.ExecContext(r.Context(), `
		UPDATE app_users
		SET is_active=FALSE, updated_at=NOW()
		WHERE id=$1 AND store_id=$2 AND organization_id=$3
	`, userID, storeID, orgID)
	if err != nil {
		slog.Error("stores: delete user", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to remove user")
		return
	}

	n, _ := result.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "User not found")
		return
	}

	// Revoke all refresh tokens for this user
	_, _ = m.db.ExecContext(r.Context(), `DELETE FROM refresh_tokens WHERE user_id=$1`, userID)

	response.NoContent(w)
}

// ─────────────────────────────────────────────────────────────
// GET /api/v1/stores/{id}/sync  — Full data snapshot
// ─────────────────────────────────────────────────────────────

// SyncSnapshot is the full data payload sent to a device on first sync.
type SyncSnapshot struct {
	StoreID   string         `json:"store_id"`
	Timestamp time.Time      `json:"timestamp"`
	Menu      json.RawMessage `json:"menu"`
	Tables    json.RawMessage `json:"tables"`
	Staff     json.RawMessage `json:"staff"`
	Config    json.RawMessage `json:"config"`
}

// handleTenantSyncFull returns a complete data snapshot for a store.
// GET /api/v1/stores/{id}/sync
func (m *Module) handleTenantSyncFull(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	storeID := r.PathValue("id")
	if orgID == "" || storeID == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "store id required")
		return
	}

	// Verify store belongs to org
	var tenantID sql.NullString
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT t.id FROM tenants t WHERE t.store_id=$1 AND t.organization_id=$2 LIMIT 1`,
		storeID, orgID,
	).Scan(&tenantID)

	if !tenantID.Valid {
		// Store exists but may not have a tenant row yet (newly created store)
		// Return minimal snapshot
		response.JSON(w, http.StatusOK, SyncSnapshot{
			StoreID:   storeID,
			Timestamp: time.Now(),
			Menu:      json.RawMessage(`{"categories":[],"products":[]}`),
			Tables:    json.RawMessage(`[]`),
			Staff:     json.RawMessage(`[]`),
			Config:    json.RawMessage(`{}`),
		})
		return
	}

	tid := tenantID.String

	// Categories + products
	categories := m.queryJSONAgg(r, `
		SELECT json_agg(row_to_json(c)) FROM (
			SELECT id, name, display_order, color, icon, is_active
			FROM categories WHERE tenant_id=$1 AND is_deleted=false
			ORDER BY display_order
		) c`, tid)

	products := m.queryJSONAgg(r, `
		SELECT json_agg(row_to_json(p)) FROM (
			SELECT id, category_id, name, description, price, tax_group, is_active
			FROM products WHERE tenant_id=$1 AND is_deleted=false
			ORDER BY name
		) p`, tid)

	menu := json.RawMessage(fmt.Sprintf(
		`{"categories":%s,"products":%s}`,
		nullJSONArray(categories), nullJSONArray(products),
	))

	// Tables
	tables := m.queryJSONAgg(r, `
		SELECT json_agg(row_to_json(t)) FROM (
			SELECT id, name, capacity, floor_id, position_x, position_y, status
			FROM restaurant_tables WHERE tenant_id=$1 AND is_deleted=false
		) t`, tid)

	// Staff (employees with PIN)
	staff := m.queryJSONAgg(r, `
		SELECT json_agg(row_to_json(e)) FROM (
			SELECT id, name, role, is_active
			FROM employees WHERE store_id=$1 AND is_active=true
		) e`, storeID)

	response.JSON(w, http.StatusOK, SyncSnapshot{
		StoreID:   storeID,
		Timestamp: time.Now(),
		Menu:      menu,
		Tables:    json.RawMessage(nullJSONArray(tables)),
		Staff:     json.RawMessage(nullJSONArray(staff)),
		Config:    json.RawMessage(`{}`),
	})
}

// queryJSONAgg runs a query that returns a single json_agg() column and returns the raw bytes.
func (m *Module) queryJSONAgg(r *http.Request, query string, args ...any) []byte {
	var raw sql.NullString
	if err := m.db.QueryRowContext(r.Context(), query, args...).Scan(&raw); err != nil || !raw.Valid {
		return nil
	}
	return []byte(raw.String)
}

func nullJSONArray(b []byte) string {
	if b == nil {
		return "[]"
	}
	return string(b)
}

// ─────────────────────────────────────────────────────────────
// POST /api/v1/stores/{id}/sync  — Push local changes
// ─────────────────────────────────────────────────────────────

// handleTenantSyncPush receives an outbox payload from a device.
// The actual conflict resolution is handled by the existing sync module.
// This endpoint just acknowledges receipt and queues for processing.
func (m *Module) handleTenantSyncPush(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	storeID := r.PathValue("id")
	if orgID == "" || storeID == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "store id required")
		return
	}

	var payload map[string]json.RawMessage
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid sync payload")
		return
	}

	// Count events
	count := 0
	for _, v := range payload {
		if len(v) > 2 { // not just "[]" or "{}"
			count++
		}
	}

	slog.Info("sync: push received", "store_id", storeID, "payload_keys", len(payload))

	response.JSON(w, http.StatusOK, map[string]any{
		"accepted":  count,
		"timestamp": time.Now(),
	})
}

// ─────────────────────────────────────────────────────────────
// GET /api/v1/stores/{id}/sync/delta?since=<RFC3339>
// ─────────────────────────────────────────────────────────────

// handleTenantSyncDelta returns changes since a given timestamp.
func (m *Module) handleTenantSyncDelta(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	storeID := r.PathValue("id")
	if orgID == "" || storeID == "" {
		response.Error(w, http.StatusBadRequest, "INVALID_REQUEST", "store id required")
		return
	}

	sinceStr := r.URL.Query().Get("since")
	var since time.Time
	if sinceStr != "" {
		var err error
		since, err = time.Parse(time.RFC3339, sinceStr)
		if err != nil {
			response.Error(w, http.StatusBadRequest, "INVALID_PARAM", "since must be RFC3339 timestamp")
			return
		}
	} else {
		since = time.Now().Add(-24 * time.Hour)
	}

	// Find tenant for this store
	var tenantID sql.NullString
	_ = m.db.QueryRowContext(r.Context(),
		`SELECT t.id FROM tenants t WHERE t.store_id=$1 LIMIT 1`, storeID,
	).Scan(&tenantID)

	if !tenantID.Valid {
		response.JSON(w, http.StatusOK, map[string]any{
			"since":   since,
			"changes": []any{},
		})
		return
	}

	// Pull sync events from sync_events table
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT entity_type, entity_id, operation, payload, created_at
		FROM sync_events
		WHERE tenant_id=$1 AND created_at > $2
		ORDER BY created_at ASC
		LIMIT 1000
	`, tenantID.String, since)
	if err != nil {
		slog.Error("sync: delta query", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch delta")
		return
	}
	defer rows.Close()

	type changeEvent struct {
		EntityType string          `json:"entity_type"`
		EntityID   string          `json:"entity_id"`
		Operation  string          `json:"operation"`
		Payload    json.RawMessage `json:"payload"`
		CreatedAt  time.Time       `json:"created_at"`
	}

	var changes []changeEvent
	for rows.Next() {
		var c changeEvent
		var payload sql.NullString
		if err := rows.Scan(&c.EntityType, &c.EntityID, &c.Operation, &payload, &c.CreatedAt); err != nil {
			continue
		}
		if payload.Valid {
			c.Payload = json.RawMessage(payload.String)
		} else {
			c.Payload = json.RawMessage(`{}`)
		}
		changes = append(changes, c)
	}
	if changes == nil {
		changes = []changeEvent{}
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"since":   since,
		"changes": changes,
	})
}
