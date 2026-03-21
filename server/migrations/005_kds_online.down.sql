-- Migration 005 down: remove kds_online additions

DROP INDEX IF EXISTS idx_order_items_kds_status;
DROP INDEX IF EXISTS idx_devices_token;

ALTER TABLE order_items    DROP COLUMN IF EXISTS kds_status;
ALTER TABLE tenants        DROP COLUMN IF EXISTS description,
                           DROP COLUMN IF EXISTS logo_url,
                           DROP COLUMN IF EXISTS cover_image_url,
                           DROP COLUMN IF EXISTS is_open,
                           DROP COLUMN IF EXISTS is_deleted;
ALTER TABLE products       DROP COLUMN IF EXISTS stock_status,
                           DROP COLUMN IF EXISTS prep_time_minutes;
ALTER TABLE devices        DROP COLUMN IF EXISTS device_token;
