-- Migration 016 (down): drop feedback, promotions, suppliers, prefs.

DROP INDEX IF EXISTS idx_inventory_items_supplier;
ALTER TABLE inventory_items DROP COLUMN IF EXISTS supplier_id;

DROP TABLE IF EXISTS notification_preferences;
DROP TABLE IF EXISTS campaigns;
DROP TABLE IF EXISTS discounts;
DROP TABLE IF EXISTS suppliers;
DROP TABLE IF EXISTS feedback;
