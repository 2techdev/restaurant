package menu

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

// --- Categories ---

// handleListCategories returns all categories for the tenant.
// GET /api/v1/menu/categories
func (m *Module) handleListCategories(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, name, display_order,
		       COALESCE(color,''), COALESCE(icon,''),
		       COALESCE(parent_id::text,''),
		       is_active, created_at, updated_at
		FROM categories
		WHERE tenant_id = $1 AND is_deleted = false
		ORDER BY display_order ASC, name ASC
	`, tenantID)
	if err != nil {
		slog.Error("menu: list categories", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch categories")
		return
	}
	defer rows.Close()

	categories := []Category{}
	for rows.Next() {
		var c Category
		var color, icon, parentID string
		if err := rows.Scan(
			&c.ID, &c.TenantID, &c.Name, &c.DisplayOrder,
			&color, &icon, &parentID,
			&c.IsActive, &c.CreatedAt, &c.UpdatedAt,
		); err != nil {
			continue
		}
		if color != "" {
			c.Color = &color
		}
		if icon != "" {
			c.Icon = &icon
		}
		if parentID != "" {
			c.ParentID = &parentID
		}
		categories = append(categories, c)
	}
	response.Paginated(w, categories, "", false)
}

// handleCreateCategory creates a new category.
// POST /api/v1/menu/categories
func (m *Module) handleCreateCategory(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	var req struct {
		Name         string  `json:"name"`
		DisplayOrder int     `json:"display_order"`
		Color        *string `json:"color"`
		Icon         *string `json:"icon"`
		ParentID     *string `json:"parent_id"`
		IsActive     bool    `json:"is_active"`
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

	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO categories (id, tenant_id, name, display_order, color, icon, parent_id, is_active, created_at, updated_at, sync_status, is_deleted)
		VALUES ($1, $2, $3, $4, $5, $6, $7::uuid, $8, $9, $9, 0, false)
	`, id, tenantID, req.Name, req.DisplayOrder,
		nullableString(req.Color), nullableString(req.Icon), nullableString(req.ParentID),
		req.IsActive, now,
	)
	if err != nil {
		slog.Error("menu: create category", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create category")
		return
	}

	cat := Category{
		ID:           id,
		TenantID:     tenantID,
		Name:         req.Name,
		DisplayOrder: req.DisplayOrder,
		Color:        req.Color,
		Icon:         req.Icon,
		ParentID:     req.ParentID,
		IsActive:     req.IsActive,
		CreatedAt:    now,
		UpdatedAt:    now,
	}
	response.Created(w, cat)
}

// handleUpdateCategory updates an existing category.
// PUT /api/v1/menu/categories/{id}
func (m *Module) handleUpdateCategory(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")

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
		WHERE id=$6 AND tenant_id=$7 AND is_deleted=false
	`, req.Name, req.DisplayOrder,
		nullableString(req.Color), nullableString(req.Icon),
		req.IsActive, id, tenantID,
	)
	if err != nil {
		slog.Error("menu: update category", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update category")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Category not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"id": id, "status": "updated"})
}

// handleDeleteCategory soft-deletes a category.
// DELETE /api/v1/menu/categories/{id}
func (m *Module) handleDeleteCategory(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")

	res, err := m.db.ExecContext(r.Context(), `
		UPDATE categories SET is_deleted=true, updated_at=NOW()
		WHERE id=$1 AND tenant_id=$2 AND is_deleted=false
	`, id, tenantID)
	if err != nil {
		slog.Error("menu: delete category", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete category")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Category not found")
		return
	}
	response.NoContent(w)
}

// --- Products ---

// handleListProducts returns products with optional category filter.
// GET /api/v1/menu/products?category_id=<id>&active=true
func (m *Module) handleListProducts(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	categoryID := r.URL.Query().Get("category_id")

	var rows *sql.Rows
	var err error
	if categoryID != "" {
		rows, err = m.db.QueryContext(r.Context(), `
			SELECT id, tenant_id, category_id, name, COALESCE(description,''),
			       price, cost_price, tax_group,
			       COALESCE(image_path,''), COALESCE(barcode,''),
			       is_active, display_order, prep_time_minutes,
			       COALESCE(printer_group,'kitchen'), created_at, updated_at
			FROM products
			WHERE tenant_id=$1 AND category_id=$2 AND is_deleted=false
			ORDER BY display_order ASC, name ASC
		`, tenantID, categoryID)
	} else {
		rows, err = m.db.QueryContext(r.Context(), `
			SELECT id, tenant_id, category_id, name, COALESCE(description,''),
			       price, cost_price, tax_group,
			       COALESCE(image_path,''), COALESCE(barcode,''),
			       is_active, display_order, prep_time_minutes,
			       COALESCE(printer_group,'kitchen'), created_at, updated_at
			FROM products
			WHERE tenant_id=$1 AND is_deleted=false
			ORDER BY display_order ASC, name ASC
		`, tenantID)
	}
	if err != nil {
		slog.Error("menu: list products", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch products")
		return
	}
	defer rows.Close()

	products := []Product{}
	for rows.Next() {
		var p Product
		var desc, imagePath, barcode string
		var prepTime sql.NullInt64
		if err := rows.Scan(
			&p.ID, &p.TenantID, &p.CategoryID, &p.Name, &desc,
			&p.Price, &p.CostPrice, &p.TaxGroup,
			&imagePath, &barcode,
			&p.IsActive, &p.DisplayOrder, &prepTime,
			&p.PrinterGroup, &p.CreatedAt, &p.UpdatedAt,
		); err != nil {
			continue
		}
		if desc != "" {
			p.Description = &desc
		}
		if imagePath != "" {
			p.ImagePath = &imagePath
		}
		if barcode != "" {
			p.Barcode = &barcode
		}
		if prepTime.Valid {
			v := int(prepTime.Int64)
			p.PrepTimeMinutes = &v
		}
		products = append(products, p)
	}
	response.Paginated(w, products, "", false)
}

// handleCreateProduct creates a new product.
// POST /api/v1/menu/products
func (m *Module) handleCreateProduct(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
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
		IsActive        bool    `json:"is_active"`
		DisplayOrder    int     `json:"display_order"`
		PrepTimeMinutes *int    `json:"prep_time_minutes"`
		PrinterGroup    string  `json:"printer_group"`
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

	id := uuid.New()
	now := time.Now().UTC()

	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO products (
			id, tenant_id, category_id, name, description, price, cost_price,
			tax_group, image_path, barcode, is_active, display_order,
			prep_time_minutes, printer_group, created_at, updated_at, sync_status, is_deleted
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$15,0,false)
	`, id, tenantID, req.CategoryID, req.Name,
		nullableString(req.Description), req.Price, req.CostPrice,
		req.TaxGroup, nullableString(req.ImagePath), nullableString(req.Barcode),
		req.IsActive, req.DisplayOrder,
		nullableInt(req.PrepTimeMinutes), req.PrinterGroup, now,
	)
	if err != nil {
		slog.Error("menu: create product", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create product")
		return
	}

	prod := Product{
		ID:              id,
		TenantID:        tenantID,
		CategoryID:      req.CategoryID,
		Name:            req.Name,
		Description:     req.Description,
		Price:           req.Price,
		CostPrice:       req.CostPrice,
		TaxGroup:        req.TaxGroup,
		ImagePath:       req.ImagePath,
		Barcode:         req.Barcode,
		IsActive:        req.IsActive,
		DisplayOrder:    req.DisplayOrder,
		PrepTimeMinutes: req.PrepTimeMinutes,
		PrinterGroup:    req.PrinterGroup,
		CreatedAt:       now,
		UpdatedAt:       now,
	}
	response.Created(w, prod)
}

// handleUpdateProduct updates an existing product.
// PUT /api/v1/menu/products/{id}
func (m *Module) handleUpdateProduct(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")

	var req struct {
		Name            string  `json:"name"`
		Description     *string `json:"description"`
		Price           int64   `json:"price"`
		CostPrice       int64   `json:"cost_price"`
		TaxGroup        string  `json:"tax_group"`
		ImagePath       *string `json:"image_path"`
		IsActive        bool    `json:"is_active"`
		DisplayOrder    int     `json:"display_order"`
		PrepTimeMinutes *int    `json:"prep_time_minutes"`
		CategoryID      string  `json:"category_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	res, err := m.db.ExecContext(r.Context(), `
		UPDATE products
		SET name=$1, description=$2, price=$3, cost_price=$4, tax_group=$5,
		    image_path=$6, is_active=$7, display_order=$8,
		    prep_time_minutes=$9, category_id=$10, updated_at=NOW()
		WHERE id=$11 AND tenant_id=$12 AND is_deleted=false
	`, req.Name, nullableString(req.Description), req.Price, req.CostPrice, req.TaxGroup,
		nullableString(req.ImagePath), req.IsActive, req.DisplayOrder,
		nullableInt(req.PrepTimeMinutes), req.CategoryID,
		id, tenantID,
	)
	if err != nil {
		slog.Error("menu: update product", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update product")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Product not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"id": id, "status": "updated"})
}

// handleDeleteProduct soft-deletes a product.
// DELETE /api/v1/menu/products/{id}
func (m *Module) handleDeleteProduct(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")

	res, err := m.db.ExecContext(r.Context(), `
		UPDATE products SET is_deleted=true, updated_at=NOW()
		WHERE id=$1 AND tenant_id=$2 AND is_deleted=false
	`, id, tenantID)
	if err != nil {
		slog.Error("menu: delete product", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete product")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Product not found")
		return
	}
	response.NoContent(w)
}

// --- Modifiers ---

// handleListModifiers returns modifier groups with their modifiers.
// GET /api/v1/menu/modifiers?product_id=<id>
func (m *Module) handleListModifiers(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	productID := r.URL.Query().Get("product_id")

	var rows *sql.Rows
	var err error
	if productID != "" {
		rows, err = m.db.QueryContext(r.Context(), `
			SELECT mg.id, mg.tenant_id, mg.name, mg.selection_type,
			       mg.min_selections, mg.max_selections, mg.is_required,
			       mg.display_order, mg.created_at, mg.updated_at
			FROM modifier_groups mg
			JOIN product_modifier_groups pmg ON pmg.modifier_group_id = mg.id
			WHERE pmg.product_id = $1 AND mg.tenant_id = $2 AND mg.is_deleted = false
			ORDER BY pmg.display_order ASC, mg.display_order ASC
		`, productID, tenantID)
	} else {
		rows, err = m.db.QueryContext(r.Context(), `
			SELECT id, tenant_id, name, selection_type,
			       min_selections, max_selections, is_required,
			       display_order, created_at, updated_at
			FROM modifier_groups
			WHERE tenant_id=$1 AND is_deleted=false
			ORDER BY display_order ASC
		`, tenantID)
	}
	if err != nil {
		slog.Error("menu: list modifiers", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch modifiers")
		return
	}
	defer rows.Close()

	groups := []ModifierGroup{}
	for rows.Next() {
		var g ModifierGroup
		if err := rows.Scan(
			&g.ID, &g.TenantID, &g.Name, &g.SelectionType,
			&g.MinSelections, &g.MaxSelections, &g.IsRequired,
			&g.DisplayOrder, &g.CreatedAt, &g.UpdatedAt,
		); err != nil {
			continue
		}
		g.Modifiers = m.fetchModifiers(r, g.ID)
		groups = append(groups, g)
	}
	response.JSON(w, http.StatusOK, groups)
}

// fetchModifiers loads modifiers for a group.
func (m *Module) fetchModifiers(r *http.Request, groupID string) []Modifier {
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, group_id, name, price_delta, is_default, display_order, created_at, updated_at
		FROM modifiers
		WHERE group_id=$1 AND is_deleted=false
		ORDER BY display_order ASC
	`, groupID)
	if err != nil {
		return nil
	}
	defer rows.Close()

	var mods []Modifier
	for rows.Next() {
		var mod Modifier
		if err := rows.Scan(
			&mod.ID, &mod.TenantID, &mod.GroupID, &mod.Name,
			&mod.PriceDelta, &mod.IsDefault, &mod.DisplayOrder,
			&mod.CreatedAt, &mod.UpdatedAt,
		); err == nil {
			mods = append(mods, mod)
		}
	}
	return mods
}

// nullableString converts a *string to nil if the pointer is nil or points to "".
func nullableString(s *string) interface{} {
	if s == nil || *s == "" {
		return nil
	}
	return *s
}

// nullableInt converts a *int to nil if the pointer is nil.
func nullableInt(n *int) interface{} {
	if n == nil {
		return nil
	}
	return *n
}
