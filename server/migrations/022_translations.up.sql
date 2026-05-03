-- Multi-language menu support — primary_language on tenants, JSONB
-- name_translations / description_translations on products + categories.
--
-- Backoffice writes the primary-language string to `name`/`description` and
-- the rest into the JSONB map. POS chooses display string by matching the
-- session locale; falls back to primary_language, then `name`/`description`.

ALTER TABLE tenants
    ADD COLUMN IF NOT EXISTS primary_language TEXT DEFAULT 'tr'
    CHECK (primary_language IN ('tr', 'de', 'en', 'fr', 'it'));

ALTER TABLE products
    ADD COLUMN IF NOT EXISTS name_translations JSONB DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS description_translations JSONB DEFAULT '{}'::jsonb;

ALTER TABLE categories
    ADD COLUMN IF NOT EXISTS name_translations JSONB DEFAULT '{}'::jsonb;
