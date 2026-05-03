-- Swiss-specific tenant fields for compliant receipt printing
-- UID-Nummer (CHE-XXX.XXX.XXX MWST format), IBAN, website, default_language

ALTER TABLE tenants
    ADD COLUMN IF NOT EXISTS uid_nummer       TEXT,
    ADD COLUMN IF NOT EXISTS iban             TEXT,
    ADD COLUMN IF NOT EXISTS website          TEXT,
    ADD COLUMN IF NOT EXISTS default_language TEXT NOT NULL DEFAULT 'de';

CREATE INDEX IF NOT EXISTS idx_tenants_uid ON tenants(uid_nummer)
    WHERE uid_nummer IS NOT NULL;
