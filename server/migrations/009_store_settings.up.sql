-- Migration 009: per-store settings for backoffice Settings page
-- Adds service charge toggle, service charge percent, language preference,
-- and parametric Gang/Kurs configuration (gangs_enabled, max_gangs, gang_labels).

ALTER TABLE stores
    ADD COLUMN IF NOT EXISTS service_charge_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS service_charge_percent NUMERIC(5,2) NOT NULL DEFAULT 10.00
        CHECK (service_charge_percent >= 0 AND service_charge_percent <= 100),
    ADD COLUMN IF NOT EXISTS language TEXT NOT NULL DEFAULT 'tr',
    ADD COLUMN IF NOT EXISTS gangs_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS max_gangs INTEGER NOT NULL DEFAULT 3
        CHECK (max_gangs BETWEEN 1 AND 5),
    ADD COLUMN IF NOT EXISTS gang_labels JSONB NOT NULL
        DEFAULT '["Gang 1","Gang 2","Gang 3"]'::jsonb;
