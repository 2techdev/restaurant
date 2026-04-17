-- cleanup_audit_user.sql
-- Removes the audit user `audit+owner@gastrocore.ch` created during the
-- 2026-04 external pilot audit, along with its refresh tokens. Safe to run
-- repeatedly — DELETEs are WHERE-filtered by email and cascade through
-- refresh_tokens by user_id.
--
-- Usage (from server/):
--   psql "$DATABASE_URL" -f scripts/cleanup_audit_user.sql
--
-- Verify first (dry run):
--   SELECT id, email, role, organization_id, is_active
--   FROM admin_users WHERE email = 'audit+owner@gastrocore.ch';

BEGIN;

-- 1) Capture IDs we're about to delete (for logging).
DO $$
DECLARE
    admin_id UUID;
    app_id   UUID;
BEGIN
    SELECT id INTO admin_id FROM admin_users WHERE email = 'audit+owner@gastrocore.ch';
    SELECT id INTO app_id   FROM app_users   WHERE email = 'audit+owner@gastrocore.ch';

    IF admin_id IS NOT NULL THEN
        RAISE NOTICE 'Removing admin_user %', admin_id;
    END IF;
    IF app_id IS NOT NULL THEN
        RAISE NOTICE 'Removing app_user %', app_id;
    END IF;
END $$;

-- 2) Revoke refresh tokens first (no FK cascade guarantee).
DELETE FROM refresh_tokens
WHERE user_id IN (
    SELECT id FROM admin_users WHERE email = 'audit+owner@gastrocore.ch'
    UNION
    SELECT id FROM app_users   WHERE email = 'audit+owner@gastrocore.ch'
);

-- 3) Delete from both user tables (audit may have lived in either).
DELETE FROM admin_users WHERE email = 'audit+owner@gastrocore.ch';
DELETE FROM app_users   WHERE email = 'audit+owner@gastrocore.ch';

COMMIT;

-- 4) Verification
SELECT 'admin_users remaining' AS table_name, COUNT(*) AS n
FROM admin_users WHERE email = 'audit+owner@gastrocore.ch'
UNION ALL
SELECT 'app_users remaining', COUNT(*)
FROM app_users WHERE email = 'audit+owner@gastrocore.ch';
