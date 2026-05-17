-- Down 024: drop impersonation_sessions + is_super_admin column
DROP INDEX IF EXISTS idx_impersonation_active;
DROP INDEX IF EXISTS idx_impersonation_tenant;
DROP INDEX IF EXISTS idx_impersonation_super_admin;
DROP TABLE IF EXISTS impersonation_sessions;

ALTER TABLE admin_users
    DROP COLUMN IF EXISTS is_super_admin;
