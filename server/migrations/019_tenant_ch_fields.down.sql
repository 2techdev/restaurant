DROP INDEX IF EXISTS idx_tenants_uid;

ALTER TABLE tenants
    DROP COLUMN IF EXISTS default_language,
    DROP COLUMN IF EXISTS website,
    DROP COLUMN IF EXISTS iban,
    DROP COLUMN IF EXISTS uid_nummer;
