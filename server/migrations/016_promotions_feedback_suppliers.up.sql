-- Migration 016: feedback, promotions, suppliers, notification preferences
-- Adds tables required by the missing-endpoint coverage pass.
-- Notes:
--   * tenant_id is TEXT to stay consistent with the 006_crm_reservations
--     style (reservations.tenant_id, customers.tenant_id are TEXT). UUID
--     casting at the application layer remains valid because canonical UUID
--     strings are stored as-is.
--   * IF NOT EXISTS guards everywhere so re-applying never breaks.

-- ---------------------------------------------------------------------------
-- feedback: customer reviews / comments tied (optionally) to orders
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS feedback (
    id           TEXT        PRIMARY KEY,
    tenant_id    TEXT        NOT NULL,
    customer_id  TEXT        REFERENCES customers(id),
    order_id     TEXT,
    rating       INTEGER     NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment      TEXT,
    resolved     BOOLEAN     NOT NULL DEFAULT false,
    resolved_by  TEXT,
    resolved_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_feedback_tenant_created
    ON feedback(tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_feedback_unresolved
    ON feedback(tenant_id, resolved, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_feedback_customer
    ON feedback(customer_id)
    WHERE customer_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- suppliers: vendor master records for inventory restocking
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS suppliers (
    id            TEXT        PRIMARY KEY,
    tenant_id     TEXT        NOT NULL,
    name          TEXT        NOT NULL,
    contact_name  TEXT,
    email         TEXT,
    phone         TEXT,
    address       TEXT,
    notes         TEXT,
    is_active     BOOLEAN     NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted    BOOLEAN     NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_suppliers_tenant
    ON suppliers(tenant_id)
    WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_suppliers_tenant_name
    ON suppliers(tenant_id, name)
    WHERE is_deleted = false;

-- ---------------------------------------------------------------------------
-- discounts: catalog of reusable discount rules
-- type: PERCENT (value=10 means 10%), FIXED (value=500 = 500 cents off), BOGO
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS discounts (
    id                     TEXT        PRIMARY KEY,
    tenant_id              TEXT        NOT NULL,
    name                   TEXT        NOT NULL,
    type                   TEXT        NOT NULL CHECK (type IN ('PERCENT','FIXED','BOGO')),
    value                  NUMERIC(10,2) NOT NULL DEFAULT 0,
    active                 BOOLEAN     NOT NULL DEFAULT true,
    starts_at              TIMESTAMPTZ,
    ends_at                TIMESTAMPTZ,
    applies_to_categories  TEXT[],
    applies_to_products    TEXT[],
    min_order_cents        BIGINT,
    notes                  TEXT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted             BOOLEAN     NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_discounts_tenant_active
    ON discounts(tenant_id, active)
    WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_discounts_tenant_window
    ON discounts(tenant_id, starts_at, ends_at)
    WHERE is_deleted = false AND active = true;

-- ---------------------------------------------------------------------------
-- campaigns: marketing campaigns; can group discounts and target channels
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS campaigns (
    id            TEXT        PRIMARY KEY,
    tenant_id     TEXT        NOT NULL,
    name          TEXT        NOT NULL,
    description   TEXT,
    starts_at     TIMESTAMPTZ,
    ends_at       TIMESTAMPTZ,
    active        BOOLEAN     NOT NULL DEFAULT true,
    channels      TEXT[],          -- email, sms, app, push
    discount_id   TEXT REFERENCES discounts(id),
    audience      TEXT,            -- all | loyalty | vip | segment_<name>
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted    BOOLEAN     NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_campaigns_tenant_active
    ON campaigns(tenant_id, active)
    WHERE is_deleted = false;

-- ---------------------------------------------------------------------------
-- notification_preferences: per-user prefs for email / push / sms / channels
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notification_preferences (
    user_id              TEXT        PRIMARY KEY,
    tenant_id            TEXT        NOT NULL,
    email_enabled        BOOLEAN     NOT NULL DEFAULT true,
    push_enabled         BOOLEAN     NOT NULL DEFAULT true,
    sms_enabled          BOOLEAN     NOT NULL DEFAULT false,
    new_order_alerts     BOOLEAN     NOT NULL DEFAULT true,
    low_stock_alerts     BOOLEAN     NOT NULL DEFAULT true,
    daily_summary        BOOLEAN     NOT NULL DEFAULT true,
    weekly_summary       BOOLEAN     NOT NULL DEFAULT false,
    feedback_alerts      BOOLEAN     NOT NULL DEFAULT true,
    quiet_hours_start    TEXT,           -- HH:MM
    quiet_hours_end      TEXT,
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_prefs_tenant
    ON notification_preferences(tenant_id);

-- ---------------------------------------------------------------------------
-- inventory_items: optional supplier_id link (existing supplier TEXT column
-- stays for legacy free-text vendor names). Add column only if missing.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'inventory_items' AND column_name = 'supplier_id'
    ) THEN
        ALTER TABLE inventory_items ADD COLUMN supplier_id TEXT;
        CREATE INDEX idx_inventory_items_supplier
            ON inventory_items(supplier_id)
            WHERE supplier_id IS NOT NULL;
    END IF;
END$$;
