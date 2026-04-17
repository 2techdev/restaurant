-- Migration 011: kitchen/bar stations for product routing
-- A station groups products that share a prep area (e.g. Cold / Hot / Dessert / Bar)
-- and eventually a printer. Products are assigned to a station via products.station_id.

CREATE TABLE IF NOT EXISTS stations (
    id UUID PRIMARY KEY,
    tenant_id UUID NOT NULL,
    store_id UUID NULL REFERENCES stores(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color TEXT NOT NULL DEFAULT '#4f46e5',
    printer_id UUID NULL,                   -- FK wired after migration 012 (printers)
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stations_tenant ON stations(tenant_id) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_stations_store ON stations(store_id) WHERE is_deleted = FALSE;

-- Product → station mapping. Coexists with legacy products.printer_group (TEXT),
-- which stays for backward compatibility until clients migrate.
ALTER TABLE products ADD COLUMN IF NOT EXISTS station_id UUID NULL REFERENCES stations(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_products_station ON products(station_id) WHERE station_id IS NOT NULL;
