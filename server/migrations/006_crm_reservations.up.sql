-- Migration 006: CRM customers, loyalty transactions, and reservations
-- Adds customer management, loyalty points tracking, and table reservation system.

-- ---------------------------------------------------------------------------
-- customers: CRM contact records with loyalty balance
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customers (
    id                TEXT        PRIMARY KEY,
    tenant_id         TEXT        NOT NULL,
    name              TEXT        NOT NULL,
    phone             TEXT,
    email             TEXT,
    birthday          TEXT,           -- YYYY-MM-DD
    notes             TEXT,
    loyalty_points    INTEGER     NOT NULL DEFAULT 0,
    total_visits      INTEGER     NOT NULL DEFAULT 0,
    total_spent_cents BIGINT      NOT NULL DEFAULT 0,
    last_visit_at     TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted        BOOLEAN     NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_customers_tenant
    ON customers(tenant_id)
    WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_customers_tenant_name
    ON customers(tenant_id, name)
    WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_customers_phone
    ON customers(tenant_id, phone)
    WHERE phone IS NOT NULL AND is_deleted = false;

-- ---------------------------------------------------------------------------
-- loyalty_transactions: point earn/redeem/adjust history
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS loyalty_transactions (
    id          TEXT        PRIMARY KEY,
    tenant_id   TEXT        NOT NULL,
    customer_id TEXT        NOT NULL REFERENCES customers(id),
    points      INTEGER     NOT NULL,   -- positive = earn, negative = redeem
    type        TEXT        NOT NULL,   -- earn | redeem | adjust
    description TEXT,
    ticket_id   TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_loyalty_customer
    ON loyalty_transactions(customer_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_loyalty_tenant
    ON loyalty_transactions(tenant_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- reservations: table booking system
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reservations (
    id               TEXT        PRIMARY KEY,
    tenant_id        TEXT        NOT NULL,
    customer_name    TEXT        NOT NULL,
    phone            TEXT,
    guest_count      INTEGER     NOT NULL DEFAULT 1,
    table_id         TEXT,               -- nullable: no table assigned yet
    date             TEXT        NOT NULL, -- YYYY-MM-DD
    time             TEXT        NOT NULL, -- HH:MM (24h)
    duration_minutes INTEGER     NOT NULL DEFAULT 90,
    status           TEXT        NOT NULL DEFAULT 'pending',
                                           -- pending | confirmed | seated | cancelled | no_show
    notes            TEXT,
    customer_id      TEXT        REFERENCES customers(id),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN     NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_reservations_tenant_date
    ON reservations(tenant_id, date)
    WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_reservations_tenant_status
    ON reservations(tenant_id, status)
    WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_reservations_table_date
    ON reservations(table_id, date)
    WHERE table_id IS NOT NULL AND is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_reservations_customer
    ON reservations(customer_id)
    WHERE customer_id IS NOT NULL AND is_deleted = false;
