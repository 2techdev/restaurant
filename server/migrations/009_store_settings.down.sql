-- Migration 009 rollback
ALTER TABLE stores
    DROP COLUMN IF EXISTS service_charge_enabled,
    DROP COLUMN IF EXISTS service_charge_percent,
    DROP COLUMN IF EXISTS language,
    DROP COLUMN IF EXISTS gangs_enabled,
    DROP COLUMN IF EXISTS max_gangs,
    DROP COLUMN IF EXISTS gang_labels;
