ALTER TABLE categories
    DROP COLUMN IF EXISTS name_translations;

ALTER TABLE products
    DROP COLUMN IF EXISTS description_translations,
    DROP COLUMN IF EXISTS name_translations;

ALTER TABLE tenants
    DROP COLUMN IF EXISTS primary_language;
