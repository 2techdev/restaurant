-- Reverse migration: drop multi-store tables in dependency order.

-- Remove columns added to tenants
ALTER TABLE tenants DROP COLUMN IF EXISTS store_id;
ALTER TABLE tenants DROP COLUMN IF EXISTS organization_id;

-- Drop triggers
DROP TRIGGER IF EXISTS trg_employees_updated_at ON employees;
DROP TRIGGER IF EXISTS trg_admin_users_updated_at ON admin_users;
DROP TRIGGER IF EXISTS trg_stores_updated_at ON stores;
DROP TRIGGER IF EXISTS trg_brands_updated_at ON brands;
DROP TRIGGER IF EXISTS trg_organizations_updated_at ON organizations;

-- Drop indexes
DROP INDEX IF EXISTS idx_employees_org;
DROP INDEX IF EXISTS idx_employees_store;
DROP INDEX IF EXISTS idx_admin_users_email;
DROP INDEX IF EXISTS idx_admin_users_org;
DROP INDEX IF EXISTS idx_stores_status;
DROP INDEX IF EXISTS idx_stores_code;
DROP INDEX IF EXISTS idx_stores_org;
DROP INDEX IF EXISTS idx_stores_brand;
DROP INDEX IF EXISTS idx_brands_org;

-- Drop tables in reverse dependency order
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS admin_users;
DROP TABLE IF EXISTS stores;
DROP TABLE IF EXISTS brands;
DROP TABLE IF EXISTS organizations;
