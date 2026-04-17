ALTER TABLE restaurant_tables DROP COLUMN IF EXISTS zone;
-- NOTE: not restoring floor_id NOT NULL to avoid failing on NULL rows.
