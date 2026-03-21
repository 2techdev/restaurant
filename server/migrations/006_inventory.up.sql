-- Inventory module: stock items and movements.
-- inventory_items holds the current stock level for each ingredient / product.
-- stock_movements is an append-only ledger of every quantity change.

-- ============================================================
-- INVENTORY ITEMS
-- ============================================================
CREATE TABLE inventory_items (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id        UUID NOT NULL REFERENCES tenants(id),
    name             TEXT NOT NULL,
    sku              TEXT,
    unit             TEXT NOT NULL DEFAULT 'unit',  -- unit, kg, litre, portion …
    current_qty      NUMERIC(12, 3) NOT NULL DEFAULT 0,
    min_qty          NUMERIC(12, 3) NOT NULL DEFAULT 0,
    max_qty          NUMERIC(12, 3),
    cost_per_unit    INTEGER,  -- cents
    supplier         TEXT,
    notes            TEXT,
    is_active        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_inventory_items_tenant ON inventory_items(tenant_id) WHERE is_deleted = FALSE;
CREATE UNIQUE INDEX idx_inventory_items_sku   ON inventory_items(tenant_id, sku) WHERE sku IS NOT NULL AND is_deleted = FALSE;

-- ============================================================
-- STOCK MOVEMENTS
-- ============================================================
-- movement_type values: stock_in | stock_out | waste | restock | adjustment
CREATE TABLE stock_movements (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id        UUID NOT NULL REFERENCES tenants(id),
    item_id          UUID NOT NULL REFERENCES inventory_items(id),
    movement_type    TEXT NOT NULL,
    qty              NUMERIC(12, 3) NOT NULL,  -- always positive; sign derived from type
    qty_before       NUMERIC(12, 3) NOT NULL,
    qty_after        NUMERIC(12, 3) NOT NULL,
    reference        TEXT,  -- e.g. ticket ID for stock_out
    notes            TEXT,
    performed_by     UUID REFERENCES users(id),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_stock_movements_item      ON stock_movements(item_id, created_at DESC);
CREATE INDEX idx_stock_movements_tenant    ON stock_movements(tenant_id, created_at DESC);
CREATE INDEX idx_stock_movements_type      ON stock_movements(tenant_id, movement_type);
