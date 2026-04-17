-- Migration 009 rollback
ALTER TABLE stores
    DROP COLUMN IF EXISTS service_charge_enabled,
    DROP COLUMN IF EXISTS service_charge_percent,
    DROP COLUMN IF EXISTS language;
