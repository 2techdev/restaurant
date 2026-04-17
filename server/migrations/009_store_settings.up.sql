-- Migration 009: per-store settings for backoffice Settings page
-- Adds service charge toggle, service charge percent, and language preference.

ALTER TABLE stores
    ADD COLUMN IF NOT EXISTS service_charge_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS service_charge_percent NUMERIC(5,2) NOT NULL DEFAULT 10.00
        CHECK (service_charge_percent >= 0 AND service_charge_percent <= 100),
    ADD COLUMN IF NOT EXISTS language TEXT NOT NULL DEFAULT 'tr';
