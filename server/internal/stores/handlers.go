package stores

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/crypto"
	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	pqlib "github.com/lib/pq"
)

// ============================================================
// Organization handlers
// ============================================================

// handleGetOrganization returns the current organization.
// GET /api/v1/admin/organization
func (m *Module) handleGetOrganization(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}

	var org Organization
	var logo, taxID, address, phone, email sql.NullString
	var trialEndsAt sql.NullTime

	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, name, COALESCE(legal_name,''), COALESCE(tax_id,''),
		       country, COALESCE(address,''), COALESCE(phone,''), COALESCE(email,''),
		       COALESCE(logo,''), plan, status, trial_ends_at, created_at, updated_at
		FROM organizations
		WHERE id = $1
	`, orgID).Scan(
		&org.ID, &org.Name, &org.LegalName, &taxID,
		&org.Country, &address, &phone, &email,
		&logo, &org.Plan, &org.Status, &trialEndsAt, &org.CreatedAt, &org.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Organization not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch organization")
		return
	}

	org.TaxID = taxID.String
	org.Address = address.String
	org.Phone = phone.String
	org.Email = email.String
	org.Logo = logo.String
	if trialEndsAt.Valid {
		t := trialEndsAt.Time
		org.TrialEndsAt = &t
	}

	response.JSON(w, http.StatusOK, org)
}

// handleUpdateOrganization updates the current organization.
// PUT /api/v1/admin/organization
func (m *Module) handleUpdateOrganization(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}

	var req struct {
		Name      string `json:"name"`
		LegalName string `json:"legal_name"`
		TaxID     string `json:"tax_id"`
		Address   string `json:"address"`
		Phone     string `json:"phone"`
		Email     string `json:"email"`
		Logo      string `json:"logo"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	_, err := m.db.ExecContext(r.Context(), `
		UPDATE organizations
		SET name=$2, legal_name=$3, tax_id=$4, address=$5,
		    phone=$6, email=$7, logo=$8, updated_at=NOW()
		WHERE id=$1
	`, orgID, req.Name, req.LegalName, req.TaxID,
		req.Address, req.Phone, req.Email, req.Logo)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update organization")
		return
	}

	// Return updated org
	m.handleGetOrganization(w, r)
}

// ============================================================
// Brand handlers
// ============================================================

// handleListBrands returns all brands for the current organization.
// GET /api/v1/admin/brands
func (m *Module) handleListBrands(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, organization_id, name, COALESCE(logo,''), COALESCE(description,''),
		       status, created_at, updated_at
		FROM brands
		WHERE organization_id = $1
		ORDER BY name
	`, orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list brands")
		return
	}
	defer rows.Close()

	brands := make([]Brand, 0)
	for rows.Next() {
		var b Brand
		if err := rows.Scan(
			&b.ID, &b.OrganizationID, &b.Name, &b.Logo, &b.Description,
			&b.Status, &b.CreatedAt, &b.UpdatedAt,
		); err == nil {
			brands = append(brands, b)
		}
	}

	response.JSON(w, http.StatusOK, brands)
}

// handleCreateBrand creates a new brand.
// POST /api/v1/admin/brands
func (m *Module) handleCreateBrand(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}

	var req struct {
		Name        string `json:"name"`
		Logo        string `json:"logo"`
		Description string `json:"description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "name is required")
		return
	}

	var brand Brand
	err := m.db.QueryRowContext(r.Context(), `
		INSERT INTO brands (organization_id, name, logo, description, status)
		VALUES ($1, $2, $3, $4, 'active')
		RETURNING id, organization_id, name, COALESCE(logo,''), COALESCE(description,''),
		          status, created_at, updated_at
	`, orgID, req.Name, req.Logo, req.Description,
	).Scan(
		&brand.ID, &brand.OrganizationID, &brand.Name, &brand.Logo, &brand.Description,
		&brand.Status, &brand.CreatedAt, &brand.UpdatedAt,
	)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create brand")
		return
	}

	response.Created(w, brand)
}

// handleUpdateBrand updates an existing brand.
// PUT /api/v1/admin/brands/{id}
func (m *Module) handleUpdateBrand(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}
	brandID := r.PathValue("id")
	if brandID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "brand id is required")
		return
	}

	var req struct {
		Name        string `json:"name"`
		Logo        string `json:"logo"`
		Description string `json:"description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	var brand Brand
	err := m.db.QueryRowContext(r.Context(), `
		UPDATE brands
		SET name=$3, logo=$4, description=$5, updated_at=NOW()
		WHERE id=$1 AND organization_id=$2
		RETURNING id, organization_id, name, COALESCE(logo,''), COALESCE(description,''),
		          status, created_at, updated_at
	`, brandID, orgID, req.Name, req.Logo, req.Description,
	).Scan(
		&brand.ID, &brand.OrganizationID, &brand.Name, &brand.Logo, &brand.Description,
		&brand.Status, &brand.CreatedAt, &brand.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Brand not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update brand")
		return
	}

	response.JSON(w, http.StatusOK, brand)
}

// handleDeleteBrand deactivates a brand (soft delete).
// DELETE /api/v1/admin/brands/{id}
func (m *Module) handleDeleteBrand(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}
	brandID := r.PathValue("id")
	if brandID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "brand id is required")
		return
	}

	// Check for active stores under this brand
	var activeStoreCount int
	_ = m.db.QueryRowContext(r.Context(), `
		SELECT COUNT(*) FROM stores WHERE brand_id=$1 AND status='active'
	`, brandID).Scan(&activeStoreCount)

	if activeStoreCount > 0 {
		response.Error(w, http.StatusConflict, "BRAND_HAS_STORES",
			fmt.Sprintf("Cannot deactivate brand with %d active store(s)", activeStoreCount))
		return
	}

	_, err := m.db.ExecContext(r.Context(), `
		UPDATE brands SET status='inactive', updated_at=NOW()
		WHERE id=$1 AND organization_id=$2
	`, brandID, orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to deactivate brand")
		return
	}

	response.NoContent(w)
}

// ============================================================
// Store handlers
// ============================================================

// handleListStores returns all stores with optional filtering.
// GET /api/v1/admin/stores?name=&code=&status=&brand_id=
func (m *Module) handleListStores(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}

	q := r.URL.Query()
	nameFilter := q.Get("name")
	codeFilter := q.Get("code")
	statusFilter := q.Get("status")
	brandFilter := q.Get("brand_id")

	where := "s.organization_id = $1"
	args := []any{orgID}
	idx := 2

	if nameFilter != "" {
		where += fmt.Sprintf(" AND s.name ILIKE $%d", idx)
		args = append(args, "%"+nameFilter+"%")
		idx++
	}
	if codeFilter != "" {
		where += fmt.Sprintf(" AND s.store_code = $%d", idx)
		args = append(args, codeFilter)
		idx++
	}
	if statusFilter != "" {
		where += fmt.Sprintf(" AND s.status = $%d", idx)
		args = append(args, statusFilter)
		idx++
	}
	if brandFilter != "" {
		where += fmt.Sprintf(" AND s.brand_id = $%d", idx)
		args = append(args, brandFilter)
		idx++
	}
	_ = idx

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT
			s.id, s.brand_id, s.organization_id, s.store_code,
			s.name, COALESCE(s.legal_name,''), s.country,
			COALESCE(s.address,''), COALESCE(s.city,''), COALESCE(s.postal_code,''),
			COALESCE(s.phone,''), COALESCE(s.email,''),
			s.timezone, s.currency, COALESCE(s.tax_rate, 8.1),
			COALESCE(s.manager_name,''), s.status, s.expires_at,
			(SELECT COUNT(*) FROM products p WHERE p.tenant_id = s.id::TEXT AND p.is_deleted=FALSE AND p.is_active=TRUE),
			(SELECT COUNT(*) FROM restaurant_tables rt WHERE rt.tenant_id = s.id::TEXT AND rt.is_deleted=FALSE),
			0,
			s.created_at, s.updated_at
		FROM stores s
		WHERE `+where+`
		ORDER BY s.name
	`, args...)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list stores")
		return
	}
	defer rows.Close()

	stores := make([]Store, 0)
	for rows.Next() {
		var s Store
		var expiresAt sql.NullTime
		if err := rows.Scan(
			&s.ID, &s.BrandID, &s.OrganizationID, &s.StoreCode,
			&s.Name, &s.LegalName, &s.Country,
			&s.Address, &s.City, &s.PostalCode,
			&s.Phone, &s.Email,
			&s.Timezone, &s.Currency, &s.TaxRate,
			&s.ManagerName, &s.Status, &expiresAt,
			&s.ProductCount, &s.TableCount, &s.DeviceCount,
			&s.CreatedAt, &s.UpdatedAt,
		); err == nil {
			if expiresAt.Valid {
				t := expiresAt.Time
				s.ExpiresAt = &t
			}
			stores = append(stores, s)
		}
	}

	response.JSON(w, http.StatusOK, stores)
}

// handleCreateStore creates a new store.
// POST /api/v1/admin/stores
func (m *Module) handleCreateStore(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}

	var req struct {
		BrandID     string  `json:"brand_id"`
		Name        string  `json:"name"`
		LegalName   string  `json:"legal_name"`
		Country     string  `json:"country"`
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
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.BrandID == "" || req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "brand_id and name are required")
		return
	}

	// Defaults for Swiss stores
	if req.Timezone == "" {
		req.Timezone = "Europe/Zurich"
	}
	if req.Currency == "" {
		req.Currency = "CHF"
	}
	if req.Country == "" {
		req.Country = "CH"
	}
	if req.TaxRate == 0 {
		req.TaxRate = 8.1
	}

	// Generate unique store code
	storeCode, err := generateStoreCode(m.db, req.Country)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to generate store code")
		return
	}

	var store Store
	var expiresAt sql.NullTime
	err = m.db.QueryRowContext(r.Context(), `
		INSERT INTO stores (
			brand_id, organization_id, store_code, name, legal_name,
			country, address, city, postal_code, phone, email,
			timezone, currency, tax_rate, manager_name, status
		) VALUES (
			$1, $2, $3, $4, $5,
			$6, $7, $8, $9, $10, $11,
			$12, $13, $14, $15, 'active'
		)
		RETURNING id, brand_id, organization_id, store_code,
		          name, COALESCE(legal_name,''), country,
		          COALESCE(address,''), COALESCE(city,''), COALESCE(postal_code,''),
		          COALESCE(phone,''), COALESCE(email,''),
		          timezone, currency, COALESCE(tax_rate, 8.1),
		          COALESCE(manager_name,''), status, expires_at,
		          created_at, updated_at
	`, req.BrandID, orgID, storeCode, req.Name, req.LegalName,
		req.Country, req.Address, req.City, req.PostalCode, req.Phone, req.Email,
		req.Timezone, req.Currency, req.TaxRate, req.ManagerName,
	).Scan(
		&store.ID, &store.BrandID, &store.OrganizationID, &store.StoreCode,
		&store.Name, &store.LegalName, &store.Country,
		&store.Address, &store.City, &store.PostalCode,
		&store.Phone, &store.Email,
		&store.Timezone, &store.Currency, &store.TaxRate,
		&store.ManagerName, &store.Status, &expiresAt,
		&store.CreatedAt, &store.UpdatedAt,
	)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create store")
		return
	}
	if expiresAt.Valid {
		t := expiresAt.Time
		store.ExpiresAt = &t
	}

	response.Created(w, store)
}

// handleGetStore returns a single store with counts.
// GET /api/v1/admin/stores/{id}
func (m *Module) handleGetStore(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}
	storeID := r.PathValue("id")
	if storeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id is required")
		return
	}

	var s Store
	var expiresAt sql.NullTime
	err := m.db.QueryRowContext(r.Context(), `
		SELECT
			s.id, s.brand_id, s.organization_id, s.store_code,
			s.name, COALESCE(s.legal_name,''), s.country,
			COALESCE(s.address,''), COALESCE(s.city,''), COALESCE(s.postal_code,''),
			COALESCE(s.phone,''), COALESCE(s.email,''),
			s.timezone, s.currency, COALESCE(s.tax_rate, 8.1),
			COALESCE(s.manager_name,''), s.status, s.expires_at,
			(SELECT COUNT(*) FROM products p WHERE p.tenant_id = s.id::TEXT AND p.is_deleted=FALSE AND p.is_active=TRUE),
			(SELECT COUNT(*) FROM restaurant_tables rt WHERE rt.tenant_id = s.id::TEXT AND rt.is_deleted=FALSE),
			0,
			s.created_at, s.updated_at
		FROM stores s
		WHERE s.id = $1 AND s.organization_id = $2
	`, storeID, orgID).Scan(
		&s.ID, &s.BrandID, &s.OrganizationID, &s.StoreCode,
		&s.Name, &s.LegalName, &s.Country,
		&s.Address, &s.City, &s.PostalCode,
		&s.Phone, &s.Email,
		&s.Timezone, &s.Currency, &s.TaxRate,
		&s.ManagerName, &s.Status, &expiresAt,
		&s.ProductCount, &s.TableCount, &s.DeviceCount,
		&s.CreatedAt, &s.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Store not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch store")
		return
	}
	if expiresAt.Valid {
		t := expiresAt.Time
		s.ExpiresAt = &t
	}

	response.JSON(w, http.StatusOK, s)
}

// handleUpdateStore updates an existing store.
// PUT /api/v1/admin/stores/{id}
func (m *Module) handleUpdateStore(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}
	storeID := r.PathValue("id")
	if storeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id is required")
		return
	}

	var req struct {
		Name        string  `json:"name"`
		LegalName   string  `json:"legal_name"`
		Address     string  `json:"address"`
		City        string  `json:"city"`
		PostalCode  string  `json:"postal_code"`
		Phone       string  `json:"phone"`
		Email       string  `json:"email"`
		Timezone    string  `json:"timezone"`
		Currency    string  `json:"currency"`
		TaxRate     float64 `json:"tax_rate"`
		ManagerName string  `json:"manager_name"`
		Status      string  `json:"status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	_, err := m.db.ExecContext(r.Context(), `
		UPDATE stores
		SET name=$3, legal_name=$4, address=$5, city=$6, postal_code=$7,
		    phone=$8, email=$9, timezone=$10, currency=$11,
		    tax_rate=$12, manager_name=$13, status=$14, updated_at=NOW()
		WHERE id=$1 AND organization_id=$2
	`, storeID, orgID,
		req.Name, req.LegalName, req.Address, req.City, req.PostalCode,
		req.Phone, req.Email, req.Timezone, req.Currency,
		req.TaxRate, req.ManagerName, req.Status)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update store")
		return
	}

	// Return updated store
	m.handleGetStore(w, r)
}

// handleDeleteStore deactivates a store (soft delete).
// DELETE /api/v1/admin/stores/{id}
func (m *Module) handleDeleteStore(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}
	storeID := r.PathValue("id")
	if storeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id is required")
		return
	}

	_, err := m.db.ExecContext(r.Context(), `
		UPDATE stores SET status='inactive', updated_at=NOW()
		WHERE id=$1 AND organization_id=$2
	`, storeID, orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to deactivate store")
		return
	}

	response.NoContent(w)
}

// handleGetStoreStats returns statistics for a specific store.
// GET /api/v1/admin/stores/{id}/stats
func (m *Module) handleGetStoreStats(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}
	storeID := r.PathValue("id")
	if storeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id is required")
		return
	}

	// Verify store belongs to this org
	var storeName string
	err := m.db.QueryRowContext(r.Context(), `
		SELECT name FROM stores WHERE id=$1 AND organization_id=$2
	`, storeID, orgID).Scan(&storeName)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Store not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to verify store")
		return
	}

	now := time.Now()
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	weekStart := todayStart.AddDate(0, 0, -6)
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())

	// The tenant_id in tickets matches the store ID from the multi-store schema.
	// We query using the store ID as the tenant_id.
	var todaySales, weekSales, monthSales int64
	var todayOrders, weekOrders, monthOrders int

	_ = m.db.QueryRowContext(r.Context(), `
		SELECT
			COALESCE(SUM(total) FILTER (WHERE created_at >= $2), 0),
			COUNT(*) FILTER (WHERE created_at >= $2 AND status NOT IN ('void','open')),
			COALESCE(SUM(total) FILTER (WHERE created_at >= $3), 0),
			COUNT(*) FILTER (WHERE created_at >= $3 AND status NOT IN ('void','open')),
			COALESCE(SUM(total) FILTER (WHERE created_at >= $4), 0),
			COUNT(*) FILTER (WHERE created_at >= $4 AND status NOT IN ('void','open'))
		FROM tickets
		WHERE tenant_id = $1 AND is_deleted = FALSE AND status NOT IN ('void','open')
	`, storeID, todayStart, weekStart, monthStart).Scan(
		&todaySales, &todayOrders,
		&weekSales, &weekOrders,
		&monthSales, &monthOrders,
	)

	// Active devices (last seen within 24h)
	var activeDevices int
	_ = m.db.QueryRowContext(r.Context(), `
		SELECT COUNT(*) FROM devices
		WHERE tenant_id = $1 AND status='active'
		  AND last_seen_at >= NOW() - INTERVAL '24 hours'
	`, storeID).Scan(&activeDevices)

	// Active staff (users with is_active=true)
	var activeStaff int
	_ = m.db.QueryRowContext(r.Context(), `
		SELECT COUNT(*) FROM users
		WHERE tenant_id = $1 AND is_active=TRUE AND is_deleted=FALSE
	`, storeID).Scan(&activeStaff)

	stats := StoreStats{
		StoreID:       storeID,
		StoreName:     storeName,
		TodaySales:    todaySales,
		TodayOrders:   todayOrders,
		WeekSales:     weekSales,
		WeekOrders:    weekOrders,
		MonthSales:    monthSales,
		MonthOrders:   monthOrders,
		ActiveDevices: activeDevices,
		ActiveStaff:   activeStaff,
	}

	response.JSON(w, http.StatusOK, stats)
}

// ============================================================
// Admin User handlers
// ============================================================

// handleListAdminUsers returns all admin users for the organization.
// GET /api/v1/admin/users
func (m *Module) handleListAdminUsers(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, organization_id, email, name, role,
		       COALESCE(store_ids, '{}'), status, last_login_at, created_at, updated_at
		FROM admin_users
		WHERE organization_id = $1
		ORDER BY name
	`, orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list admin users")
		return
	}
	defer rows.Close()

	users := make([]AdminUser, 0)
	for rows.Next() {
		var u AdminUser
		var storeIDs pqlib.StringArray
		var lastLoginAt sql.NullTime
		if err := rows.Scan(
			&u.ID, &u.OrganizationID, &u.Email, &u.Name, &u.Role,
			&storeIDs, &u.Status, &lastLoginAt, &u.CreatedAt, &u.UpdatedAt,
		); err == nil {
			u.StoreIDs = []string(storeIDs)
			if lastLoginAt.Valid {
				t := lastLoginAt.Time
				u.LastLoginAt = &t
			}
			users = append(users, u)
		}
	}

	response.JSON(w, http.StatusOK, users)
}

// handleCreateAdminUser creates a new admin user.
// POST /api/v1/admin/users
func (m *Module) handleCreateAdminUser(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}

	var req struct {
		Email    string   `json:"email"`
		Name     string   `json:"name"`
		Password string   `json:"password"`
		Role     string   `json:"role"`
		StoreIDs []string `json:"store_ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.Email == "" || req.Name == "" || req.Password == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "email, name, and password are required")
		return
	}

	role := req.Role
	if role == "" {
		role = "viewer"
	}

	passwordHash, err := crypto.HashPassword(req.Password)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "HASH_ERROR", "Failed to hash password")
		return
	}

	storeIDs := req.StoreIDs
	if storeIDs == nil {
		storeIDs = []string{}
	}

	var user AdminUser
	var lastLoginAt sql.NullTime
	err = m.db.QueryRowContext(r.Context(), `
		INSERT INTO admin_users (organization_id, email, password_hash, name, role, store_ids, status)
		VALUES ($1, $2, $3, $4, $5, $6, 'active')
		RETURNING id, organization_id, email, name, role,
		          COALESCE(store_ids,'{}'), status, last_login_at, created_at, updated_at
	`, orgID, req.Email, passwordHash, req.Name, role, pqlib.Array(storeIDs),
	).Scan(
		&user.ID, &user.OrganizationID, &user.Email, &user.Name, &user.Role,
		pqlib.Array(&storeIDs), &user.Status, &lastLoginAt, &user.CreatedAt, &user.UpdatedAt,
	)
	if err != nil {
		// Check for duplicate email
		if isUniqueViolation(err) {
			response.Error(w, http.StatusConflict, "DUPLICATE_EMAIL", "A user with this email already exists")
			return
		}
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create admin user")
		return
	}
	user.StoreIDs = storeIDs

	response.Created(w, user)
}

// handleUpdateAdminUser updates an existing admin user.
// PUT /api/v1/admin/users/{id}
func (m *Module) handleUpdateAdminUser(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}
	userID := r.PathValue("id")
	if userID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "user id is required")
		return
	}

	var req struct {
		Name     string   `json:"name"`
		Role     string   `json:"role"`
		StoreIDs []string `json:"store_ids"`
		Status   string   `json:"status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	storeIDs := req.StoreIDs
	if storeIDs == nil {
		storeIDs = []string{}
	}

	var user AdminUser
	var lastLoginAt sql.NullTime
	err := m.db.QueryRowContext(r.Context(), `
		UPDATE admin_users
		SET name=$3, role=$4, store_ids=$5, status=$6, updated_at=NOW()
		WHERE id=$1 AND organization_id=$2
		RETURNING id, organization_id, email, name, role,
		          COALESCE(store_ids,'{}'), status, last_login_at, created_at, updated_at
	`, userID, orgID, req.Name, req.Role, pqlib.Array(storeIDs), req.Status,
	).Scan(
		&user.ID, &user.OrganizationID, &user.Email, &user.Name, &user.Role,
		pqlib.Array(&storeIDs), &user.Status, &lastLoginAt, &user.CreatedAt, &user.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Admin user not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update admin user")
		return
	}
	user.StoreIDs = storeIDs
	if lastLoginAt.Valid {
		t := lastLoginAt.Time
		user.LastLoginAt = &t
	}

	response.JSON(w, http.StatusOK, user)
}

// handleDeleteAdminUser deactivates an admin user (soft delete).
// DELETE /api/v1/admin/users/{id}
func (m *Module) handleDeleteAdminUser(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}
	userID := r.PathValue("id")
	if userID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "user id is required")
		return
	}

	_, err := m.db.ExecContext(r.Context(), `
		UPDATE admin_users SET status='inactive', updated_at=NOW()
		WHERE id=$1 AND organization_id=$2
	`, userID, orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to deactivate admin user")
		return
	}

	response.NoContent(w)
}

// ============================================================
// Employee handlers
// ============================================================

// handleListEmployees returns all employees for a specific store.
// GET /api/v1/admin/stores/{id}/employees
func (m *Module) handleListEmployees(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}
	storeID := r.PathValue("id")
	if storeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id is required")
		return
	}

	// Employees are stored in the users table with the store's tenant_id
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, name, role, is_active,
		       COALESCE(email,''), COALESCE(phone,''), created_at, updated_at
		FROM users
		WHERE tenant_id = $1 AND is_deleted = FALSE
		ORDER BY name
	`, storeID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list employees")
		return
	}
	defer rows.Close()

	employees := make([]Employee, 0)
	for rows.Next() {
		var e Employee
		if err := rows.Scan(
			&e.ID, &e.StoreID, &e.Name, &e.Role, &e.IsActive,
			&e.Email, &e.Phone, &e.CreatedAt, &e.UpdatedAt,
		); err == nil {
			e.OrganizationID = orgID
			employees = append(employees, e)
		}
	}

	response.JSON(w, http.StatusOK, employees)
}

// handleCreateEmployee creates a new employee for a store.
// POST /api/v1/admin/stores/{id}/employees
func (m *Module) handleCreateEmployee(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}
	storeID := r.PathValue("id")
	if storeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id is required")
		return
	}

	var req struct {
		Name        string `json:"name"`
		PIN         string `json:"pin"`
		Role        string `json:"role"`
		Phone       string `json:"phone"`
		Email       string `json:"email"`
		Permissions string `json:"permissions"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "name is required")
		return
	}
	if req.PIN == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "pin is required")
		return
	}

	role := req.Role
	if role == "" {
		role = "waiter"
	}

	// Hash the PIN using the same crypto module as the Flutter app
	pinHash, err := crypto.HashPIN(req.PIN)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "HASH_ERROR", "Failed to hash PIN")
		return
	}

	var employee Employee
	err = m.db.QueryRowContext(r.Context(), `
		INSERT INTO users (tenant_id, name, pin_hash, role, is_active, email, phone)
		VALUES ($1, $2, $3, $4, TRUE, $5, $6)
		RETURNING id, tenant_id, name, role, is_active,
		          COALESCE(email,''), COALESCE(phone,''), created_at, updated_at
	`, storeID, req.Name, pinHash, role, req.Email, req.Phone,
	).Scan(
		&employee.ID, &employee.StoreID, &employee.Name, &employee.Role, &employee.IsActive,
		&employee.Email, &employee.Phone, &employee.CreatedAt, &employee.UpdatedAt,
	)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create employee")
		return
	}
	employee.OrganizationID = orgID

	response.Created(w, employee)
}

// handleUpdateEmployee updates an existing employee.
// PUT /api/v1/admin/employees/{id}
func (m *Module) handleUpdateEmployee(w http.ResponseWriter, r *http.Request) {
	employeeID := r.PathValue("id")
	if employeeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "employee id is required")
		return
	}

	var req struct {
		Name        string `json:"name"`
		Role        string `json:"role"`
		Phone       string `json:"phone"`
		Email       string `json:"email"`
		IsActive    *bool  `json:"is_active"`
		Permissions string `json:"permissions"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}

	var employee Employee
	err := m.db.QueryRowContext(r.Context(), `
		UPDATE users
		SET name=$2, role=$3, phone=$4, email=$5, is_active=$6, updated_at=NOW()
		WHERE id=$1 AND is_deleted=FALSE
		RETURNING id, tenant_id, name, role, is_active,
		          COALESCE(email,''), COALESCE(phone,''), created_at, updated_at
	`, employeeID, req.Name, req.Role, req.Phone, req.Email, isActive,
	).Scan(
		&employee.ID, &employee.StoreID, &employee.Name, &employee.Role, &employee.IsActive,
		&employee.Email, &employee.Phone, &employee.CreatedAt, &employee.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Employee not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update employee")
		return
	}

	response.JSON(w, http.StatusOK, employee)
}

// handleDeleteEmployee deactivates an employee (soft delete).
// DELETE /api/v1/admin/employees/{id}
func (m *Module) handleDeleteEmployee(w http.ResponseWriter, r *http.Request) {
	employeeID := r.PathValue("id")
	if employeeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "employee id is required")
		return
	}

	_, err := m.db.ExecContext(r.Context(), `
		UPDATE users SET is_active=FALSE, updated_at=NOW()
		WHERE id=$1 AND is_deleted=FALSE
	`, employeeID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to deactivate employee")
		return
	}

	response.NoContent(w)
}

// ============================================================
// Dashboard handlers
// ============================================================

// handleDashboard returns organization-wide dashboard statistics.
// GET /api/v1/admin/dashboard
func (m *Module) handleDashboard(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}

	now := time.Now()
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	yesterdayStart := todayStart.AddDate(0, 0, -1)
	todayEnd := todayStart.Add(24*time.Hour - time.Nanosecond)
	yesterdayEnd := yesterdayStart.Add(24*time.Hour - time.Nanosecond)

	// Get all store IDs for this org
	storeRows, err := m.db.QueryContext(r.Context(), `
		SELECT id::TEXT FROM stores WHERE organization_id=$1 AND status='active'
	`, orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to query stores")
		return
	}
	defer storeRows.Close()

	storeIDs := []string{}
	for storeRows.Next() {
		var sid string
		if storeRows.Scan(&sid) == nil {
			storeIDs = append(storeIDs, sid)
		}
	}

	if len(storeIDs) == 0 {
		// No stores, return zeros
		response.JSON(w, http.StatusOK, DashboardResponse{
			HourlySales: make([]int64, 24),
		})
		return
	}

	// Build IN clause for tenant_ids
	inClause, args := buildInClause(storeIDs, 1)

	// Today's stats
	var todaySales, todayNetSales, todayTax, todayDiscounts int64
	var todayOrders int
	queryArgs := append(args, todayStart, todayEnd)
	_ = m.db.QueryRowContext(r.Context(), `
		SELECT
			COALESCE(SUM(total),0),
			COALESCE(SUM(total - discount_amount),0),
			COALESCE(SUM(tax_amount),0),
			COALESCE(SUM(discount_amount),0),
			COUNT(*)
		FROM tickets
		WHERE tenant_id IN (`+inClause+`)
		  AND is_deleted=FALSE
		  AND status NOT IN ('void','open')
		  AND created_at >= $`+fmt.Sprintf("%d", len(args)+1)+`
		  AND created_at <= $`+fmt.Sprintf("%d", len(args)+2),
		queryArgs...,
	).Scan(&todaySales, &todayNetSales, &todayTax, &todayDiscounts, &todayOrders)

	// Yesterday's stats for comparison
	var yesterdaySales, yesterdayNetSales int64
	var yesterdayOrders int
	yesterdayArgs := append(args, yesterdayStart, yesterdayEnd)
	_ = m.db.QueryRowContext(r.Context(), `
		SELECT COALESCE(SUM(total),0), COALESCE(SUM(total - discount_amount),0), COUNT(*)
		FROM tickets
		WHERE tenant_id IN (`+inClause+`)
		  AND is_deleted=FALSE
		  AND status NOT IN ('void','open')
		  AND created_at >= $`+fmt.Sprintf("%d", len(args)+1)+`
		  AND created_at <= $`+fmt.Sprintf("%d", len(args)+2),
		yesterdayArgs...,
	).Scan(&yesterdaySales, &yesterdayNetSales, &yesterdayOrders)

	// Sales vs yesterday percentages
	salesVsYesterday := percentChange(yesterdaySales, todaySales)
	netSalesVsYesterday := percentChange(yesterdayNetSales, todayNetSales)
	ordersVsYesterday := percentChange(int64(yesterdayOrders), int64(todayOrders))

	// Payment method breakdown
	payArgs := append(args, todayStart, todayEnd)
	payRows, _ := m.db.QueryContext(r.Context(), `
		SELECT payment_method, COALESCE(SUM(amount),0)
		FROM payments
		WHERE tenant_id IN (`+inClause+`)
		  AND is_deleted=FALSE
		  AND paid_at >= $`+fmt.Sprintf("%d", len(args)+1)+`
		  AND paid_at <= $`+fmt.Sprintf("%d", len(args)+2)+`
		GROUP BY payment_method
	`, payArgs...)

	paymentTotals := map[string]int64{}
	var totalPayments int64
	if payRows != nil {
		defer payRows.Close()
		for payRows.Next() {
			var method string
			var amount int64
			if payRows.Scan(&method, &amount) == nil {
				paymentTotals[method] = amount
				totalPayments += amount
			}
		}
	}

	salesByPayment := make([]PaymentMethodSales, 0)
	for method, amount := range paymentTotals {
		pct := 0
		if totalPayments > 0 {
			pct = int(amount * 100 / totalPayments)
		}
		salesByPayment = append(salesByPayment, PaymentMethodSales{
			Method:     method,
			Amount:     amount,
			Percentage: pct,
		})
	}

	// Order type breakdown
	typeArgs := append(args, todayStart, todayEnd)
	typeRows, _ := m.db.QueryContext(r.Context(), `
		SELECT order_type, COALESCE(SUM(total),0)
		FROM tickets
		WHERE tenant_id IN (`+inClause+`)
		  AND is_deleted=FALSE
		  AND status NOT IN ('void','open')
		  AND created_at >= $`+fmt.Sprintf("%d", len(args)+1)+`
		  AND created_at <= $`+fmt.Sprintf("%d", len(args)+2)+`
		GROUP BY order_type
	`, typeArgs...)

	salesByType := make([]OrderTypeSales, 0)
	if typeRows != nil {
		defer typeRows.Close()
		for typeRows.Next() {
			var ot string
			var amount int64
			if typeRows.Scan(&ot, &amount) == nil {
				pct := 0
				if todaySales > 0 {
					pct = int(amount * 100 / todaySales)
				}
				salesByType = append(salesByType, OrderTypeSales{
					Type:       ot,
					Amount:     amount,
					Percentage: pct,
				})
			}
		}
	}

	// Hourly breakdown
	hourlyArgs := append(args, todayStart, todayEnd)
	hourlyRows, _ := m.db.QueryContext(r.Context(), `
		SELECT EXTRACT(HOUR FROM created_at)::INT, COALESCE(SUM(total),0)
		FROM tickets
		WHERE tenant_id IN (`+inClause+`)
		  AND is_deleted=FALSE
		  AND status NOT IN ('void','open')
		  AND created_at >= $`+fmt.Sprintf("%d", len(args)+1)+`
		  AND created_at <= $`+fmt.Sprintf("%d", len(args)+2)+`
		GROUP BY EXTRACT(HOUR FROM created_at)
	`, hourlyArgs...)

	hourlySales := make([]int64, 24)
	if hourlyRows != nil {
		defer hourlyRows.Close()
		for hourlyRows.Next() {
			var hour int
			var amount int64
			if hourlyRows.Scan(&hour, &amount) == nil && hour >= 0 && hour < 24 {
				hourlySales[hour] = amount
			}
		}
	}

	dashboard := DashboardResponse{
		Sales:               todaySales,
		NetSales:            todayNetSales,
		Orders:              todayOrders,
		SalesVsYesterday:    salesVsYesterday,
		NetSalesVsYesterday: netSalesVsYesterday,
		OrdersVsYesterday:   ordersVsYesterday,
		SalesBreakdown: SalesBreakdown{
			DiscountAmount: todayDiscounts,
			Tax:            todayTax,
			TotalSales:     todaySales,
		},
		SalesByPayment:   salesByPayment,
		SalesByOrderType: salesByType,
		HourlySales:      hourlySales,
	}

	response.JSON(w, http.StatusOK, dashboard)
}

// handleStoreDashboard returns dashboard statistics for a specific store.
// GET /api/v1/admin/dashboard/store/{id}
func (m *Module) handleStoreDashboard(w http.ResponseWriter, r *http.Request) {
	orgID := middleware.GetTenantID(r.Context())
	if orgID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Organization context required")
		return
	}
	storeID := r.PathValue("id")
	if storeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id is required")
		return
	}

	// Verify store belongs to this org
	var exists bool
	err := m.db.QueryRowContext(r.Context(), `
		SELECT EXISTS(SELECT 1 FROM stores WHERE id=$1 AND organization_id=$2)
	`, storeID, orgID).Scan(&exists)
	if err != nil || !exists {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Store not found")
		return
	}

	now := time.Now()
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	yesterdayStart := todayStart.AddDate(0, 0, -1)
	todayEnd := todayStart.Add(24*time.Hour - time.Nanosecond)
	yesterdayEnd := yesterdayStart.Add(24*time.Hour - time.Nanosecond)

	var todaySales, todayNetSales, todayTax, todayDiscounts int64
	var todayOrders int
	_ = m.db.QueryRowContext(r.Context(), `
		SELECT
			COALESCE(SUM(total),0),
			COALESCE(SUM(total - discount_amount),0),
			COALESCE(SUM(tax_amount),0),
			COALESCE(SUM(discount_amount),0),
			COUNT(*)
		FROM tickets
		WHERE tenant_id=$1 AND is_deleted=FALSE
		  AND status NOT IN ('void','open')
		  AND created_at >= $2 AND created_at <= $3
	`, storeID, todayStart, todayEnd).Scan(
		&todaySales, &todayNetSales, &todayTax, &todayDiscounts, &todayOrders)

	var yesterdaySales, yesterdayNetSales int64
	var yesterdayOrders int
	_ = m.db.QueryRowContext(r.Context(), `
		SELECT COALESCE(SUM(total),0), COALESCE(SUM(total - discount_amount),0), COUNT(*)
		FROM tickets
		WHERE tenant_id=$1 AND is_deleted=FALSE
		  AND status NOT IN ('void','open')
		  AND created_at >= $2 AND created_at <= $3
	`, storeID, yesterdayStart, yesterdayEnd).Scan(
		&yesterdaySales, &yesterdayNetSales, &yesterdayOrders)

	salesVsYesterday := percentChange(yesterdaySales, todaySales)
	netSalesVsYesterday := percentChange(yesterdayNetSales, todayNetSales)
	ordersVsYesterday := percentChange(int64(yesterdayOrders), int64(todayOrders))

	// Payment breakdown
	payRows, _ := m.db.QueryContext(r.Context(), `
		SELECT payment_method, COALESCE(SUM(amount),0)
		FROM payments
		WHERE tenant_id=$1 AND is_deleted=FALSE
		  AND paid_at >= $2 AND paid_at <= $3
		GROUP BY payment_method
	`, storeID, todayStart, todayEnd)

	paymentTotals := map[string]int64{}
	var totalPayments int64
	if payRows != nil {
		defer payRows.Close()
		for payRows.Next() {
			var method string
			var amount int64
			if payRows.Scan(&method, &amount) == nil {
				paymentTotals[method] = amount
				totalPayments += amount
			}
		}
	}

	salesByPayment := make([]PaymentMethodSales, 0)
	for method, amount := range paymentTotals {
		pct := 0
		if totalPayments > 0 {
			pct = int(amount * 100 / totalPayments)
		}
		salesByPayment = append(salesByPayment, PaymentMethodSales{
			Method:     method,
			Amount:     amount,
			Percentage: pct,
		})
	}

	// Order type breakdown
	typeRows, _ := m.db.QueryContext(r.Context(), `
		SELECT order_type, COALESCE(SUM(total),0)
		FROM tickets
		WHERE tenant_id=$1 AND is_deleted=FALSE
		  AND status NOT IN ('void','open')
		  AND created_at >= $2 AND created_at <= $3
		GROUP BY order_type
	`, storeID, todayStart, todayEnd)

	salesByType := make([]OrderTypeSales, 0)
	if typeRows != nil {
		defer typeRows.Close()
		for typeRows.Next() {
			var ot string
			var amount int64
			if typeRows.Scan(&ot, &amount) == nil {
				pct := 0
				if todaySales > 0 {
					pct = int(amount * 100 / todaySales)
				}
				salesByType = append(salesByType, OrderTypeSales{
					Type:       ot,
					Amount:     amount,
					Percentage: pct,
				})
			}
		}
	}

	// Hourly breakdown
	hourlyRows, _ := m.db.QueryContext(r.Context(), `
		SELECT EXTRACT(HOUR FROM created_at)::INT, COALESCE(SUM(total),0)
		FROM tickets
		WHERE tenant_id=$1 AND is_deleted=FALSE
		  AND status NOT IN ('void','open')
		  AND created_at >= $2 AND created_at <= $3
		GROUP BY EXTRACT(HOUR FROM created_at)
	`, storeID, todayStart, todayEnd)

	hourlySales := make([]int64, 24)
	if hourlyRows != nil {
		defer hourlyRows.Close()
		for hourlyRows.Next() {
			var hour int
			var amount int64
			if hourlyRows.Scan(&hour, &amount) == nil && hour >= 0 && hour < 24 {
				hourlySales[hour] = amount
			}
		}
	}

	dashboard := DashboardResponse{
		Sales:               todaySales,
		NetSales:            todayNetSales,
		Orders:              todayOrders,
		SalesVsYesterday:    salesVsYesterday,
		NetSalesVsYesterday: netSalesVsYesterday,
		OrdersVsYesterday:   ordersVsYesterday,
		SalesBreakdown: SalesBreakdown{
			DiscountAmount: todayDiscounts,
			Tax:            todayTax,
			TotalSales:     todaySales,
		},
		SalesByPayment:   salesByPayment,
		SalesByOrderType: salesByType,
		HourlySales:      hourlySales,
	}

	response.JSON(w, http.StatusOK, dashboard)
}

// ============================================================
// Helpers
// ============================================================

// generateStoreCode creates a unique store code like "CH00000064".
func generateStoreCode(db *sql.DB, country string) (string, error) {
	// Get the current max code for this country prefix
	var maxCode sql.NullString
	prefix := country
	if len(prefix) != 2 {
		prefix = "CH"
	}

	_ = db.QueryRow(`
		SELECT MAX(store_code)
		FROM stores
		WHERE store_code LIKE $1
	`, prefix+"%").Scan(&maxCode)

	nextNum := 60 // Start from CH00000060
	if maxCode.Valid && len(maxCode.String) > 2 {
		var n int
		fmt.Sscanf(maxCode.String[2:], "%d", &n)
		nextNum = n + 1
	}

	// Add randomness to avoid race conditions
	b := make([]byte, 2)
	rand.Read(b)
	_ = hex.EncodeToString(b)

	return fmt.Sprintf("%s%08d", prefix, nextNum), nil
}

// buildInClause builds a PostgreSQL IN clause placeholder string for a slice of string IDs.
// startIdx is the starting $N index.
func buildInClause(ids []string, startIdx int) (string, []any) {
	clause := ""
	args := make([]any, len(ids))
	for i, id := range ids {
		if i > 0 {
			clause += ", "
		}
		clause += fmt.Sprintf("$%d", startIdx+i)
		args[i] = id
	}
	return clause, args
}

// percentChange returns the percentage change from oldVal to newVal.
func percentChange(oldVal, newVal int64) int {
	if oldVal == 0 {
		if newVal > 0 {
			return 100
		}
		return 0
	}
	return int((newVal - oldVal) * 100 / oldVal)
}

// isUniqueViolation checks if a PostgreSQL error is a unique constraint violation.
func isUniqueViolation(err error) bool {
	if pqErr, ok := err.(*pqlib.Error); ok {
		return pqErr.Code == "23505"
	}
	return false
}

