package menu

// Cloud-master menu sync — version / snapshot / publish endpoints.
//
// The Go backend is the authoritative source of menu data. POS clients pull
// the current version number first (cheap), then the JSON snapshot only when
// the version changed. Backoffice users press "Publish" to freeze the live
// menu tables into an immutable JSON snapshot row in `menu_versions`.
//
// Auth model:
//   - GET  /api/v1/menu/version/{tenantId}      — JWT  OR  X-API-Key
//   - GET  /api/v1/menu/snapshot/{tenantId}     — JWT  OR  X-API-Key
//   - POST /api/v1/menu/publish/{tenantId}      — JWT  only (admin/brand_manager)
//   - POST /api/v1/admin/tenants/{tenantId}/api-key
//                                                — JWT  only (admin/brand_manager)
//
// Wire format follows docs/menu-sync/CONTRACT.md (schemaVersion=1).

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/crypto"
	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

const schemaVersion = 1

// ---------------------------------------------------------------------------
// Snapshot DTO — must match docs/menu-sync/CONTRACT.md §3 exactly.
// ---------------------------------------------------------------------------

type snapshot struct {
	SchemaVersion   int             `json:"schemaVersion"`
	TenantID        string          `json:"tenantId"`
	MenuVersion     int             `json:"menuVersion"`
	PublishedAt     time.Time       `json:"publishedAt"`
	Currency        string          `json:"currency"`
	Locale          string          `json:"locale"`
	Business        snapBusiness    `json:"business"`
	TaxProfiles     []snapTax       `json:"taxProfiles"`
	Categories      []snapCategory  `json:"categories"`
	Products        []snapProduct   `json:"products"`
	ModifierGroups  []snapModGroup  `json:"modifierGroups"`
	HappyHourRules  []any           `json:"happyHourRules"`
	Gangs           []any           `json:"gangs"`
	ReceiptTemplate snapReceiptTmpl `json:"receiptTemplate"`
}

type snapBusiness struct {
	Name         string  `json:"name"`
	Address      string  `json:"address"`
	Phone        string  `json:"phone"`
	Email        string  `json:"email"`
	MwstNr       string  `json:"mwstNr"`
	LogoURL      *string `json:"logoUrl"`
	PrimaryColor string  `json:"primaryColor"`
}

type snapTax struct {
	ID              string  `json:"id"`
	CountryCode     string  `json:"countryCode"`
	OrderType       string  `json:"orderType"`
	ProductTaxGroup string  `json:"productTaxGroup"`
	TaxRate         float64 `json:"taxRate"`
	TaxName         string  `json:"taxName"`
	IsDefault       bool    `json:"isDefault"`
	ValidFrom       *string `json:"validFrom"`
	ValidUntil      *string `json:"validUntil"`
}

type snapCategory struct {
	ID               string       `json:"id"`
	Name             string       `json:"name"`
	NameTranslations Translations `json:"nameTranslations"`
	DisplayOrder     int          `json:"displayOrder"`
	Color            *string      `json:"color"`
	Icon             *string      `json:"icon"`
	ParentID         *string      `json:"parentId"`
	IsActive         bool         `json:"isActive"`
	DefaultGangID    *string      `json:"defaultGangId"`
}

type snapProduct struct {
	ID                      string       `json:"id"`
	CategoryID              string       `json:"categoryId"`
	Name                    string       `json:"name"`
	NameTranslations        Translations `json:"nameTranslations"`
	Description             string       `json:"description"`
	DescriptionTranslations Translations `json:"descriptionTranslations"`
	PriceCents        int64   `json:"priceCents"`
	CostPriceCents    int64   `json:"costPriceCents"`
	TaxGroup          string  `json:"taxGroup"`
	ImageURL          *string `json:"imageUrl"`
	Barcode           *string `json:"barcode"`
	IsActive          bool    `json:"isActive"`
	IsAvailable       bool    `json:"isAvailable"`
	DisplayOrder      int     `json:"displayOrder"`
	PrepTimeMinutes   *int    `json:"prepTimeMinutes"`
	PrinterGroup      string  `json:"printerGroup"`
	ButtonColor       *string `json:"buttonColor"`
	DefaultGangID     *string `json:"defaultGangId"`
	IsCombo           bool    `json:"isCombo"`
	ComboDiscountCent *int64  `json:"comboDiscountCents"`
	StockStatus       string  `json:"stockStatus"`
	IsOpenPrice       bool    `json:"isOpenPrice"`
	IsWeightBased     bool    `json:"isWeightBased"`
	WeightUnit        *string `json:"weightUnit"`

	ModifierGroupIDs []string         `json:"modifierGroupIds"`
	PriceOverrides   []map[string]any `json:"priceOverrides"`
	Variants         []map[string]any `json:"variants"`
	Allergens        []string         `json:"allergens"`
}

type snapModGroup struct {
	ID            string    `json:"id"`
	Name          string    `json:"name"`
	SelectionType string    `json:"selectionType"`
	MinSelections int       `json:"minSelections"`
	MaxSelections int       `json:"maxSelections"`
	IsRequired    bool      `json:"isRequired"`
	AskQuantity   bool      `json:"askQuantity"`
	FreeTagging   bool      `json:"freeTagging"`
	ColumnCount   int       `json:"columnCount"`
	Prefix        string    `json:"prefix"`
	DisplayOrder  int       `json:"displayOrder"`
	Modifiers     []snapMod `json:"modifiers"`
}

type snapMod struct {
	ID               string `json:"id"`
	Name             string `json:"name"`
	PriceDeltaCents  int64  `json:"priceDeltaCents"`
	IsDefault        bool   `json:"isDefault"`
	DisplayOrder     int    `json:"displayOrder"`
}

type snapReceiptTmpl struct {
	HeaderLines       []string `json:"headerLines"`
	FooterLines       []string `json:"footerLines"`
	ShowLogo          bool     `json:"showLogo"`
	ShowMwstBreakdown bool     `json:"showMwstBreakdown"`
	FontSize          string   `json:"fontSize"`
}

// ---------------------------------------------------------------------------
// Routes (registered from module.go)
// ---------------------------------------------------------------------------

// registerSyncRoutes wires the menu sync endpoints onto the given mux.
// Called from Module.RegisterRoutes after the regular CRUD routes.
func (m *Module) registerSyncRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/menu/version/{tenantId}", m.handleGetVersion)
	mux.HandleFunc("GET /api/v1/menu/snapshot/{tenantId}", m.handleGetSnapshot)
	mux.HandleFunc("POST /api/v1/menu/publish/{tenantId}", m.handlePublish)
	mux.HandleFunc("POST /api/v1/admin/tenants/{tenantId}/api-key", m.handleRotateAPIKey)
}

// ---------------------------------------------------------------------------
// Auth helpers — resolve tenantId from JWT or X-API-Key.
// ---------------------------------------------------------------------------

// authorizeTenantRead allows either a JWT bound to the same tenantId, or an
// X-API-Key header that matches the tenant's stored hash. Returns ("", false)
// on failure; caller must respond.
func (m *Module) authorizeTenantRead(r *http.Request, pathTenantID string) (string, bool) {
	// Path tenant must be present.
	if pathTenantID == "" {
		return "", false
	}

	// Path 1 — JWT in context. Must match path tenant.
	if t := middleware.GetTenantID(r.Context()); t != "" {
		if t == pathTenantID {
			return pathTenantID, true
		}
		return "", false
	}

	// Path 2 — X-API-Key. Two flavours:
	//   (a) Device-scoped key (`gc_dev_…`) → look up `pos_devices`.
	//   (b) Legacy per-tenant key → compare against `tenants.pos_api_key`.
	// Device keys are checked first because they're the going-forward path
	// and rotating the legacy tenant key out is on the cleanup roadmap.
	key := strings.TrimSpace(r.Header.Get("X-API-Key"))
	if key == "" {
		return "", false
	}
	if devTenant := m.validateDeviceAPIKey(r, key); devTenant != "" {
		if devTenant != pathTenantID {
			return "", false
		}
		return pathTenantID, true
	}
	var stored sql.NullString
	err := m.db.QueryRowContext(r.Context(),
		`SELECT pos_api_key FROM tenants WHERE id = $1`, pathTenantID).Scan(&stored)
	if err != nil || !stored.Valid || stored.String == "" {
		return "", false
	}
	if !crypto.VerifyPassword(key, stored.String) {
		return "", false
	}
	return pathTenantID, true
}

// authorizeTenantWrite requires a JWT bound to the same tenant AND a role
// authorised to publish (admin or brand_manager). API keys cannot publish.
func (m *Module) authorizeTenantWrite(r *http.Request, pathTenantID string) (string, bool) {
	t := middleware.GetTenantID(r.Context())
	if t == "" || t != pathTenantID {
		return "", false
	}
	role := middleware.GetRole(r.Context())
	if role != "admin" && role != "brand_manager" {
		return "", false
	}
	return pathTenantID, true
}

// ---------------------------------------------------------------------------
// GET /api/v1/menu/version/{tenantId}
// ---------------------------------------------------------------------------

func (m *Module) handleGetVersion(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenantId")
	if _, ok := m.authorizeTenantRead(r, tenantID); !ok {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "JWT or X-API-Key required")
		return
	}

	var version int
	var publishedAt sql.NullTime
	err := m.db.QueryRowContext(r.Context(), `
		SELECT t.menu_version_current, mv.published_at
		FROM tenants t
		LEFT JOIN menu_versions mv
		    ON mv.tenant_id = t.id AND mv.version = t.menu_version_current
		WHERE t.id = $1
	`, tenantID).Scan(&version, &publishedAt)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Tenant not found")
		return
	}
	if err != nil {
		slog.Error("menu sync: get version", "error", err, "tenant", tenantID)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch version")
		return
	}
	if version == 0 {
		response.JSON(w, http.StatusNotFound, map[string]any{
			"success": false,
			"error":   "no_published_version",
		})
		return
	}

	out := map[string]any{
		"tenantId":      tenantID,
		"menuVersion":   version,
		"schemaVersion": schemaVersion,
	}
	if publishedAt.Valid {
		out["publishedAt"] = publishedAt.Time.UTC().Format(time.RFC3339)
	}
	response.JSON(w, http.StatusOK, map[string]any{
		"success": true,
		"data":    out,
	})
}

// ---------------------------------------------------------------------------
// GET /api/v1/menu/snapshot/{tenantId}?since=N
// ---------------------------------------------------------------------------

func (m *Module) handleGetSnapshot(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenantId")
	if _, ok := m.authorizeTenantRead(r, tenantID); !ok {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "JWT or X-API-Key required")
		return
	}

	var current int
	if err := m.db.QueryRowContext(r.Context(),
		`SELECT menu_version_current FROM tenants WHERE id = $1`, tenantID).Scan(&current); err != nil {
		if err == sql.ErrNoRows {
			response.Error(w, http.StatusNotFound, "NOT_FOUND", "Tenant not found")
			return
		}
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch tenant")
		return
	}
	if current == 0 {
		response.JSON(w, http.StatusNotFound, map[string]any{
			"success": false,
			"error":   "no_published_version",
		})
		return
	}

	if since := r.URL.Query().Get("since"); since != "" {
		if n, err := strconv.Atoi(since); err == nil && n >= current {
			w.WriteHeader(http.StatusNotModified)
			return
		}
	}

	var raw []byte
	if err := m.db.QueryRowContext(r.Context(),
		`SELECT snapshot FROM menu_versions
		 WHERE tenant_id = $1 AND version = $2`,
		tenantID, current).Scan(&raw); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch snapshot")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "private, no-cache")
	// The stored row already contains the full {success,data} envelope?
	// No — we store only the snapshot body. Wrap it.
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"success":true,"data":`))
	_, _ = w.Write(raw)
	_, _ = w.Write([]byte(`}`))
}

// ---------------------------------------------------------------------------
// POST /api/v1/menu/publish/{tenantId}
// ---------------------------------------------------------------------------

func (m *Module) handlePublish(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenantId")
	if _, ok := m.authorizeTenantWrite(r, tenantID); !ok {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Admin role and matching tenant required")
		return
	}

	// Build the snapshot in a serializable transaction so we don't observe
	// half-written CRUD work from another admin.
	ctx := r.Context()
	tx, err := m.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to begin transaction")
		return
	}
	defer tx.Rollback()

	snap, summary, err := buildSnapshot(ctx, tx, tenantID)
	if err != nil {
		slog.Error("menu sync: build snapshot", "error", err, "tenant", tenantID)
		response.Error(w, http.StatusInternalServerError, "BUILD_ERROR", "Failed to build snapshot")
		return
	}

	// Bump version inside the same tx.
	var nextVersion int
	if err := tx.QueryRowContext(ctx,
		`UPDATE tenants SET menu_version_current = menu_version_current + 1
		 WHERE id = $1
		 RETURNING menu_version_current`, tenantID).Scan(&nextVersion); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to bump version")
		return
	}
	publishedAt := time.Now().UTC()
	snap.MenuVersion = nextVersion
	snap.PublishedAt = publishedAt

	jsonBytes, err := json.Marshal(snap)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "ENCODE_ERROR", "Failed to encode snapshot")
		return
	}

	publishedBy := middleware.GetUserID(ctx)
	var publishedByVal any
	if publishedBy != "" {
		publishedByVal = publishedBy
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO menu_versions (tenant_id, version, snapshot, published_at, published_by)
		VALUES ($1, $2, $3::jsonb, $4, $5)
	`, tenantID, nextVersion, string(jsonBytes), publishedAt, publishedByVal); err != nil {
		// Most likely cause: another publish raced and committed first.
		// Serializable isolation will surface this as a serialization failure.
		response.Error(w, http.StatusConflict, "CONCURRENT_PUBLISH", "Concurrent publish detected; retry")
		return
	}

	if err := tx.Commit(); err != nil {
		response.Error(w, http.StatusConflict, "COMMIT_FAILED", "Could not commit publish; retry")
		return
	}

	// Best-effort fan-out via the existing sync hub. POS clients that have
	// a WebSocket open for this tenant get a "menu_published" notification
	// and can pull the snapshot immediately.
	if m.hub != nil {
		evt, _ := json.Marshal(map[string]any{
			"type":        "menu_published",
			"tenant_id":   tenantID,
			"version":     nextVersion,
			"published_at": publishedAt.Format(time.RFC3339),
		})
		m.hub.BroadcastTenant(tenantID, evt)
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"success": true,
		"data": map[string]any{
			"menuVersion": nextVersion,
			"publishedAt": publishedAt.Format(time.RFC3339),
			"summary":     summary,
		},
	})
}

// ---------------------------------------------------------------------------
// POST /api/v1/admin/tenants/{tenantId}/api-key
// ---------------------------------------------------------------------------

func (m *Module) handleRotateAPIKey(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenantId")
	if _, ok := m.authorizeTenantWrite(r, tenantID); !ok {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Admin role and matching tenant required")
		return
	}

	// Generate 32 random bytes -> URL-safe base64 (no padding) -> ~43 chars.
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		response.Error(w, http.StatusInternalServerError, "RAND_ERROR", "Failed to generate key")
		return
	}
	plain := strings.TrimRight(base64.URLEncoding.EncodeToString(buf), "=")

	hash, err := crypto.HashPassword(plain)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "HASH_ERROR", "Failed to hash key")
		return
	}

	if _, err := m.db.ExecContext(r.Context(),
		`UPDATE tenants SET pos_api_key = $1 WHERE id = $2`, hash, tenantID); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to store key")
		return
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"success": true,
		"data": map[string]any{
			// IMPORTANT: plain key is shown ONCE here. The server keeps only
			// the hash; if the user loses the key they must rotate again.
			"apiKey":   plain,
			"tenantId": tenantID,
			"warning":  "This key is shown only once. Store it now; you cannot retrieve it later.",
		},
	})
}

// ---------------------------------------------------------------------------
// buildSnapshot — read live tables for a tenant and produce a snapshot.
// Money values are converted from BIGINT cents (already cents) directly.
// ---------------------------------------------------------------------------

func buildSnapshot(ctx context.Context, tx *sql.Tx, tenantID string) (*snapshot, map[string]int, error) {
	out := &snapshot{
		SchemaVersion:   schemaVersion,
		TenantID:        tenantID,
		Currency:        "CHF",
		Locale:          "de-CH",
		HappyHourRules:  []any{},
		Gangs:           []any{},
		TaxProfiles:     []snapTax{},
		Categories:      []snapCategory{},
		Products:        []snapProduct{},
		ModifierGroups:  []snapModGroup{},
		ReceiptTemplate: snapReceiptTmpl{HeaderLines: []string{}, FooterLines: []string{}, FontSize: "normal", ShowLogo: true, ShowMwstBreakdown: true},
	}

	// Business profile from tenants row.
	var name, address, phone, taxID sql.NullString
	var currency sql.NullString
	if err := tx.QueryRowContext(ctx, `
		SELECT name, COALESCE(address,''), COALESCE(phone,''),
		       COALESCE(tax_id,''), COALESCE(currency_code,'CHF')
		FROM tenants WHERE id = $1
	`, tenantID).Scan(&name, &address, &phone, &taxID, &currency); err != nil {
		return nil, nil, err
	}
	out.Currency = currency.String
	out.Business = snapBusiness{
		Name:    name.String,
		Address: address.String,
		Phone:   phone.String,
		Email:   "",
		MwstNr:  taxID.String,
	}

	// Tax profiles.
	taxRows, err := tx.QueryContext(ctx, `
		SELECT id, country_code, order_type, product_tax_group, tax_rate, tax_name, is_default
		FROM tax_profiles WHERE tenant_id = $1
		ORDER BY is_default DESC, order_type ASC
	`, tenantID)
	if err == nil {
		defer taxRows.Close()
		for taxRows.Next() {
			var t snapTax
			if err := taxRows.Scan(&t.ID, &t.CountryCode, &t.OrderType, &t.ProductTaxGroup,
				&t.TaxRate, &t.TaxName, &t.IsDefault); err == nil {
				out.TaxProfiles = append(out.TaxProfiles, t)
			}
		}
	} else if !errors.Is(err, sql.ErrNoRows) {
		// Tax table optional — log but don't fail.
		slog.Warn("menu sync: tax profiles", "error", err, "tenant", tenantID)
	}

	// Categories.
	catRows, err := tx.QueryContext(ctx, `
		SELECT id::text, name, display_order, color, icon, parent_id::text, is_active,
		       COALESCE(name_translations, '{}'::jsonb)
		FROM categories
		WHERE tenant_id = $1 AND is_deleted = false
		ORDER BY display_order ASC, name ASC
	`, tenantID)
	if err != nil {
		return nil, nil, err
	}
	defer catRows.Close()
	for catRows.Next() {
		var c snapCategory
		var color, icon sql.NullString
		var parentID sql.NullString
		var nameTr []byte
		if err := catRows.Scan(&c.ID, &c.Name, &c.DisplayOrder, &color, &icon, &parentID, &c.IsActive, &nameTr); err != nil {
			continue
		}
		c.NameTranslations = ScanTranslations(nameTr)
		if color.Valid && color.String != "" {
			s := color.String
			c.Color = &s
		}
		if icon.Valid && icon.String != "" {
			s := icon.String
			c.Icon = &s
		}
		if parentID.Valid && parentID.String != "" {
			s := parentID.String
			c.ParentID = &s
		}
		out.Categories = append(out.Categories, c)
	}

	// Products + their modifier-group ids.
	prodRows, err := tx.QueryContext(ctx, `
		SELECT id::text, category_id::text, name, COALESCE(description,''),
		       price, cost_price, tax_group, image_path, barcode,
		       is_active, display_order, prep_time_minutes, printer_group,
		       COALESCE(name_translations, '{}'::jsonb),
		       COALESCE(description_translations, '{}'::jsonb)
		FROM products
		WHERE tenant_id = $1 AND is_deleted = false
		ORDER BY display_order ASC, name ASC
	`, tenantID)
	if err != nil {
		return nil, nil, err
	}
	defer prodRows.Close()

	productIDs := []string{}
	productMap := map[string]*snapProduct{}
	for prodRows.Next() {
		var p snapProduct
		var img, barcode sql.NullString
		var prep sql.NullInt64
		var nameTr, descTr []byte
		if err := prodRows.Scan(&p.ID, &p.CategoryID, &p.Name, &p.Description,
			&p.PriceCents, &p.CostPriceCents, &p.TaxGroup, &img, &barcode,
			&p.IsActive, &p.DisplayOrder, &prep, &p.PrinterGroup,
			&nameTr, &descTr); err != nil {
			continue
		}
		p.NameTranslations = ScanTranslations(nameTr)
		p.DescriptionTranslations = ScanTranslations(descTr)
		if img.Valid && img.String != "" {
			s := img.String
			p.ImageURL = &s
		}
		if barcode.Valid && barcode.String != "" {
			s := barcode.String
			p.Barcode = &s
		}
		if prep.Valid {
			n := int(prep.Int64)
			p.PrepTimeMinutes = &n
		}
		// Defaults for fields the products table doesn't carry yet.
		p.IsAvailable = true
		p.StockStatus = "in_stock"
		p.ModifierGroupIDs = []string{}
		p.PriceOverrides = []map[string]any{}
		p.Variants = []map[string]any{}
		p.Allergens = []string{}
		out.Products = append(out.Products, p)
		productIDs = append(productIDs, p.ID)
		productMap[p.ID] = &out.Products[len(out.Products)-1]
	}

	// Product → modifier group links.
	if len(productIDs) > 0 {
		linkRows, err := tx.QueryContext(ctx, `
			SELECT product_id::text, modifier_group_id::text, display_order
			FROM product_modifier_groups
			WHERE product_id = ANY($1::uuid[])
			ORDER BY product_id, display_order ASC
		`, "{"+strings.Join(productIDs, ",")+"}")
		if err == nil {
			defer linkRows.Close()
			for linkRows.Next() {
				var pid, mgid string
				var ord int
				if err := linkRows.Scan(&pid, &mgid, &ord); err == nil {
					if p, ok := productMap[pid]; ok {
						p.ModifierGroupIDs = append(p.ModifierGroupIDs, mgid)
					}
				}
			}
		}
	}

	// Modifier groups + nested modifiers.
	mgRows, err := tx.QueryContext(ctx, `
		SELECT id::text, name, selection_type, min_selections, max_selections, is_required, display_order
		FROM modifier_groups
		WHERE tenant_id = $1 AND is_deleted = false
		ORDER BY display_order ASC, name ASC
	`, tenantID)
	if err != nil {
		return nil, nil, err
	}
	defer mgRows.Close()
	mgMap := map[string]*snapModGroup{}
	for mgRows.Next() {
		var mg snapModGroup
		if err := mgRows.Scan(&mg.ID, &mg.Name, &mg.SelectionType, &mg.MinSelections, &mg.MaxSelections, &mg.IsRequired, &mg.DisplayOrder); err != nil {
			continue
		}
		mg.Modifiers = []snapMod{}
		mg.ColumnCount = 3
		out.ModifierGroups = append(out.ModifierGroups, mg)
		mgMap[mg.ID] = &out.ModifierGroups[len(out.ModifierGroups)-1]
	}

	modRows, err := tx.QueryContext(ctx, `
		SELECT id::text, group_id::text, name, price_delta, is_default, display_order
		FROM modifiers
		WHERE tenant_id = $1 AND is_deleted = false
		ORDER BY group_id, display_order ASC
	`, tenantID)
	if err == nil {
		defer modRows.Close()
		modCount := 0
		for modRows.Next() {
			var md snapMod
			var gid string
			if err := modRows.Scan(&md.ID, &gid, &md.Name, &md.PriceDeltaCents, &md.IsDefault, &md.DisplayOrder); err != nil {
				continue
			}
			if mg, ok := mgMap[gid]; ok {
				mg.Modifiers = append(mg.Modifiers, md)
				modCount++
			}
		}
		_ = modCount
	}

	summary := map[string]int{
		"categories":     len(out.Categories),
		"products":       len(out.Products),
		"modifierGroups": len(out.ModifierGroups),
		"taxProfiles":    len(out.TaxProfiles),
	}
	return out, summary, nil
}
