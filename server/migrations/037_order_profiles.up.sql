-- Migration 037: Order Profiles (time-based pricing + service charge + print rules).
--
-- An "order profile" is a named preset that augments the basic order type
-- (dine-in / takeaway / delivery) with: a schedule (weekday + time windows),
-- pricing overrides at category or product granularity, an optional service
-- charge, a receipt template override, kitchen/bar print routing rules, and
-- a visibility filter.  Examples:
--
--   "Normal"      — default, always on
--   "Happy Hour"  — Mon-Fri 16:00-18:00, -20% on drinks
--   "Mittagsmenü" — Mon-Fri 12:00-14:00, set price for lunch combos
--   "Late Night"  — daily 22:00-02:00, +CHF 1 service charge
--   "Brunch"      — Sat/Sun 09:00-14:00, brunch category visible only
--
-- The Go server recomputes which profiles are active every minute and
-- broadcasts a `profile_changed` WS event when the active set changes; POS
-- clients consume that to re-price the open cart.
--
-- Schema design notes:
--   - `settings` JSONB owns schedule + service_charge + print_rules +
--     visibility because they're rarely queried by SQL — the Go layer reads
--     the row, walks settings.schedule, and decides "is this profile active
--     right now?".  Keeping these in jsonb avoids 4 child tables for what
--     amounts to a single Go struct serialisation.
--   - `pricing_rules` is a separate relational table because the backoffice
--     UI lets the operator add/remove per-product/category overrides one at
--     a time and we need ON CONFLICT semantics + cascade-on-delete, which
--     are awkward inside a JSONB blob.
--   - `is_default` per tenant: exactly one row per tenant is the fallback
--     used when no scheduled profile matches.  Enforced by a partial unique
--     index, not a CHECK, so the default-flip update can be a two-statement
--     transaction (unset then set) instead of needing deferrable constraints.

CREATE TABLE IF NOT EXISTS order_profiles (
    id                  UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID         NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    code                TEXT         NOT NULL,
    name                TEXT         NOT NULL,
    name_translations   JSONB        NOT NULL DEFAULT '{}'::jsonb,
    description         TEXT         NOT NULL DEFAULT '',
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    is_default          BOOLEAN      NOT NULL DEFAULT FALSE,
    priority            INTEGER      NOT NULL DEFAULT 0,
    -- settings shape — see internal/orderprofiles/models.go:ProfileSettings
    -- {
    --   "schedule": [
    --     { "weekdays": [1,2,3,4,5], "starts_at": "16:00", "ends_at": "18:00" }
    --   ],
    --   "service_charge": { "kind": "percent" | "fixed", "value_cents": 100, "label": "Late Night Zuschlag" },
    --   "print_rules": { "kitchen": true, "bar": true, "receipt_copies": 1 },
    --   "visibility": { "categories": ["uuid",...], "products": ["uuid",...], "mode": "include" | "exclude" },
    --   "receipt_template_id": "uuid" | null
    -- }
    settings            JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, code)
);

-- Exactly one default per tenant.  Flip via tx: UPDATE … SET is_default=FALSE
-- WHERE tenant_id=$1; UPDATE … SET is_default=TRUE WHERE id=$2.
CREATE UNIQUE INDEX IF NOT EXISTS uq_order_profiles_default_per_tenant
    ON order_profiles(tenant_id)
    WHERE is_default = TRUE;

CREATE INDEX IF NOT EXISTS idx_order_profiles_tenant_active
    ON order_profiles(tenant_id, is_active);

-- Pricing rules: either a category-level override or a product-level
-- override.  Exactly one of category_id / product_id is set (CHECK).  The
-- value can be a fixed override price OR a discount percent, never both.
CREATE TABLE IF NOT EXISTS order_profile_pricing_rules (
    id                    UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    profile_id            UUID         NOT NULL REFERENCES order_profiles(id) ON DELETE CASCADE,
    category_id           UUID         REFERENCES categories(id) ON DELETE CASCADE,
    product_id            UUID         REFERENCES products(id) ON DELETE CASCADE,
    override_price_cents  BIGINT,
    discount_percent      NUMERIC(5,2),
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CHECK ( (category_id IS NULL) <> (product_id IS NULL) ),
    CHECK ( (override_price_cents IS NULL) <> (discount_percent IS NULL) ),
    CHECK ( override_price_cents IS NULL OR override_price_cents >= 0 ),
    CHECK ( discount_percent     IS NULL OR (discount_percent >= 0 AND discount_percent <= 100) )
);

-- One rule per (profile, category) and one rule per (profile, product) —
-- prevents duplicate / conflicting overrides for the same target.
CREATE UNIQUE INDEX IF NOT EXISTS uq_order_profile_pricing_category
    ON order_profile_pricing_rules(profile_id, category_id)
    WHERE category_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_order_profile_pricing_product
    ON order_profile_pricing_rules(profile_id, product_id)
    WHERE product_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_order_profile_pricing_profile
    ON order_profile_pricing_rules(profile_id);

-- ===========================================================
-- Seed the "Normal" default profile for every existing tenant.
-- Schedule omitted → always active (the fallback).
-- ===========================================================
INSERT INTO order_profiles (
    tenant_id, code, name, name_translations, description,
    is_active, is_default, priority, settings
)
SELECT
    t.id,
    'normal',
    'Normal',
    jsonb_build_object('de', 'Normal', 'en', 'Standard', 'fr', 'Normal', 'it', 'Normale', 'tr', 'Normal'),
    'Default profile — applies whenever no scheduled profile matches.',
    TRUE,  -- is_active
    TRUE,  -- is_default
    0,     -- priority (lowest)
    jsonb_build_object(
        'schedule', '[]'::jsonb,
        'print_rules', jsonb_build_object('kitchen', TRUE, 'bar', TRUE, 'receipt_copies', 1)
    )
FROM tenants t
ON CONFLICT (tenant_id, code) DO NOTHING;
