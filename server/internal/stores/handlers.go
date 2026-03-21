package stores

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

// ============================================================
// Organization handlers
// ============================================================

// handleGetOrganization returns the current organization.
// GET /api/v1/admin/organization
func (m *Module) handleGetOrganization(w http.ResponseWriter, r *http.Request) {
	// TODO: Extract org_id from JWT claims via middleware context
	// TODO: Query organization from database

	trialEnd := time.Date(2026, 6, 30, 23, 59, 59, 0, time.UTC)
	org := Organization{
		ID:          "org_01JQXYZ123456789ABCDEF",
		Name:        "2TECH Technology AG",
		LegalName:   "2TECH Technology AG",
		TaxID:       "CHE-123.456.789",
		Country:     "CH",
		Address:     "Bahnhofstrasse 10, 8001 Zurich",
		Phone:       "+41 44 123 45 67",
		Email:       "info@2tech.ch",
		Logo:        "",
		Plan:        "professional",
		Status:      "active",
		TrialEndsAt: &trialEnd,
		CreatedAt:   time.Date(2024, 1, 15, 10, 0, 0, 0, time.UTC),
		UpdatedAt:   time.Now().UTC(),
	}

	response.JSON(w, http.StatusOK, org)
}

// handleUpdateOrganization updates the current organization.
// PUT /api/v1/admin/organization
func (m *Module) handleUpdateOrganization(w http.ResponseWriter, r *http.Request) {
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

	// TODO: Validate and update organization in database

	trialEnd := time.Date(2026, 6, 30, 23, 59, 59, 0, time.UTC)
	org := Organization{
		ID:          "org_01JQXYZ123456789ABCDEF",
		Name:        req.Name,
		LegalName:   req.LegalName,
		TaxID:       req.TaxID,
		Country:     "CH",
		Address:     req.Address,
		Phone:       req.Phone,
		Email:       req.Email,
		Logo:        req.Logo,
		Plan:        "professional",
		Status:      "active",
		TrialEndsAt: &trialEnd,
		CreatedAt:   time.Date(2024, 1, 15, 10, 0, 0, 0, time.UTC),
		UpdatedAt:   time.Now().UTC(),
	}

	response.JSON(w, http.StatusOK, org)
}

// ============================================================
// Brand handlers
// ============================================================

// handleListBrands returns all brands for the current organization.
// GET /api/v1/admin/brands
func (m *Module) handleListBrands(w http.ResponseWriter, r *http.Request) {
	// TODO: Extract org_id from JWT claims, query brands from database

	brands := []Brand{
		{
			ID:             "brand_01JR0001",
			OrganizationID: "org_01JQXYZ123456789ABCDEF",
			Name:           "Schore Pintli Restaurant",
			Logo:           "",
			Description:    "Traditional Swiss cuisine",
			Status:         "active",
			CreatedAt:      time.Date(2024, 1, 15, 10, 0, 0, 0, time.UTC),
			UpdatedAt:      time.Now().UTC(),
		},
		{
			ID:             "brand_01JR0002",
			OrganizationID: "org_01JQXYZ123456789ABCDEF",
			Name:           "Quick Bites Express",
			Logo:           "",
			Description:    "Fast casual dining",
			Status:         "active",
			CreatedAt:      time.Date(2024, 3, 1, 10, 0, 0, 0, time.UTC),
			UpdatedAt:      time.Now().UTC(),
		},
	}

	response.JSON(w, http.StatusOK, brands)
}

// handleCreateBrand creates a new brand.
// POST /api/v1/admin/brands
func (m *Module) handleCreateBrand(w http.ResponseWriter, r *http.Request) {
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

	// TODO: Insert brand into database

	brand := Brand{
		ID:             "brand_01JR0003",
		OrganizationID: "org_01JQXYZ123456789ABCDEF",
		Name:           req.Name,
		Logo:           req.Logo,
		Description:    req.Description,
		Status:         "active",
		CreatedAt:      time.Now().UTC(),
		UpdatedAt:      time.Now().UTC(),
	}

	response.Created(w, brand)
}

// handleUpdateBrand updates an existing brand.
// PUT /api/v1/admin/brands/{id}
func (m *Module) handleUpdateBrand(w http.ResponseWriter, r *http.Request) {
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

	// TODO: Update brand in database

	brand := Brand{
		ID:             brandID,
		OrganizationID: "org_01JQXYZ123456789ABCDEF",
		Name:           req.Name,
		Logo:           req.Logo,
		Description:    req.Description,
		Status:         "active",
		CreatedAt:      time.Date(2024, 1, 15, 10, 0, 0, 0, time.UTC),
		UpdatedAt:      time.Now().UTC(),
	}

	response.JSON(w, http.StatusOK, brand)
}

// handleDeleteBrand deactivates a brand (soft delete).
// DELETE /api/v1/admin/brands/{id}
func (m *Module) handleDeleteBrand(w http.ResponseWriter, r *http.Request) {
	brandID := r.PathValue("id")
	if brandID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "brand id is required")
		return
	}

	// TODO: Set brand status to "inactive" in database
	// TODO: Check for active stores under this brand

	response.NoContent(w)
}

// ============================================================
// Store handlers
// ============================================================

// handleListStores returns all stores with optional filtering.
// GET /api/v1/admin/stores?name=&code=&status=&brand_id=
func (m *Module) handleListStores(w http.ResponseWriter, r *http.Request) {
	// Parse query parameters for filtering
	_ = r.URL.Query().Get("name")
	_ = r.URL.Query().Get("code")
	_ = r.URL.Query().Get("status")
	_ = r.URL.Query().Get("brand_id")

	// TODO: Build dynamic query with filters, extract org_id from JWT

	exp1 := time.Date(2026, 12, 31, 23, 59, 59, 0, time.UTC)
	exp2 := time.Date(2026, 12, 31, 23, 59, 59, 0, time.UTC)
	exp3 := time.Date(2027, 6, 30, 23, 59, 59, 0, time.UTC)

	stores := []Store{
		{
			ID:             "store_01JS0001",
			BrandID:        "brand_01JR0001",
			OrganizationID: "org_01JQXYZ123456789ABCDEF",
			StoreCode:      "CH00000060",
			Name:           "Zurich Main",
			LegalName:      "Schore Pintli AG - Zurich",
			Country:        "CH",
			Address:        "Bahnhofstrasse 42",
			City:           "Zurich",
			PostalCode:     "8001",
			Phone:          "+41 44 210 00 01",
			Email:          "zurich@schorepintli.ch",
			Timezone:       "Europe/Zurich",
			Currency:       "CHF",
			TaxRate:        8.1,
			ProductCount:   85,
			TableCount:     24,
			DeviceCount:    3,
			ManagerName:    "Hans Mueller",
			Status:         "active",
			ExpiresAt:      &exp1,
			CreatedAt:      time.Date(2024, 1, 15, 10, 0, 0, 0, time.UTC),
			UpdatedAt:      time.Now().UTC(),
		},
		{
			ID:             "store_01JS0002",
			BrandID:        "brand_01JR0001",
			OrganizationID: "org_01JQXYZ123456789ABCDEF",
			StoreCode:      "CH00000061",
			Name:           "Bern Branch",
			LegalName:      "Schore Pintli AG - Bern",
			Country:        "CH",
			Address:        "Marktgasse 15",
			City:           "Bern",
			PostalCode:     "3011",
			Phone:          "+41 31 310 00 02",
			Email:          "bern@schorepintli.ch",
			Timezone:       "Europe/Zurich",
			Currency:       "CHF",
			TaxRate:        8.1,
			ProductCount:   72,
			TableCount:     18,
			DeviceCount:    2,
			ManagerName:    "Anna Fischer",
			Status:         "active",
			ExpiresAt:      &exp2,
			CreatedAt:      time.Date(2024, 6, 1, 10, 0, 0, 0, time.UTC),
			UpdatedAt:      time.Now().UTC(),
		},
		{
			ID:             "store_01JS0003",
			BrandID:        "brand_01JR0002",
			OrganizationID: "org_01JQXYZ123456789ABCDEF",
			StoreCode:      "CH00000062",
			Name:           "Basel Express",
			LegalName:      "Quick Bites GmbH - Basel",
			Country:        "CH",
			Address:        "Freie Strasse 28",
			City:           "Basel",
			PostalCode:     "4001",
			Phone:          "+41 61 260 00 03",
			Email:          "basel@quickbites.ch",
			Timezone:       "Europe/Zurich",
			Currency:       "CHF",
			TaxRate:        8.1,
			ProductCount:   45,
			TableCount:     12,
			DeviceCount:    2,
			ManagerName:    "Peter Weber",
			Status:         "active",
			ExpiresAt:      &exp3,
			CreatedAt:      time.Date(2025, 1, 10, 10, 0, 0, 0, time.UTC),
			UpdatedAt:      time.Now().UTC(),
		},
	}

	response.JSON(w, http.StatusOK, stores)
}

// handleCreateStore creates a new store.
// POST /api/v1/admin/stores
func (m *Module) handleCreateStore(w http.ResponseWriter, r *http.Request) {
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

	// TODO: Generate store_code, insert into database

	// Default timezone and currency for Swiss stores
	tz := req.Timezone
	if tz == "" {
		tz = "Europe/Zurich"
	}
	cur := req.Currency
	if cur == "" {
		cur = "CHF"
	}
	taxRate := req.TaxRate
	if taxRate == 0 {
		taxRate = 8.1
	}

	store := Store{
		ID:             "store_01JS0004",
		BrandID:        req.BrandID,
		OrganizationID: "org_01JQXYZ123456789ABCDEF",
		StoreCode:      "CH00000063",
		Name:           req.Name,
		LegalName:      req.LegalName,
		Country:        req.Country,
		Address:        req.Address,
		City:           req.City,
		PostalCode:     req.PostalCode,
		Phone:          req.Phone,
		Email:          req.Email,
		Timezone:       tz,
		Currency:       cur,
		TaxRate:        taxRate,
		ProductCount:   0,
		TableCount:     0,
		DeviceCount:    0,
		ManagerName:    req.ManagerName,
		Status:         "active",
		CreatedAt:      time.Now().UTC(),
		UpdatedAt:      time.Now().UTC(),
	}

	response.Created(w, store)
}

// handleGetStore returns a single store with counts.
// GET /api/v1/admin/stores/{id}
func (m *Module) handleGetStore(w http.ResponseWriter, r *http.Request) {
	storeID := r.PathValue("id")
	if storeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id is required")
		return
	}

	// TODO: Query store from database with product/table/device counts

	exp := time.Date(2026, 12, 31, 23, 59, 59, 0, time.UTC)
	store := Store{
		ID:             storeID,
		BrandID:        "brand_01JR0001",
		OrganizationID: "org_01JQXYZ123456789ABCDEF",
		StoreCode:      "CH00000060",
		Name:           "Zurich Main",
		LegalName:      "Schore Pintli AG - Zurich",
		Country:        "CH",
		Address:        "Bahnhofstrasse 42",
		City:           "Zurich",
		PostalCode:     "8001",
		Phone:          "+41 44 210 00 01",
		Email:          "zurich@schorepintli.ch",
		Timezone:       "Europe/Zurich",
		Currency:       "CHF",
		TaxRate:        8.1,
		ProductCount:   85,
		TableCount:     24,
		DeviceCount:    3,
		ManagerName:    "Hans Mueller",
		Status:         "active",
		ExpiresAt:      &exp,
		CreatedAt:      time.Date(2024, 1, 15, 10, 0, 0, 0, time.UTC),
		UpdatedAt:      time.Now().UTC(),
	}

	response.JSON(w, http.StatusOK, store)
}

// handleUpdateStore updates an existing store.
// PUT /api/v1/admin/stores/{id}
func (m *Module) handleUpdateStore(w http.ResponseWriter, r *http.Request) {
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

	// TODO: Update store in database

	exp := time.Date(2026, 12, 31, 23, 59, 59, 0, time.UTC)
	store := Store{
		ID:             storeID,
		BrandID:        "brand_01JR0001",
		OrganizationID: "org_01JQXYZ123456789ABCDEF",
		StoreCode:      "CH00000060",
		Name:           req.Name,
		LegalName:      req.LegalName,
		Country:        "CH",
		Address:        req.Address,
		City:           req.City,
		PostalCode:     req.PostalCode,
		Phone:          req.Phone,
		Email:          req.Email,
		Timezone:       req.Timezone,
		Currency:       req.Currency,
		TaxRate:        req.TaxRate,
		ProductCount:   85,
		TableCount:     24,
		DeviceCount:    3,
		ManagerName:    req.ManagerName,
		Status:         req.Status,
		ExpiresAt:      &exp,
		CreatedAt:      time.Date(2024, 1, 15, 10, 0, 0, 0, time.UTC),
		UpdatedAt:      time.Now().UTC(),
	}

	response.JSON(w, http.StatusOK, store)
}

// handleDeleteStore deactivates a store (soft delete).
// DELETE /api/v1/admin/stores/{id}
func (m *Module) handleDeleteStore(w http.ResponseWriter, r *http.Request) {
	storeID := r.PathValue("id")
	if storeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id is required")
		return
	}

	// TODO: Set store status to "inactive" in database
	// TODO: Deactivate all devices and employees under this store

	response.NoContent(w)
}

// handleGetStoreStats returns statistics for a specific store.
// GET /api/v1/admin/stores/{id}/stats
func (m *Module) handleGetStoreStats(w http.ResponseWriter, r *http.Request) {
	storeID := r.PathValue("id")
	if storeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id is required")
		return
	}

	// TODO: Query aggregated stats from tickets, payments, devices tables

	stats := StoreStats{
		StoreID:       storeID,
		StoreName:     "Zurich Main",
		TodaySales:    222500,
		TodayOrders:   222,
		WeekSales:     1485000,
		WeekOrders:    1540,
		MonthSales:    5920000,
		MonthOrders:   6120,
		ActiveDevices: 3,
		ActiveStaff:   8,
	}

	response.JSON(w, http.StatusOK, stats)
}

// ============================================================
// Admin User handlers
// ============================================================

// handleListAdminUsers returns all admin users for the organization.
// GET /api/v1/admin/users
func (m *Module) handleListAdminUsers(w http.ResponseWriter, r *http.Request) {
	// TODO: Extract org_id from JWT, query admin_users

	lastLogin := time.Now().Add(-2 * time.Hour)
	users := []AdminUser{
		{
			ID:             "adm_01JU0001",
			OrganizationID: "org_01JQXYZ123456789ABCDEF",
			Email:          "admin@2tech.ch",
			Name:           "System Admin",
			Role:           "org_admin",
			StoreIDs:       nil,
			Status:         "active",
			LastLoginAt:    &lastLogin,
			CreatedAt:      time.Date(2024, 1, 15, 10, 0, 0, 0, time.UTC),
			UpdatedAt:      time.Now().UTC(),
		},
		{
			ID:             "adm_01JU0002",
			OrganizationID: "org_01JQXYZ123456789ABCDEF",
			Email:          "hans@schorepintli.ch",
			Name:           "Hans Mueller",
			Role:           "store_manager",
			StoreIDs:       []string{"store_01JS0001"},
			Status:         "active",
			LastLoginAt:    &lastLogin,
			CreatedAt:      time.Date(2024, 2, 1, 10, 0, 0, 0, time.UTC),
			UpdatedAt:      time.Now().UTC(),
		},
		{
			ID:             "adm_01JU0003",
			OrganizationID: "org_01JQXYZ123456789ABCDEF",
			Email:          "anna@schorepintli.ch",
			Name:           "Anna Fischer",
			Role:           "store_manager",
			StoreIDs:       []string{"store_01JS0002"},
			Status:         "active",
			LastLoginAt:    nil,
			CreatedAt:      time.Date(2024, 6, 1, 10, 0, 0, 0, time.UTC),
			UpdatedAt:      time.Now().UTC(),
		},
	}

	response.JSON(w, http.StatusOK, users)
}

// handleCreateAdminUser creates a new admin user.
// POST /api/v1/admin/users
func (m *Module) handleCreateAdminUser(w http.ResponseWriter, r *http.Request) {
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

	// TODO: Hash password with bcrypt, insert into admin_users table
	// TODO: Check for duplicate email

	role := req.Role
	if role == "" {
		role = "viewer"
	}

	user := AdminUser{
		ID:             "adm_01JU0004",
		OrganizationID: "org_01JQXYZ123456789ABCDEF",
		Email:          req.Email,
		Name:           req.Name,
		Role:           role,
		StoreIDs:       req.StoreIDs,
		Status:         "active",
		CreatedAt:      time.Now().UTC(),
		UpdatedAt:      time.Now().UTC(),
	}

	response.Created(w, user)
}

// handleUpdateAdminUser updates an existing admin user.
// PUT /api/v1/admin/users/{id}
func (m *Module) handleUpdateAdminUser(w http.ResponseWriter, r *http.Request) {
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

	// TODO: Update admin user in database

	user := AdminUser{
		ID:             userID,
		OrganizationID: "org_01JQXYZ123456789ABCDEF",
		Email:          "updated@2tech.ch",
		Name:           req.Name,
		Role:           req.Role,
		StoreIDs:       req.StoreIDs,
		Status:         req.Status,
		CreatedAt:      time.Date(2024, 1, 15, 10, 0, 0, 0, time.UTC),
		UpdatedAt:      time.Now().UTC(),
	}

	response.JSON(w, http.StatusOK, user)
}

// handleDeleteAdminUser deactivates an admin user (soft delete).
// DELETE /api/v1/admin/users/{id}
func (m *Module) handleDeleteAdminUser(w http.ResponseWriter, r *http.Request) {
	userID := r.PathValue("id")
	if userID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "user id is required")
		return
	}

	// TODO: Set admin user status to "inactive" in database

	response.NoContent(w)
}

// ============================================================
// Employee handlers
// ============================================================

// handleListEmployees returns all employees for a specific store.
// GET /api/v1/admin/stores/{id}/employees
func (m *Module) handleListEmployees(w http.ResponseWriter, r *http.Request) {
	storeID := r.PathValue("id")
	if storeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id is required")
		return
	}

	// TODO: Query employees for the given store_id and org_id

	employees := []Employee{
		{
			ID:             "emp_01JV0001",
			StoreID:        storeID,
			OrganizationID: "org_01JQXYZ123456789ABCDEF",
			Name:           "Marco Rossi",
			Role:           "manager",
			IsActive:       true,
			Phone:          "+41 79 100 00 01",
			Email:          "marco@schorepintli.ch",
			CreatedAt:      time.Date(2024, 1, 20, 10, 0, 0, 0, time.UTC),
			UpdatedAt:      time.Now().UTC(),
		},
		{
			ID:             "emp_01JV0002",
			StoreID:        storeID,
			OrganizationID: "org_01JQXYZ123456789ABCDEF",
			Name:           "Lisa Schmidt",
			Role:           "waiter",
			IsActive:       true,
			Phone:          "+41 79 100 00 02",
			CreatedAt:      time.Date(2024, 2, 1, 10, 0, 0, 0, time.UTC),
			UpdatedAt:      time.Now().UTC(),
		},
		{
			ID:             "emp_01JV0003",
			StoreID:        storeID,
			OrganizationID: "org_01JQXYZ123456789ABCDEF",
			Name:           "Thomas Keller",
			Role:           "kitchen",
			IsActive:       true,
			Phone:          "+41 79 100 00 03",
			CreatedAt:      time.Date(2024, 2, 15, 10, 0, 0, 0, time.UTC),
			UpdatedAt:      time.Now().UTC(),
		},
		{
			ID:             "emp_01JV0004",
			StoreID:        storeID,
			OrganizationID: "org_01JQXYZ123456789ABCDEF",
			Name:           "Sarah Brunner",
			Role:           "cashier",
			IsActive:       true,
			Phone:          "+41 79 100 00 04",
			CreatedAt:      time.Date(2024, 3, 1, 10, 0, 0, 0, time.UTC),
			UpdatedAt:      time.Now().UTC(),
		},
	}

	response.JSON(w, http.StatusOK, employees)
}

// handleCreateEmployee creates a new employee for a store.
// POST /api/v1/admin/stores/{id}/employees
func (m *Module) handleCreateEmployee(w http.ResponseWriter, r *http.Request) {
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

	// TODO: Hash PIN, insert into employees table

	role := req.Role
	if role == "" {
		role = "waiter"
	}

	employee := Employee{
		ID:             "emp_01JV0005",
		StoreID:        storeID,
		OrganizationID: "org_01JQXYZ123456789ABCDEF",
		Name:           req.Name,
		Role:           role,
		IsActive:       true,
		Phone:          req.Phone,
		Email:          req.Email,
		Permissions:    req.Permissions,
		CreatedAt:      time.Now().UTC(),
		UpdatedAt:      time.Now().UTC(),
	}

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

	// TODO: Update employee in database

	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}

	employee := Employee{
		ID:             employeeID,
		StoreID:        "store_01JS0001",
		OrganizationID: "org_01JQXYZ123456789ABCDEF",
		Name:           req.Name,
		Role:           req.Role,
		IsActive:       isActive,
		Phone:          req.Phone,
		Email:          req.Email,
		Permissions:    req.Permissions,
		CreatedAt:      time.Date(2024, 1, 20, 10, 0, 0, 0, time.UTC),
		UpdatedAt:      time.Now().UTC(),
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

	// TODO: Set employee is_active to false in database

	response.NoContent(w)
}

// ============================================================
// Dashboard handlers
// ============================================================

// handleDashboard returns organization-wide dashboard statistics.
// GET /api/v1/admin/dashboard
func (m *Module) handleDashboard(w http.ResponseWriter, r *http.Request) {
	// TODO: Extract org_id from JWT, aggregate across all stores
	// TODO: Query tickets, payments for today vs yesterday comparison

	dashboard := DashboardResponse{
		Sales:               222500,
		NetSales:            210107,
		Orders:              222,
		SalesVsYesterday:    0,
		NetSalesVsYesterday: -21,
		OrdersVsYesterday:   -21,
		SalesBreakdown: SalesBreakdown{
			DiscountAmount: -250,
			Tax:            10346,
			TotalSales:     222500,
		},
		SalesByPayment: []PaymentMethodSales{
			{Method: "cash", Amount: 116970, Percentage: 53},
			{Method: "card", Amount: 105530, Percentage: 47},
		},
		SalesByOrderType: []OrderTypeSales{
			{Type: "dine_in", Amount: 150000, Percentage: 67},
			{Type: "takeaway", Amount: 72500, Percentage: 33},
		},
		HourlySales: []int64{
			0, 0, 0, 0, 0, 0, 0, 0,
			5000, 15000, 35000, 80000,
			45000, 20000, 10000, 0,
			0, 0, 0, 0, 0, 0, 0, 0,
		},
	}

	response.JSON(w, http.StatusOK, dashboard)
}

// handleStoreDashboard returns dashboard statistics for a specific store.
// GET /api/v1/admin/dashboard/store/{id}
func (m *Module) handleStoreDashboard(w http.ResponseWriter, r *http.Request) {
	storeID := r.PathValue("id")
	if storeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id is required")
		return
	}

	// TODO: Extract org_id from JWT, verify store belongs to org
	// TODO: Query tickets, payments for this specific store

	dashboard := DashboardResponse{
		Sales:               145200,
		NetSales:            137100,
		Orders:              148,
		SalesVsYesterday:    5,
		NetSalesVsYesterday: 3,
		OrdersVsYesterday:   -8,
		SalesBreakdown: SalesBreakdown{
			DiscountAmount: -150,
			Tax:            6700,
			TotalSales:     145200,
		},
		SalesByPayment: []PaymentMethodSales{
			{Method: "cash", Amount: 72600, Percentage: 50},
			{Method: "card", Amount: 65340, Percentage: 45},
			{Method: "twint", Amount: 7260, Percentage: 5},
		},
		SalesByOrderType: []OrderTypeSales{
			{Type: "dine_in", Amount: 101640, Percentage: 70},
			{Type: "takeaway", Amount: 36300, Percentage: 25},
			{Type: "delivery", Amount: 7260, Percentage: 5},
		},
		HourlySales: []int64{
			0, 0, 0, 0, 0, 0, 0, 0,
			3200, 9800, 22000, 52000,
			30000, 14000, 7200, 0,
			0, 0, 5000, 2000, 0, 0, 0, 0,
		},
	}

	response.JSON(w, http.StatusOK, dashboard)
}
