package orderprofiles

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
)

// store holds the SQL-level reads + writes for order_profiles and
// order_profile_pricing_rules.  Handlers stay narrow by calling these.

func scanProfile(rs interface{ Scan(...any) error }) (*Profile, error) {
	p := &Profile{
		NameTranslations: map[string]string{},
		PricingRules:     []PricingRule{},
	}
	var nameTr, settings []byte
	if err := rs.Scan(
		&p.ID, &p.TenantID, &p.Code, &p.Name, &nameTr, &p.Description,
		&p.IsActive, &p.IsDefault, &p.Priority, &settings,
		&p.CreatedAt, &p.UpdatedAt,
	); err != nil {
		return nil, err
	}
	if len(nameTr) > 0 {
		_ = json.Unmarshal(nameTr, &p.NameTranslations)
	}
	if len(settings) > 0 {
		_ = json.Unmarshal(settings, &p.Settings)
	}
	if p.Settings.Schedule == nil {
		p.Settings.Schedule = []ScheduleSlot{}
	}
	return p, nil
}

// listProfiles returns every profile for the tenant, newest-priority first.
// Pricing rules are loaded in a separate query and stitched in by ID so we
// don't pay the cartesian-explosion cost of a single LEFT JOIN.
func (m *Module) listProfiles(ctx context.Context, tenantID string) ([]*Profile, error) {
	rows, err := m.db.QueryContext(ctx, `
		SELECT id::text, tenant_id::text, code, name,
		       COALESCE(name_translations, '{}'::jsonb),
		       description, is_active, is_default, priority,
		       COALESCE(settings, '{}'::jsonb), created_at, updated_at
		FROM order_profiles
		WHERE tenant_id = $1
		ORDER BY priority DESC, name ASC
	`, tenantID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []*Profile{}
	ids := []string{}
	byID := map[string]*Profile{}
	for rows.Next() {
		p, err := scanProfile(rows)
		if err != nil {
			continue
		}
		out = append(out, p)
		ids = append(ids, p.ID)
		byID[p.ID] = p
	}
	if len(ids) == 0 {
		return out, nil
	}

	ruleRows, err := m.db.QueryContext(ctx, `
		SELECT id::text, profile_id::text, category_id::text, product_id::text,
		       override_price_cents, discount_percent
		FROM order_profile_pricing_rules
		WHERE profile_id = ANY($1::uuid[])
		ORDER BY created_at ASC
	`, pgUUIDArray(ids))
	if err != nil {
		return nil, err
	}
	defer ruleRows.Close()
	for ruleRows.Next() {
		var r PricingRule
		var profileID string
		var catID, prodID sql.NullString
		var override sql.NullInt64
		var discount sql.NullFloat64
		if err := ruleRows.Scan(&r.ID, &profileID, &catID, &prodID, &override, &discount); err != nil {
			continue
		}
		if catID.Valid && catID.String != "" {
			s := catID.String
			r.CategoryID = &s
		}
		if prodID.Valid && prodID.String != "" {
			s := prodID.String
			r.ProductID = &s
		}
		if override.Valid {
			v := override.Int64
			r.OverridePriceCents = &v
		}
		if discount.Valid {
			v := discount.Float64
			r.DiscountPercent = &v
		}
		if p, ok := byID[profileID]; ok {
			p.PricingRules = append(p.PricingRules, r)
		}
	}
	return out, nil
}

func (m *Module) getProfile(ctx context.Context, tenantID, profileID string) (*Profile, error) {
	row := m.db.QueryRowContext(ctx, `
		SELECT id::text, tenant_id::text, code, name,
		       COALESCE(name_translations, '{}'::jsonb),
		       description, is_active, is_default, priority,
		       COALESCE(settings, '{}'::jsonb), created_at, updated_at
		FROM order_profiles
		WHERE tenant_id = $1 AND id = $2
	`, tenantID, profileID)
	p, err := scanProfile(row)
	if err != nil {
		return nil, err
	}
	rules, err := m.loadRules(ctx, p.ID)
	if err == nil {
		p.PricingRules = rules
	}
	return p, nil
}

func (m *Module) loadRules(ctx context.Context, profileID string) ([]PricingRule, error) {
	rows, err := m.db.QueryContext(ctx, `
		SELECT id::text, category_id::text, product_id::text,
		       override_price_cents, discount_percent
		FROM order_profile_pricing_rules
		WHERE profile_id = $1
		ORDER BY created_at ASC
	`, profileID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []PricingRule{}
	for rows.Next() {
		var r PricingRule
		var catID, prodID sql.NullString
		var override sql.NullInt64
		var discount sql.NullFloat64
		if err := rows.Scan(&r.ID, &catID, &prodID, &override, &discount); err != nil {
			continue
		}
		if catID.Valid && catID.String != "" {
			s := catID.String
			r.CategoryID = &s
		}
		if prodID.Valid && prodID.String != "" {
			s := prodID.String
			r.ProductID = &s
		}
		if override.Valid {
			v := override.Int64
			r.OverridePriceCents = &v
		}
		if discount.Valid {
			v := discount.Float64
			r.DiscountPercent = &v
		}
		out = append(out, r)
	}
	return out, nil
}

// pgUUIDArray formats a Go []string of UUIDs into the literal that
// pq accepts for $1::uuid[].  We don't use pq.Array here so the dependency
// surface stays the same as the rest of the menu/snapshots code.
func pgUUIDArray(ids []string) string {
	if len(ids) == 0 {
		return "{}"
	}
	return "{" + joinComma(ids) + "}"
}

func joinComma(s []string) string {
	out := ""
	for i, v := range s {
		if i > 0 {
			out += ","
		}
		out += v
	}
	return out
}

var errProfileNotFound = errors.New("order profile not found")

// upsertProfile creates or updates a profile in a single transaction along
// with its pricing rules (full replace — caller hands in the desired final
// set).  Returns the post-write profile so the handler can echo back IDs.
func (m *Module) upsertProfile(ctx context.Context, tenantID string, p *Profile) (*Profile, error) {
	tx, err := m.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	nameTr, _ := json.Marshal(p.NameTranslations)
	settings, _ := json.Marshal(p.Settings)

	if p.IsDefault {
		// Flip any existing default off first; the partial unique index
		// would otherwise reject this row's insert/update.
		if _, err := tx.ExecContext(ctx, `
			UPDATE order_profiles SET is_default = FALSE
			WHERE tenant_id = $1 AND is_default = TRUE
		`, tenantID); err != nil {
			return nil, err
		}
	}

	if p.ID == "" {
		row := tx.QueryRowContext(ctx, `
			INSERT INTO order_profiles
			    (tenant_id, code, name, name_translations, description,
			     is_active, is_default, priority, settings)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
			RETURNING id::text
		`, tenantID, p.Code, p.Name, string(nameTr), p.Description,
			p.IsActive, p.IsDefault, p.Priority, string(settings))
		if err := row.Scan(&p.ID); err != nil {
			return nil, fmt.Errorf("insert: %w", err)
		}
	} else {
		res, err := tx.ExecContext(ctx, `
			UPDATE order_profiles SET
			    code = $3, name = $4, name_translations = $5, description = $6,
			    is_active = $7, is_default = $8, priority = $9, settings = $10,
			    updated_at = NOW()
			WHERE tenant_id = $1 AND id = $2
		`, tenantID, p.ID, p.Code, p.Name, string(nameTr), p.Description,
			p.IsActive, p.IsDefault, p.Priority, string(settings))
		if err != nil {
			return nil, fmt.Errorf("update: %w", err)
		}
		n, _ := res.RowsAffected()
		if n == 0 {
			return nil, errProfileNotFound
		}
		if _, err := tx.ExecContext(ctx,
			`DELETE FROM order_profile_pricing_rules WHERE profile_id = $1`, p.ID); err != nil {
			return nil, fmt.Errorf("clear rules: %w", err)
		}
	}

	for _, r := range p.PricingRules {
		if (r.CategoryID == nil) == (r.ProductID == nil) {
			continue // DB CHECK would reject; skip silently
		}
		if (r.OverridePriceCents == nil) == (r.DiscountPercent == nil) {
			continue
		}
		var catVal, prodVal any
		if r.CategoryID != nil {
			catVal = *r.CategoryID
		}
		if r.ProductID != nil {
			prodVal = *r.ProductID
		}
		var overrideVal, discountVal any
		if r.OverridePriceCents != nil {
			overrideVal = *r.OverridePriceCents
		}
		if r.DiscountPercent != nil {
			discountVal = *r.DiscountPercent
		}
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO order_profile_pricing_rules
			    (profile_id, category_id, product_id, override_price_cents, discount_percent)
			VALUES ($1, $2, $3, $4, $5)
		`, p.ID, catVal, prodVal, overrideVal, discountVal); err != nil {
			return nil, fmt.Errorf("insert rule: %w", err)
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return m.getProfile(ctx, tenantID, p.ID)
}

func (m *Module) deleteProfile(ctx context.Context, tenantID, profileID string) error {
	res, err := m.db.ExecContext(ctx,
		`DELETE FROM order_profiles WHERE tenant_id = $1 AND id = $2 AND is_default = FALSE`,
		tenantID, profileID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return errProfileNotFound
	}
	return nil
}
