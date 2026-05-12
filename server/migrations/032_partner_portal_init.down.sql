-- Rollback migration 032 — partner portal init.
-- Drops new tables and partner-portal columns. The vestigial brands/stores/
-- employees tables and the duplicate organization row are NOT restored —
-- those were destructive cleanups and rolling back would re-introduce
-- inconsistent state.

BEGIN;

ALTER TABLE tenants       DROP COLUMN IF EXISTS current_edition_id;
ALTER TABLE tenants       DROP COLUMN IF EXISTS store_code;
ALTER TABLE tenants       DROP COLUMN IF EXISTS dealer_id;
ALTER TABLE organizations DROP COLUMN IF EXISTS deleted_at;
ALTER TABLE organizations DROP COLUMN IF EXISTS dealer_id;

DROP TABLE IF EXISTS billing_invoices       CASCADE;
DROP TABLE IF EXISTS store_feature_flags    CASCADE;
DROP TABLE IF EXISTS store_app_assignments  CASCADE;
DROP TABLE IF EXISTS app_versions           CASCADE;
DROP TABLE IF EXISTS edition_assignments    CASCADE;
DROP TABLE IF EXISTS account_pools          CASCADE;
DROP TABLE IF EXISTS editions               CASCADE;
DROP TABLE IF EXISTS dealers                CASCADE;
DROP TABLE IF EXISTS partner_employees      CASCADE;

COMMIT;
