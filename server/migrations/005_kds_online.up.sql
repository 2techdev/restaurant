-- Migration 005: KDS support + online ordering column additions
-- Adds kds_status to order_items for kitchen display tracking.
-- Adds missing columns to tenants for the online ordering public menu.
-- Adds missing columns to products for stock/prep-time tracking.

-- ---------------------------------------------------------------------------
-- order_items: KDS status
-- ---------------------------------------------------------------------------
ALTER TABLE order_items
    ADD COLUMN IF NOT EXISTS kds_status TEXT NOT NULL DEFAULT 'pending';

-- kds_status values: pending | preparing | ready | served
-- Index for efficient KDS queries (open kitchen items).
CREATE INDEX IF NOT EXISTS idx_order_items_kds_status
    ON order_items(ticket_id, kds_status)
    WHERE is_deleted = false;

-- ---------------------------------------------------------------------------
-- tenants: columns required by online ordering public menu
-- ---------------------------------------------------------------------------
ALTER TABLE tenants
    ADD COLUMN IF NOT EXISTS description     TEXT,
    ADD COLUMN IF NOT EXISTS logo_url        TEXT,
    ADD COLUMN IF NOT EXISTS cover_image_url TEXT,
    ADD COLUMN IF NOT EXISTS is_open         BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS is_deleted      BOOLEAN NOT NULL DEFAULT false;

-- ---------------------------------------------------------------------------
-- products: stock status + prep time (if not already present)
-- ---------------------------------------------------------------------------
ALTER TABLE products
    ADD COLUMN IF NOT EXISTS stock_status       TEXT    NOT NULL DEFAULT 'in_stock',
    ADD COLUMN IF NOT EXISTS prep_time_minutes  INTEGER;

-- stock_status values: in_stock | out_of_stock | low_stock | delisted

-- ---------------------------------------------------------------------------
-- devices: add device_token column (used by auth module)
-- ---------------------------------------------------------------------------
ALTER TABLE devices
    ADD COLUMN IF NOT EXISTS device_token TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_token
    ON devices(device_token)
    WHERE device_token IS NOT NULL;
