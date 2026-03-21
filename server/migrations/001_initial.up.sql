-- GastroCore Initial Schema
-- Maps Flutter SQLite schema to PostgreSQL 16 with proper types.
-- All IDs are UUID, all timestamps are TIMESTAMPTZ, JSON fields use JSONB.

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- TENANTS
-- ============================================================
CREATE TABLE tenants (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        TEXT NOT NULL,
    address     TEXT,
    phone       TEXT,
    tax_id      TEXT,
    default_tax_rate NUMERIC(5,2) NOT NULL DEFAULT 0.0,
    currency_code TEXT NOT NULL DEFAULT 'CHF',
    country_code  TEXT NOT NULL DEFAULT 'CH',
    settings    JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- USERS (staff members)
-- ============================================================
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id),
    name        TEXT NOT NULL,
    email       TEXT,
    password_hash TEXT,
    pin_hash    TEXT NOT NULL,
    role        TEXT NOT NULL DEFAULT 'waiter',
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    permissions JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status INTEGER NOT NULL DEFAULT 0,
    is_deleted  BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_users_tenant_id ON users(tenant_id);
CREATE INDEX idx_users_email ON users(email) WHERE email IS NOT NULL;
CREATE INDEX idx_users_role ON users(tenant_id, role);

-- ============================================================
-- CATEGORIES
-- ============================================================
CREATE TABLE categories (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID NOT NULL REFERENCES tenants(id),
    name          TEXT NOT NULL,
    display_order INTEGER NOT NULL DEFAULT 0,
    color         TEXT,
    icon          TEXT,
    parent_id     UUID REFERENCES categories(id),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status   INTEGER NOT NULL DEFAULT 0,
    is_deleted    BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_categories_tenant_id ON categories(tenant_id);
CREATE INDEX idx_categories_parent_id ON categories(parent_id) WHERE parent_id IS NOT NULL;

-- ============================================================
-- PRODUCTS
-- ============================================================
CREATE TABLE products (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id        UUID NOT NULL REFERENCES tenants(id),
    category_id      UUID NOT NULL REFERENCES categories(id),
    name             TEXT NOT NULL,
    description      TEXT,
    price            BIGINT NOT NULL,
    cost_price       BIGINT NOT NULL DEFAULT 0,
    tax_group        TEXT NOT NULL DEFAULT 'default',
    image_path       TEXT,
    barcode          TEXT,
    is_active        BOOLEAN NOT NULL DEFAULT TRUE,
    display_order    INTEGER NOT NULL DEFAULT 0,
    prep_time_minutes INTEGER,
    printer_group    TEXT NOT NULL DEFAULT 'kitchen',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status      INTEGER NOT NULL DEFAULT 0,
    is_deleted       BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_products_tenant_id ON products(tenant_id);
CREATE INDEX idx_products_category_id ON products(category_id);
CREATE INDEX idx_products_barcode ON products(barcode) WHERE barcode IS NOT NULL;
CREATE INDEX idx_products_active ON products(tenant_id, is_active) WHERE is_deleted = FALSE;

-- ============================================================
-- MODIFIER GROUPS
-- ============================================================
CREATE TABLE modifier_groups (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    name            TEXT NOT NULL,
    selection_type  TEXT NOT NULL DEFAULT 'single',
    min_selections  INTEGER NOT NULL DEFAULT 0,
    max_selections  INTEGER NOT NULL DEFAULT 1,
    is_required     BOOLEAN NOT NULL DEFAULT FALSE,
    display_order   INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status     INTEGER NOT NULL DEFAULT 0,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_modifier_groups_tenant_id ON modifier_groups(tenant_id);

-- ============================================================
-- MODIFIERS
-- ============================================================
CREATE TABLE modifiers (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID NOT NULL REFERENCES tenants(id),
    group_id      UUID NOT NULL REFERENCES modifier_groups(id),
    name          TEXT NOT NULL,
    price_delta   BIGINT NOT NULL DEFAULT 0,
    is_default    BOOLEAN NOT NULL DEFAULT FALSE,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status   INTEGER NOT NULL DEFAULT 0,
    is_deleted    BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_modifiers_group_id ON modifiers(group_id);

-- ============================================================
-- PRODUCT <-> MODIFIER GROUP (join table)
-- ============================================================
CREATE TABLE product_modifier_groups (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id        UUID NOT NULL REFERENCES products(id),
    modifier_group_id UUID NOT NULL REFERENCES modifier_groups(id),
    display_order     INTEGER NOT NULL DEFAULT 0,
    UNIQUE(product_id, modifier_group_id)
);

CREATE INDEX idx_pmg_product_id ON product_modifier_groups(product_id);
CREATE INDEX idx_pmg_modifier_group_id ON product_modifier_groups(modifier_group_id);

-- ============================================================
-- FLOORS
-- ============================================================
CREATE TABLE floors (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID NOT NULL REFERENCES tenants(id),
    name          TEXT NOT NULL,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status   INTEGER NOT NULL DEFAULT 0,
    is_deleted    BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_floors_tenant_id ON floors(tenant_id);

-- ============================================================
-- RESTAURANT TABLES
-- ============================================================
CREATE TABLE restaurant_tables (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    floor_id        UUID NOT NULL REFERENCES floors(id),
    name            TEXT NOT NULL,
    capacity        INTEGER NOT NULL DEFAULT 4,
    shape           TEXT NOT NULL DEFAULT 'rectangle',
    pos_x           DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    pos_y           DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    width           DOUBLE PRECISION NOT NULL DEFAULT 100.0,
    height          DOUBLE PRECISION NOT NULL DEFAULT 100.0,
    status          TEXT NOT NULL DEFAULT 'available',
    current_order_id UUID,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status     INTEGER NOT NULL DEFAULT 0,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_tables_tenant_id ON restaurant_tables(tenant_id);
CREATE INDEX idx_tables_floor_id ON restaurant_tables(floor_id);
CREATE INDEX idx_tables_status ON restaurant_tables(tenant_id, status) WHERE is_deleted = FALSE;

-- ============================================================
-- TICKETS (orders)
-- ============================================================
CREATE TABLE tickets (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    order_number    INTEGER NOT NULL,
    order_type      TEXT NOT NULL DEFAULT 'dine_in',
    table_id        UUID REFERENCES restaurant_tables(id),
    waiter_id       UUID REFERENCES users(id),
    customer_name   TEXT,
    guest_count     INTEGER NOT NULL DEFAULT 1,
    status          TEXT NOT NULL DEFAULT 'open',
    channel         TEXT NOT NULL DEFAULT 'pos',
    subtotal        BIGINT NOT NULL DEFAULT 0,
    tax_amount      BIGINT NOT NULL DEFAULT 0,
    discount_amount BIGINT NOT NULL DEFAULT 0,
    discount_type   TEXT,
    discount_value  DOUBLE PRECISION,
    total           BIGINT NOT NULL DEFAULT 0,
    notes           TEXT,
    opened_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at       TIMESTAMPTZ,
    device_id       TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status     INTEGER NOT NULL DEFAULT 0,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_tickets_tenant_id ON tickets(tenant_id);
CREATE INDEX idx_tickets_status ON tickets(tenant_id, status) WHERE is_deleted = FALSE;
CREATE INDEX idx_tickets_created_at ON tickets(tenant_id, created_at);
CREATE INDEX idx_tickets_waiter_id ON tickets(waiter_id) WHERE waiter_id IS NOT NULL;
CREATE INDEX idx_tickets_table_id ON tickets(table_id) WHERE table_id IS NOT NULL;
CREATE INDEX idx_tickets_order_number ON tickets(tenant_id, order_number);

-- ============================================================
-- ORDER ITEMS
-- ============================================================
CREATE TABLE order_items (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    ticket_id       UUID NOT NULL REFERENCES tickets(id),
    product_id      UUID NOT NULL REFERENCES products(id),
    product_name    TEXT NOT NULL,
    quantity        DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    unit_price      BIGINT NOT NULL,
    subtotal        BIGINT NOT NULL,
    tax_amount      BIGINT NOT NULL DEFAULT 0,
    discount_amount BIGINT NOT NULL DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'ordered',
    sent_to_kitchen BOOLEAN NOT NULL DEFAULT FALSE,
    notes           TEXT,
    course          INTEGER NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status     INTEGER NOT NULL DEFAULT 0,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_order_items_ticket_id ON order_items(ticket_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_order_items_status ON order_items(status);

-- ============================================================
-- ORDER ITEM MODIFIERS
-- ============================================================
CREATE TABLE order_item_modifiers (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_item_id UUID NOT NULL REFERENCES order_items(id),
    modifier_id   UUID NOT NULL REFERENCES modifiers(id),
    modifier_name TEXT NOT NULL,
    price_delta   BIGINT NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_oim_order_item_id ON order_item_modifiers(order_item_id);

-- ============================================================
-- BILLS
-- ============================================================
CREATE TABLE bills (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    ticket_id       UUID NOT NULL REFERENCES tickets(id),
    bill_number     INTEGER NOT NULL,
    subtotal        BIGINT NOT NULL,
    tax_amount      BIGINT NOT NULL DEFAULT 0,
    discount_amount BIGINT NOT NULL DEFAULT 0,
    total           BIGINT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'open',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status     INTEGER NOT NULL DEFAULT 0,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_bills_tenant_id ON bills(tenant_id);
CREATE INDEX idx_bills_ticket_id ON bills(ticket_id);
CREATE INDEX idx_bills_status ON bills(tenant_id, status);

-- ============================================================
-- PAYMENTS
-- ============================================================
CREATE TABLE payments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    bill_id         UUID NOT NULL REFERENCES bills(id),
    ticket_id       UUID NOT NULL REFERENCES tickets(id),
    payment_method  TEXT NOT NULL,
    amount          BIGINT NOT NULL,
    tip_amount      BIGINT NOT NULL DEFAULT 0,
    tendered_amount BIGINT NOT NULL DEFAULT 0,
    change_amount   BIGINT NOT NULL DEFAULT 0,
    reference       TEXT,
    received_by     UUID NOT NULL REFERENCES users(id),
    paid_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status     INTEGER NOT NULL DEFAULT 0,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_payments_tenant_id ON payments(tenant_id);
CREATE INDEX idx_payments_bill_id ON payments(bill_id);
CREATE INDEX idx_payments_ticket_id ON payments(ticket_id);
CREATE INDEX idx_payments_paid_at ON payments(tenant_id, paid_at);
CREATE INDEX idx_payments_method ON payments(tenant_id, payment_method);

-- ============================================================
-- SHIFTS
-- ============================================================
CREATE TABLE shifts (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID NOT NULL REFERENCES tenants(id),
    user_id       UUID NOT NULL REFERENCES users(id),
    device_id     TEXT NOT NULL,
    opening_cash  BIGINT NOT NULL,
    closing_cash  BIGINT,
    expected_cash BIGINT,
    difference    BIGINT,
    total_sales   BIGINT NOT NULL DEFAULT 0,
    total_orders  INTEGER NOT NULL DEFAULT 0,
    status        TEXT NOT NULL DEFAULT 'open',
    opened_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at     TIMESTAMPTZ,
    notes         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status   INTEGER NOT NULL DEFAULT 0,
    is_deleted    BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_shifts_tenant_id ON shifts(tenant_id);
CREATE INDEX idx_shifts_user_id ON shifts(user_id);
CREATE INDEX idx_shifts_status ON shifts(tenant_id, status);
CREATE INDEX idx_shifts_opened_at ON shifts(tenant_id, opened_at);

-- ============================================================
-- CASH MOVEMENTS
-- ============================================================
CREATE TABLE cash_movements (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID NOT NULL REFERENCES tenants(id),
    shift_id      UUID NOT NULL REFERENCES shifts(id),
    type          TEXT NOT NULL,
    amount        BIGINT NOT NULL,
    description   TEXT,
    performed_by  UUID NOT NULL REFERENCES users(id),
    performed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status   INTEGER NOT NULL DEFAULT 0,
    is_deleted    BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_cash_movements_shift_id ON cash_movements(shift_id);
CREATE INDEX idx_cash_movements_tenant_id ON cash_movements(tenant_id);

-- ============================================================
-- KITCHEN TICKETS
-- ============================================================
CREATE TABLE kitchen_tickets (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id         UUID NOT NULL REFERENCES tenants(id),
    ticket_id         UUID NOT NULL REFERENCES tickets(id),
    kitchen_table_name TEXT,
    order_number      INTEGER NOT NULL,
    printer_group     TEXT NOT NULL DEFAULT 'kitchen',
    status            TEXT NOT NULL DEFAULT 'pending',
    sent_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at        TIMESTAMPTZ,
    completed_at      TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status       INTEGER NOT NULL DEFAULT 0,
    is_deleted        BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_kitchen_tickets_tenant_id ON kitchen_tickets(tenant_id);
CREATE INDEX idx_kitchen_tickets_ticket_id ON kitchen_tickets(ticket_id);
CREATE INDEX idx_kitchen_tickets_status ON kitchen_tickets(tenant_id, status);

-- ============================================================
-- KITCHEN TICKET ITEMS
-- ============================================================
CREATE TABLE kitchen_ticket_items (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    kitchen_ticket_id UUID NOT NULL REFERENCES kitchen_tickets(id),
    order_item_id     UUID NOT NULL REFERENCES order_items(id),
    product_name      TEXT NOT NULL,
    quantity          DOUBLE PRECISION NOT NULL,
    modifiers_text    TEXT,
    notes             TEXT,
    status            TEXT NOT NULL DEFAULT 'pending',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_kti_kitchen_ticket_id ON kitchen_ticket_items(kitchen_ticket_id);

-- ============================================================
-- RECEIPTS
-- ============================================================
CREATE TABLE receipts (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id      UUID NOT NULL REFERENCES tenants(id),
    ticket_id      UUID NOT NULL REFERENCES tickets(id),
    bill_id        UUID NOT NULL REFERENCES bills(id),
    receipt_number TEXT NOT NULL,
    receipt_type   TEXT NOT NULL DEFAULT 'sale',
    content        JSONB NOT NULL,
    printed_at     TIMESTAMPTZ,
    print_count    INTEGER NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status    INTEGER NOT NULL DEFAULT 0,
    is_deleted     BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_receipts_tenant_id ON receipts(tenant_id);
CREATE INDEX idx_receipts_ticket_id ON receipts(ticket_id);
CREATE INDEX idx_receipts_receipt_number ON receipts(tenant_id, receipt_number);

-- ============================================================
-- AUDIT LOG
-- ============================================================
CREATE TABLE audit_log (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id),
    branch_id   UUID,
    device_id   TEXT NOT NULL,
    user_id     UUID NOT NULL REFERENCES users(id),
    entity_type TEXT NOT NULL,
    entity_id   UUID NOT NULL,
    action      TEXT NOT NULL,
    old_value   JSONB,
    new_value   JSONB,
    timestamp   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_log_tenant_id ON audit_log(tenant_id);
CREATE INDEX idx_audit_log_entity ON audit_log(entity_type, entity_id);
CREATE INDEX idx_audit_log_timestamp ON audit_log(tenant_id, timestamp);
CREATE INDEX idx_audit_log_user_id ON audit_log(user_id);

-- ============================================================
-- CLOUD-ONLY TABLES
-- ============================================================

-- Device registrations (cloud manages device lifecycle)
CREATE TABLE device_registrations (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id),
    device_name TEXT NOT NULL,
    device_type TEXT NOT NULL DEFAULT 'pos',
    token_hash  TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'active',
    app_version TEXT,
    os_version  TEXT,
    capabilities JSONB,
    last_seen_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted  BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_device_reg_tenant_id ON device_registrations(tenant_id);
CREATE INDEX idx_device_reg_status ON device_registrations(tenant_id, status);

-- Tenant subscriptions
CREATE TABLE tenant_subscriptions (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID NOT NULL REFERENCES tenants(id),
    license_key   TEXT NOT NULL UNIQUE,
    plan          TEXT NOT NULL DEFAULT 'starter',
    status        TEXT NOT NULL DEFAULT 'trial',
    max_devices   INTEGER NOT NULL DEFAULT 1,
    start_date    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    end_date      TIMESTAMPTZ,
    trial_ends_at TIMESTAMPTZ,
    features      JSONB NOT NULL DEFAULT '{}',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_subscriptions_tenant_id ON tenant_subscriptions(tenant_id);
CREATE INDEX idx_subscriptions_license_key ON tenant_subscriptions(license_key);
CREATE INDEX idx_subscriptions_status ON tenant_subscriptions(status);

-- Sync batches (tracks upload/download history)
CREATE TABLE sync_batches (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id),
    device_id   UUID NOT NULL REFERENCES device_registrations(id),
    direction   TEXT NOT NULL,
    entity_count INTEGER NOT NULL DEFAULT 0,
    status      TEXT NOT NULL DEFAULT 'pending',
    payload     JSONB,
    cursor_before TEXT,
    cursor_after  TEXT,
    error_message TEXT,
    started_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sync_batches_tenant_id ON sync_batches(tenant_id);
CREATE INDEX idx_sync_batches_device_id ON sync_batches(device_id);
CREATE INDEX idx_sync_batches_status ON sync_batches(status);
CREATE INDEX idx_sync_batches_created_at ON sync_batches(created_at);

-- API keys for external integrations
CREATE TABLE api_keys (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id),
    name        TEXT NOT NULL,
    key_hash    TEXT NOT NULL,
    key_prefix  TEXT NOT NULL,
    scopes      JSONB NOT NULL DEFAULT '[]',
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    last_used_at TIMESTAMPTZ,
    expires_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_api_keys_tenant_id ON api_keys(tenant_id);
CREATE INDEX idx_api_keys_key_prefix ON api_keys(key_prefix);

-- ============================================================
-- MATERIALIZED VIEWS FOR REPORTS
-- ============================================================

-- Daily sales summary (refreshed periodically)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_daily_sales AS
SELECT
    t.tenant_id,
    DATE(t.created_at AT TIME ZONE 'UTC') AS sale_date,
    COUNT(DISTINCT t.id) AS total_orders,
    SUM(t.total) AS total_revenue,
    SUM(t.tax_amount) AS total_tax,
    SUM(t.discount_amount) AS total_discounts,
    AVG(t.total) AS avg_order_value,
    COUNT(DISTINCT t.waiter_id) AS active_staff
FROM tickets t
WHERE t.is_deleted = FALSE
  AND t.status IN ('fully_paid', 'closed')
GROUP BY t.tenant_id, DATE(t.created_at AT TIME ZONE 'UTC');

CREATE UNIQUE INDEX idx_mv_daily_sales ON mv_daily_sales(tenant_id, sale_date);

-- Product performance (refreshed periodically)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_product_performance AS
SELECT
    oi.tenant_id,
    oi.product_id,
    oi.product_name,
    DATE(oi.created_at AT TIME ZONE 'UTC') AS sale_date,
    SUM(oi.quantity) AS total_quantity,
    SUM(oi.subtotal) AS total_revenue,
    COUNT(DISTINCT oi.ticket_id) AS order_count
FROM order_items oi
WHERE oi.is_deleted = FALSE
  AND oi.status != 'void'
GROUP BY oi.tenant_id, oi.product_id, oi.product_name, DATE(oi.created_at AT TIME ZONE 'UTC');

CREATE UNIQUE INDEX idx_mv_product_perf ON mv_product_performance(tenant_id, product_id, sale_date);

-- ============================================================
-- UPDATED_AT TRIGGER FUNCTION
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to all mutable tables
DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOR tbl IN
        SELECT unnest(ARRAY[
            'tenants', 'users', 'categories', 'products',
            'modifier_groups', 'modifiers', 'floors', 'restaurant_tables',
            'tickets', 'order_items', 'bills', 'payments',
            'shifts', 'cash_movements', 'kitchen_tickets', 'receipts',
            'device_registrations', 'tenant_subscriptions', 'api_keys'
        ])
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%s_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION update_updated_at()',
            tbl, tbl
        );
    END LOOP;
END;
$$;
