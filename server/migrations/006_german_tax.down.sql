-- Rollback migration 006: German tax rates and fiscal configuration

DROP TABLE IF EXISTS fiscal_signatures;
DROP TABLE IF EXISTS fiscal_tse_config;

DELETE FROM tax_profiles WHERE country_code = 'DE';

ALTER TABLE tax_profiles DROP COLUMN IF EXISTS requires_tse;
ALTER TABLE tax_profiles DROP COLUMN IF EXISTS currency;
ALTER TABLE tax_profiles DROP COLUMN IF EXISTS country_code;
