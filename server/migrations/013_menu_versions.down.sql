-- Migration 013 down: drop menu_versions and revert tenant columns.

DROP INDEX IF EXISTS idx_menu_versions_tenant_version;
DROP INDEX IF EXISTS idx_menu_versions_tenant_published;
DROP TABLE IF EXISTS menu_versions;

DROP INDEX IF EXISTS idx_tenants_pos_api_key;
ALTER TABLE tenants
    DROP COLUMN IF EXISTS menu_version_current,
    DROP COLUMN IF EXISTS pos_api_key;
