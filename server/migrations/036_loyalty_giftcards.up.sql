-- ---------------------------------------------------------------------------
-- 036 — Loyalty tiers + Gift Card 2.0
--
-- Builds on the basic loyalty_transactions / customers.loyalty_points scaffold
-- from migration 006. Adds:
--   1. Per-tenant tier definitions (Bronze / Silver / Gold / Platinum)
--      with point ranges, earn multiplier and a free-form benefits JSON.
--   2. Augments `customers` with total_earned + current_tier + tier_upgrade_at
--      so tier transitions are queryable without scanning the whole tx log.
--   3. Extends loyalty_transactions.type to allow 'expire' (in addition to
--      the existing earn / redeem / adjust).
--   4. Bonus campaigns table (point multiplier window — "%2x weekend").
--   5. Gift cards + per-card transaction history with partial redeem support.
--
-- Idempotent — every ALTER guarded with IF NOT EXISTS, every INSERT uses
-- ON CONFLICT DO NOTHING.
-- ---------------------------------------------------------------------------

-- =========================================================================
-- 1. loyalty_tiers — per-tenant tier definitions
-- =========================================================================
CREATE TABLE IF NOT EXISTS loyalty_tiers (
    id              TEXT        PRIMARY KEY,
    tenant_id       TEXT        NOT NULL,
    code            TEXT        NOT NULL,           -- bronze | silver | gold | platinum (or custom)
    name            TEXT        NOT NULL,           -- display name in primary locale
    name_translations JSONB     NOT NULL DEFAULT '{}'::jsonb,
    min_points      INTEGER     NOT NULL DEFAULT 0,
    max_points      INTEGER,                        -- NULL = unbounded (top tier)
    multiplier      NUMERIC(5,2) NOT NULL DEFAULT 1.00, -- earn multiplier on top of base rate
    benefits        JSONB       NOT NULL DEFAULT '[]'::jsonb, -- e.g. [{"type":"discount_pct","value":5},{"type":"free_dessert"}]
    color_hex       TEXT,                            -- optional badge color for UI
    sort_order      INTEGER     NOT NULL DEFAULT 0,
    is_active       BOOLEAN     NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT loyalty_tiers_tenant_code_uk UNIQUE (tenant_id, code)
);

CREATE INDEX IF NOT EXISTS idx_loyalty_tiers_tenant
    ON loyalty_tiers(tenant_id, sort_order)
    WHERE is_active = true;

-- =========================================================================
-- 2. customers — extend with tier columns
-- =========================================================================
ALTER TABLE customers
    ADD COLUMN IF NOT EXISTS total_earned    INTEGER     NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS current_tier    TEXT,                    -- denormalized FK by code → loyalty_tiers.code
    ADD COLUMN IF NOT EXISTS tier_upgrade_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_customers_tenant_tier
    ON customers(tenant_id, current_tier)
    WHERE is_deleted = false AND current_tier IS NOT NULL;

-- =========================================================================
-- 3. loyalty_transactions — extend type enum to allow 'expire'
--    (existing CHECK constraint is implicit / absent; we add an explicit one)
-- =========================================================================
ALTER TABLE loyalty_transactions DROP CONSTRAINT IF EXISTS loyalty_transactions_type_check;
ALTER TABLE loyalty_transactions
    ADD CONSTRAINT loyalty_transactions_type_check
        CHECK (type IN ('earn', 'redeem', 'expire', 'adjust'));

-- Order linkage column — `ticket_id` already exists from migration 006 and
-- serves this purpose. No change needed; keep the column for legacy compat.

-- =========================================================================
-- 4. loyalty_bonus_campaigns — earn multiplier windows
-- =========================================================================
CREATE TABLE IF NOT EXISTS loyalty_bonus_campaigns (
    id            TEXT        PRIMARY KEY,
    tenant_id     TEXT        NOT NULL,
    name          TEXT        NOT NULL,
    description   TEXT,
    multiplier    NUMERIC(5,2) NOT NULL DEFAULT 2.00,
    starts_at     TIMESTAMPTZ NOT NULL,
    ends_at       TIMESTAMPTZ NOT NULL,
    is_active     BOOLEAN     NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_loyalty_bonus_campaigns_active
    ON loyalty_bonus_campaigns(tenant_id, starts_at, ends_at)
    WHERE is_active = true;

-- =========================================================================
-- 5. gift_cards — issued cards
-- =========================================================================
CREATE TABLE IF NOT EXISTS gift_cards (
    id                  TEXT        PRIMARY KEY,
    tenant_id           TEXT        NOT NULL,
    code                TEXT        NOT NULL,             -- human-shareable code (GC-XXXX-XXXX)
    denomination_cents  BIGINT      NOT NULL,             -- original face value
    balance_cents       BIGINT      NOT NULL,             -- remaining balance
    issued_to_customer_id TEXT      REFERENCES customers(id),
    issued_by_user_id   TEXT,                              -- admin user who created it
    issued_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ NOT NULL,
    status              TEXT        NOT NULL DEFAULT 'active', -- active | redeemed | expired | voided
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT gift_cards_code_uk UNIQUE (code),
    CONSTRAINT gift_cards_status_check
        CHECK (status IN ('active', 'redeemed', 'expired', 'voided')),
    CONSTRAINT gift_cards_balance_nonneg CHECK (balance_cents >= 0),
    CONSTRAINT gift_cards_balance_le_denom CHECK (balance_cents <= denomination_cents)
);

CREATE INDEX IF NOT EXISTS idx_gift_cards_tenant_status
    ON gift_cards(tenant_id, status, issued_at DESC);

CREATE INDEX IF NOT EXISTS idx_gift_cards_customer
    ON gift_cards(issued_to_customer_id)
    WHERE issued_to_customer_id IS NOT NULL;

-- =========================================================================
-- 6. gift_card_transactions — per-card ledger
-- =========================================================================
CREATE TABLE IF NOT EXISTS gift_card_transactions (
    id                  TEXT        PRIMARY KEY,
    gift_card_id        TEXT        NOT NULL REFERENCES gift_cards(id),
    tenant_id           TEXT        NOT NULL,
    type                TEXT        NOT NULL,        -- issue | redeem | refund | void | expire
    amount_cents        BIGINT      NOT NULL,        -- positive = credit (issue/refund), negative = debit (redeem)
    order_id            TEXT,                          -- optional link to the order that redeemed it
    balance_after_cents BIGINT      NOT NULL,
    description         TEXT,
    created_by_user_id  TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT gift_card_transactions_type_check
        CHECK (type IN ('issue', 'redeem', 'refund', 'void', 'expire'))
);

CREATE INDEX IF NOT EXISTS idx_gift_card_transactions_card
    ON gift_card_transactions(gift_card_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_gift_card_transactions_tenant
    ON gift_card_transactions(tenant_id, created_at DESC);

-- =========================================================================
-- 7. Default tier seed (Bronze / Silver / Gold / Platinum)
--    Inserted for every existing tenant. Idempotent via ON CONFLICT.
-- =========================================================================
INSERT INTO loyalty_tiers (id, tenant_id, code, name, name_translations,
                            min_points, max_points, multiplier, benefits,
                            color_hex, sort_order)
SELECT
    gen_random_uuid()::text,
    t.id,
    seed.code,
    seed.name,
    seed.name_translations::jsonb,
    seed.min_points,
    seed.max_points,
    seed.multiplier,
    seed.benefits::jsonb,
    seed.color_hex,
    seed.sort_order
FROM tenants t
CROSS JOIN (VALUES
    ('bronze',   'Bronze',
        '{"de":"Bronze","en":"Bronze","fr":"Bronze","it":"Bronzo","tr":"Bronz"}',
        0,    499,  1.00,
        '[]',
        '#CD7F32', 1),
    ('silver',   'Silber',
        '{"de":"Silber","en":"Silver","fr":"Argent","it":"Argento","tr":"Gümüş"}',
        500,  1499, 1.25,
        '[{"type":"discount_pct","value":5}]',
        '#C0C0C0', 2),
    ('gold',     'Gold',
        '{"de":"Gold","en":"Gold","fr":"Or","it":"Oro","tr":"Altın"}',
        1500, 4999, 1.50,
        '[{"type":"discount_pct","value":5},{"type":"free_dessert"}]',
        '#FFD700', 3),
    ('platinum', 'Platin',
        '{"de":"Platin","en":"Platinum","fr":"Platine","it":"Platino","tr":"Platin"}',
        5000, NULL, 2.00,
        '[{"type":"discount_pct","value":10},{"type":"free_dessert"},{"type":"vip_reservation"}]',
        '#E5E4E2', 4)
) AS seed(code, name, name_translations, min_points, max_points, multiplier, benefits, color_hex, sort_order)
ON CONFLICT (tenant_id, code) DO NOTHING;

-- =========================================================================
-- 8. loyalty_program_settings — per-tenant feature flag + base rate
--    1 row per tenant. earn_rate_chf_to_points: how many points per CHF spent
--    (default 1.0 — 1 point per 1 CHF). redeem_rate_points_to_chf: how many
--    points equal 1 CHF redeem (default 100 — 100 pts = CHF 1).
-- =========================================================================
CREATE TABLE IF NOT EXISTS loyalty_program_settings (
    tenant_id                  TEXT        PRIMARY KEY,
    is_enabled                 BOOLEAN     NOT NULL DEFAULT false,
    earn_rate_points_per_chf   NUMERIC(8,4) NOT NULL DEFAULT 1.0000,
    redeem_rate_points_per_chf NUMERIC(8,4) NOT NULL DEFAULT 100.0000,
    expiry_months              INTEGER     NOT NULL DEFAULT 24,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed defaults for existing tenants. is_enabled=false so operator opts in.
INSERT INTO loyalty_program_settings (tenant_id)
SELECT t.id FROM tenants t
ON CONFLICT (tenant_id) DO NOTHING;
