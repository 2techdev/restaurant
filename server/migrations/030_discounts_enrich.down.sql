-- Rollback for 030 — drop every enrichment in reverse order.
-- Note: this restores the original 4-value CHECK; any existing rows with
-- type='HAPPY_HOUR' must be migrated to PERCENT / FIXED first or this
-- migration will fail on the constraint re-add.

DROP INDEX IF EXISTS idx_discounts_days_of_week;
DROP INDEX IF EXISTS idx_discounts_tenant_promo_code;

ALTER TABLE discounts
    DROP COLUMN IF EXISTS is_stackable,
    DROP COLUMN IF EXISTS promo_code,
    DROP COLUMN IF EXISTS used_count,
    DROP COLUMN IF EXISTS max_uses,
    DROP COLUMN IF EXISTS hours_to,
    DROP COLUMN IF EXISTS hours_from,
    DROP COLUMN IF EXISTS days_of_week,
    DROP COLUMN IF EXISTS description_translations,
    DROP COLUMN IF EXISTS description,
    DROP COLUMN IF EXISTS name_translations;

ALTER TABLE discounts DROP CONSTRAINT IF EXISTS discounts_type_check;
ALTER TABLE discounts
    ADD CONSTRAINT discounts_type_check
        CHECK (type IN ('PERCENT', 'FIXED', 'BOGO'));
