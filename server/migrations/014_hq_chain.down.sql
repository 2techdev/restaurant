-- 014_hq_chain.down.sql

DROP TRIGGER IF EXISTS trg_menu_policies_updated_at ON menu_policies;

-- Per-tenant menu versions table is shared with the menu-sync task.
-- We only drop columns added by THIS migration and leave the table to its owner.
ALTER TABLE menu_versions DROP COLUMN IF EXISTS organization_id;
ALTER TABLE menu_versions DROP COLUMN IF EXISTS master_version;
-- (source column kept; harmless if other code paths use it)

DROP INDEX IF EXISTS idx_users_organization;
ALTER TABLE users DROP COLUMN IF EXISTS org_role;
ALTER TABLE users DROP COLUMN IF EXISTS organization_id;

DROP TABLE IF EXISTS master_menu_versions;
DROP TABLE IF EXISTS master_menus;
DROP TABLE IF EXISTS menu_policies;
DROP TABLE IF EXISTS organization_memberships;

ALTER TABLE organizations DROP COLUMN IF EXISTS settings_json;
ALTER TABLE organizations DROP COLUMN IF EXISTS owner_user_id;
