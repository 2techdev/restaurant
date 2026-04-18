-- Tables: floor plan support for the backoffice /tables page.
-- * Adds a free-text `zone` label (bar, main hall, terrace …) so the
--   backoffice can group tables without requiring a floors row.
-- * Makes `floor_id` nullable so tables can be created before any floor
--   has been provisioned for the tenant.

ALTER TABLE restaurant_tables
    ADD COLUMN IF NOT EXISTS zone TEXT;

ALTER TABLE restaurant_tables
    ALTER COLUMN floor_id DROP NOT NULL;
