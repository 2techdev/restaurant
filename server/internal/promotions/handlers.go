package promotions

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
	"github.com/lib/pq"
)

type Discount struct {
	ID                      string          `json:"id"`
	TenantID                string          `json:"tenant_id"`
	Name                    string          `json:"name"`
	NameTranslations        json.RawMessage `json:"name_translations,omitempty"`
	Description             *string         `json:"description,omitempty"`
	DescriptionTranslations json.RawMessage `json:"description_translations,omitempty"`
	Type                    string          `json:"type"` // PERCENT | FIXED | BOGO | HAPPY_HOUR
	Value                   float64         `json:"value"`
	Active                  bool            `json:"active"`
	StartsAt                *time.Time      `json:"starts_at,omitempty"`
	EndsAt                  *time.Time      `json:"ends_at,omitempty"`
	AppliesToCategories     []string        `json:"applies_to_categories,omitempty"`
	AppliesToProducts       []string        `json:"applies_to_products,omitempty"`
	MinOrderCents           *int64          `json:"min_order_cents,omitempty"`
	Notes                   *string         `json:"notes,omitempty"`

	// Migration 030 enrichments — days/hours window, usage caps, promo code,
	// stackability. Surface as JSON only when set so the public response
	// stays compact for the legacy PERCENT/FIXED/BOGO callers.
	DaysOfWeek  []int64 `json:"days_of_week,omitempty"`
	HoursFrom   *string `json:"hours_from,omitempty"` // "HH:MM" or "HH:MM:SS"
	HoursTo     *string `json:"hours_to,omitempty"`
	MaxUses     *int64  `json:"max_uses,omitempty"`
	UsedCount   int64   `json:"used_count"`
	PromoCode   *string `json:"promo_code,omitempty"`
	IsStackable bool    `json:"is_stackable"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Campaign struct {
	ID          string     `json:"id"`
	TenantID    string     `json:"tenant_id"`
	Name        string     `json:"name"`
	Description *string    `json:"description,omitempty"`
	StartsAt    *time.Time `json:"starts_at,omitempty"`
	EndsAt      *time.Time `json:"ends_at,omitempty"`
	Active      bool       `json:"active"`
	Channels    []string   `json:"channels,omitempty"`
	DiscountID  *string    `json:"discount_id,omitempty"`
	Audience    *string    `json:"audience,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

func resolveTenant(r *http.Request) string {
	if t := middleware.GetTenantID(r.Context()); t != "" {
		return t
	}
	return r.URL.Query().Get("tenant_id")
}

// ---------------------------------------------------------------------------
// Discounts
// ---------------------------------------------------------------------------

func (m *Module) handleListDiscounts(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, name, name_translations, description, description_translations,
		       type, value, active, starts_at, ends_at,
		       applies_to_categories, applies_to_products, min_order_cents, notes,
		       days_of_week, hours_from::text, hours_to::text, max_uses, used_count,
		       promo_code, is_stackable, created_at, updated_at
		FROM discounts
		WHERE tenant_id = $1 AND is_deleted = false
		ORDER BY active DESC, name ASC
	`, tenantID)
	if err != nil {
		slog.Error("promotions: list discounts", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list discounts")
		return
	}
	defer rows.Close()
	out := make([]Discount, 0)
	for rows.Next() {
		d, err := scanDiscount(rows)
		if err != nil {
			continue
		}
		out = append(out, d)
	}
	response.Paginated(w, out, "", false)
}

type discountReq struct {
	Name                    string          `json:"name"`
	NameTranslations        json.RawMessage `json:"name_translations"`
	Description             *string         `json:"description"`
	DescriptionTranslations json.RawMessage `json:"description_translations"`
	Type                    string          `json:"type"`
	Value                   float64         `json:"value"`
	Active                  *bool           `json:"active"`
	StartsAt                *time.Time      `json:"starts_at"`
	EndsAt                  *time.Time      `json:"ends_at"`
	AppliesToCategories     []string        `json:"applies_to_categories"`
	AppliesToProducts       []string        `json:"applies_to_products"`
	MinOrderCents           *int64          `json:"min_order_cents"`
	Notes                   *string         `json:"notes"`

	// 030 fields
	DaysOfWeek  []int64 `json:"days_of_week"`
	HoursFrom   *string `json:"hours_from"`
	HoursTo     *string `json:"hours_to"`
	MaxUses     *int64  `json:"max_uses"`
	PromoCode   *string `json:"promo_code"`
	IsStackable *bool   `json:"is_stackable"`
}

func (m *Module) handleCreateDiscount(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	var req discountReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	if req.Name == "" || !isValidType(req.Type) {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR",
			"name and type required (type ∈ PERCENT|FIXED|BOGO|HAPPY_HOUR)")
		return
	}
	id := uuid.New()
	now := time.Now().UTC()
	active := true
	if req.Active != nil {
		active = *req.Active
	}
	isStackable := false
	if req.IsStackable != nil {
		isStackable = *req.IsStackable
	}
	// Default to "every day" so the operator can leave the days picker empty.
	dow := req.DaysOfWeek
	if len(dow) == 0 {
		dow = []int64{0, 1, 2, 3, 4, 5, 6}
	}
	nameTr := jsonOrEmpty(req.NameTranslations)
	descTr := jsonOrEmpty(req.DescriptionTranslations)

	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO discounts (
			id, tenant_id, name, name_translations,
			description, description_translations,
			type, value, active, starts_at, ends_at,
			applies_to_categories, applies_to_products, min_order_cents, notes,
			days_of_week, hours_from, hours_to, max_uses, used_count,
			promo_code, is_stackable, created_at, updated_at, is_deleted
		) VALUES (
			$1,$2,$3,$4::jsonb,
			$5,$6::jsonb,
			$7,$8,$9,$10,$11,
			$12,$13,$14,$15,
			$16,$17::time,$18::time,$19,0,
			$20,$21,$22,$22,false
		)
	`,
		id, tenantID, req.Name, nameTr,
		nullableString(req.Description), descTr,
		req.Type, req.Value, active, req.StartsAt, req.EndsAt,
		pq.Array(req.AppliesToCategories), pq.Array(req.AppliesToProducts),
		req.MinOrderCents, nullableString(req.Notes),
		pq.Array(dow), nullableString(req.HoursFrom), nullableString(req.HoursTo),
		req.MaxUses, nullableString(req.PromoCode), isStackable, now)
	if err != nil {
		slog.Error("promotions: create discount", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create discount")
		return
	}
	response.Created(w, Discount{
		ID: id, TenantID: tenantID, Name: req.Name,
		NameTranslations:        nameTr,
		Description:             req.Description,
		DescriptionTranslations: descTr,
		Type:                    req.Type,
		Value:                   req.Value,
		Active:                  active,
		StartsAt:                req.StartsAt,
		EndsAt:                  req.EndsAt,
		AppliesToCategories:     req.AppliesToCategories,
		AppliesToProducts:       req.AppliesToProducts,
		MinOrderCents:           req.MinOrderCents,
		Notes:                   req.Notes,
		DaysOfWeek:              dow,
		HoursFrom:               req.HoursFrom,
		HoursTo:                 req.HoursTo,
		MaxUses:                 req.MaxUses,
		PromoCode:               req.PromoCode,
		IsStackable:             isStackable,
		CreatedAt:               now,
		UpdatedAt:               now,
	})
}

func (m *Module) handleGetDiscount(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	row := m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, name, name_translations, description, description_translations,
		       type, value, active, starts_at, ends_at,
		       applies_to_categories, applies_to_products, min_order_cents, notes,
		       days_of_week, hours_from::text, hours_to::text, max_uses, used_count,
		       promo_code, is_stackable, created_at, updated_at
		FROM discounts
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID)
	d, err := scanDiscount(row)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Discount not found")
		return
	}
	if err != nil {
		slog.Error("promotions: get discount", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load discount")
		return
	}
	response.JSON(w, http.StatusOK, d)
}

func (m *Module) handleUpdateDiscount(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	var req discountReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	if req.Type != "" && !isValidType(req.Type) {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "type must be PERCENT|FIXED|BOGO|HAPPY_HOUR")
		return
	}
	dow := req.DaysOfWeek
	if dow == nil {
		dow = []int64{} // sentinel: COALESCE keeps existing value
	}
	nameTr := jsonOrEmpty(req.NameTranslations)
	descTr := jsonOrEmpty(req.DescriptionTranslations)

	res, err := m.db.ExecContext(r.Context(), `
		UPDATE discounts SET
			name = CASE WHEN $3 = '' THEN name ELSE $3 END,
			name_translations = COALESCE(NULLIF($4::jsonb, 'null'::jsonb), name_translations),
			description = COALESCE($5, description),
			description_translations = COALESCE(NULLIF($6::jsonb, 'null'::jsonb), description_translations),
			type = CASE WHEN $7 = '' THEN type ELSE $7 END,
			value = $8,
			active = COALESCE($9, active),
			starts_at = $10,
			ends_at = $11,
			applies_to_categories = $12,
			applies_to_products = $13,
			min_order_cents = $14,
			notes = $15,
			days_of_week = CASE WHEN array_length($16::int[], 1) IS NULL THEN days_of_week ELSE $16 END,
			hours_from = $17::time,
			hours_to = $18::time,
			max_uses = $19,
			promo_code = $20,
			is_stackable = COALESCE($21, is_stackable),
			updated_at = NOW()
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID, req.Name, nameTr, nullableString(req.Description), descTr,
		req.Type, req.Value, req.Active, req.StartsAt, req.EndsAt,
		pq.Array(req.AppliesToCategories), pq.Array(req.AppliesToProducts),
		req.MinOrderCents, nullableString(req.Notes),
		pq.Array(dow), nullableString(req.HoursFrom), nullableString(req.HoursTo),
		req.MaxUses, nullableString(req.PromoCode), req.IsStackable)
	if err != nil {
		slog.Error("promotions: update discount", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update discount")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Discount not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"id": id, "status": "updated"})
}

func (m *Module) handleDeleteDiscount(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE discounts SET is_deleted = true, updated_at = NOW()
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID)
	if err != nil {
		slog.Error("promotions: delete discount", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete discount")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Discount not found")
		return
	}
	response.NoContent(w)
}

// ---------------------------------------------------------------------------
// Campaigns
// ---------------------------------------------------------------------------

func (m *Module) handleListCampaigns(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, name, description, starts_at, ends_at, active, channels,
		       discount_id, audience, created_at, updated_at
		FROM campaigns
		WHERE tenant_id = $1 AND is_deleted = false
		ORDER BY active DESC, name ASC
	`, tenantID)
	if err != nil {
		slog.Error("promotions: list campaigns", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list campaigns")
		return
	}
	defer rows.Close()
	out := make([]Campaign, 0)
	for rows.Next() {
		c, err := scanCampaign(rows)
		if err != nil {
			continue
		}
		out = append(out, c)
	}
	response.Paginated(w, out, "", false)
}

type campaignReq struct {
	Name        string     `json:"name"`
	Description *string    `json:"description"`
	StartsAt    *time.Time `json:"starts_at"`
	EndsAt      *time.Time `json:"ends_at"`
	Active      *bool      `json:"active"`
	Channels    []string   `json:"channels"`
	DiscountID  *string    `json:"discount_id"`
	Audience    *string    `json:"audience"`
}

func (m *Module) handleCreateCampaign(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	var req campaignReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	if req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "name required")
		return
	}
	id := uuid.New()
	now := time.Now().UTC()
	active := true
	if req.Active != nil {
		active = *req.Active
	}
	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO campaigns (id, tenant_id, name, description, starts_at, ends_at, active, channels,
		                      discount_id, audience, created_at, updated_at, is_deleted)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$11,false)
	`, id, tenantID, req.Name, nullableString(req.Description), req.StartsAt, req.EndsAt, active,
		pq.Array(req.Channels), nullableString(req.DiscountID), nullableString(req.Audience), now)
	if err != nil {
		slog.Error("promotions: create campaign", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create campaign")
		return
	}
	response.Created(w, Campaign{
		ID: id, TenantID: tenantID, Name: req.Name, Description: req.Description,
		StartsAt: req.StartsAt, EndsAt: req.EndsAt, Active: active, Channels: req.Channels,
		DiscountID: req.DiscountID, Audience: req.Audience, CreatedAt: now, UpdatedAt: now,
	})
}

func (m *Module) handleGetCampaign(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	row := m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, name, description, starts_at, ends_at, active, channels,
		       discount_id, audience, created_at, updated_at
		FROM campaigns
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID)
	c, err := scanCampaign(row)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Campaign not found")
		return
	}
	if err != nil {
		slog.Error("promotions: get campaign", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load campaign")
		return
	}
	response.JSON(w, http.StatusOK, c)
}

func (m *Module) handleUpdateCampaign(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	var req campaignReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE campaigns SET
			name = CASE WHEN $3 = '' THEN name ELSE $3 END,
			description = $4,
			starts_at = $5,
			ends_at = $6,
			active = COALESCE($7, active),
			channels = $8,
			discount_id = $9,
			audience = $10,
			updated_at = NOW()
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID, req.Name, nullableString(req.Description), req.StartsAt, req.EndsAt, req.Active,
		pq.Array(req.Channels), nullableString(req.DiscountID), nullableString(req.Audience))
	if err != nil {
		slog.Error("promotions: update campaign", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update campaign")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Campaign not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"id": id, "status": "updated"})
}

func (m *Module) handleDeleteCampaign(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE campaigns SET is_deleted = true, updated_at = NOW()
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID)
	if err != nil {
		slog.Error("promotions: delete campaign", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete campaign")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Campaign not found")
		return
	}
	response.NoContent(w)
}

// ---------------------------------------------------------------------------
// Active promotions (POS terminal pulls these on shift open / refresh)
// ---------------------------------------------------------------------------

// handleActive returns all currently-active discounts and campaigns whose
// time window includes NOW(). Designed for POS terminals to decide which
// reductions to offer at checkout without computing the window themselves.
// GET /api/v1/promotions/active
func (m *Module) handleActive(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	now := time.Now().UTC()

	dRows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, name, name_translations, description, description_translations,
		       type, value, active, starts_at, ends_at,
		       applies_to_categories, applies_to_products, min_order_cents, notes,
		       days_of_week, hours_from::text, hours_to::text, max_uses, used_count,
		       promo_code, is_stackable, created_at, updated_at
		FROM discounts
		WHERE tenant_id = $1 AND is_deleted = false AND active = true
		  AND (starts_at IS NULL OR starts_at <= $2)
		  AND (ends_at   IS NULL OR ends_at   >= $2)
		ORDER BY name
	`, tenantID, now)
	if err != nil {
		slog.Error("promotions: active discounts", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load active discounts")
		return
	}
	discounts := make([]Discount, 0)
	for dRows.Next() {
		if d, err := scanDiscount(dRows); err == nil {
			discounts = append(discounts, d)
		}
	}
	dRows.Close()

	cRows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, name, description, starts_at, ends_at, active, channels,
		       discount_id, audience, created_at, updated_at
		FROM campaigns
		WHERE tenant_id = $1 AND is_deleted = false AND active = true
		  AND (starts_at IS NULL OR starts_at <= $2)
		  AND (ends_at   IS NULL OR ends_at   >= $2)
		ORDER BY name
	`, tenantID, now)
	if err != nil {
		slog.Error("promotions: active campaigns", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load active campaigns")
		return
	}
	defer cRows.Close()
	campaigns := make([]Campaign, 0)
	for cRows.Next() {
		if c, err := scanCampaign(cRows); err == nil {
			campaigns = append(campaigns, c)
		}
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"now":       now,
		"discounts": discounts,
		"campaigns": campaigns,
	})
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

type rowScanner interface {
	Scan(dest ...any) error
}

func scanDiscount(s rowScanner) (Discount, error) {
	var d Discount
	var startsAt, endsAt sql.NullTime
	var description, notes, hoursFrom, hoursTo, promoCode sql.NullString
	var minOrder, maxUses sql.NullInt64
	var cats, prods pq.StringArray
	var dow pq.Int64Array
	var nameTr, descTr []byte
	if err := s.Scan(
		&d.ID, &d.TenantID, &d.Name, &nameTr, &description, &descTr,
		&d.Type, &d.Value, &d.Active, &startsAt, &endsAt,
		&cats, &prods, &minOrder, &notes,
		&dow, &hoursFrom, &hoursTo, &maxUses, &d.UsedCount,
		&promoCode, &d.IsStackable, &d.CreatedAt, &d.UpdatedAt,
	); err != nil {
		return d, err
	}
	if len(nameTr) > 0 {
		d.NameTranslations = json.RawMessage(nameTr)
	}
	if description.Valid {
		v := description.String
		d.Description = &v
	}
	if len(descTr) > 0 {
		d.DescriptionTranslations = json.RawMessage(descTr)
	}
	if startsAt.Valid {
		t := startsAt.Time
		d.StartsAt = &t
	}
	if endsAt.Valid {
		t := endsAt.Time
		d.EndsAt = &t
	}
	if notes.Valid {
		v := notes.String
		d.Notes = &v
	}
	if minOrder.Valid {
		v := minOrder.Int64
		d.MinOrderCents = &v
	}
	if hoursFrom.Valid {
		v := hoursFrom.String
		d.HoursFrom = &v
	}
	if hoursTo.Valid {
		v := hoursTo.String
		d.HoursTo = &v
	}
	if maxUses.Valid {
		v := maxUses.Int64
		d.MaxUses = &v
	}
	if promoCode.Valid {
		v := promoCode.String
		d.PromoCode = &v
	}
	d.DaysOfWeek = []int64(dow)
	d.AppliesToCategories = []string(cats)
	d.AppliesToProducts = []string(prods)
	return d, nil
}

func scanCampaign(s rowScanner) (Campaign, error) {
	var c Campaign
	var startsAt, endsAt sql.NullTime
	var description, discountID, audience sql.NullString
	var channels pq.StringArray
	if err := s.Scan(&c.ID, &c.TenantID, &c.Name, &description, &startsAt, &endsAt,
		&c.Active, &channels, &discountID, &audience, &c.CreatedAt, &c.UpdatedAt); err != nil {
		return c, err
	}
	if startsAt.Valid {
		t := startsAt.Time
		c.StartsAt = &t
	}
	if endsAt.Valid {
		t := endsAt.Time
		c.EndsAt = &t
	}
	if description.Valid {
		v := description.String
		c.Description = &v
	}
	if discountID.Valid {
		v := discountID.String
		c.DiscountID = &v
	}
	if audience.Valid {
		v := audience.String
		c.Audience = &v
	}
	c.Channels = []string(channels)
	return c, nil
}

func isValidType(t string) bool {
	return t == "PERCENT" || t == "FIXED" || t == "BOGO" || t == "HAPPY_HOUR"
}

func nullableString(s *string) any {
	if s == nil || *s == "" {
		return nil
	}
	return *s
}

// jsonOrEmpty normalises an incoming nullable JSON blob so the SQL layer
// always sees a valid JSON literal — either the operator-supplied object
// or `{}`. Used for name_translations / description_translations so
// callers can omit the field on PERCENT/FIXED rows without breaking the
// JSONB NOT NULL DEFAULT '{}' contract.
func jsonOrEmpty(raw json.RawMessage) []byte {
	if len(raw) == 0 {
		return []byte("{}")
	}
	return raw
}
