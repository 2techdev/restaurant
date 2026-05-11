-- ---------------------------------------------------------------------------
-- 030 — Enrich discounts: HAPPY_HOUR type + multi-language labels +
--       day-of-week / hour-of-day windows + promo codes + usage caps +
--       stackability flag.
--
-- Brings the table up to the operator-facing brief that the existing
-- happy-hour UI (apps/backoffice/.../promotions/happy-hour/) needs to wire
-- against a real backend. Until now that page wrote to localStorage only;
-- after this migration the same /api/v1/discounts surface backs every
-- promotion type, with HAPPY_HOUR distinguished by `type='HAPPY_HOUR'`
-- plus the day-of-week + hours columns added below.
--
-- All new columns are nullable / defaulted so existing rows stay intact.
-- Idempotent — each ALTER guards with IF NOT EXISTS.
-- ---------------------------------------------------------------------------

-- 1. Allow HAPPY_HOUR as a discount type. Postgres CHECK constraints can't
-- be ALTERed in place; drop and re-create.
ALTER TABLE discounts DROP CONSTRAINT IF EXISTS discounts_type_check;
ALTER TABLE discounts
    ADD CONSTRAINT discounts_type_check
        CHECK (type IN ('PERCENT', 'FIXED', 'BOGO', 'HAPPY_HOUR'));

-- 2. Multi-language label JSON blobs. Default {} so the existing `name`
-- column stays the source of truth until the operator fills translations.
ALTER TABLE discounts
    ADD COLUMN IF NOT EXISTS name_translations        JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS description              TEXT,
    ADD COLUMN IF NOT EXISTS description_translations JSONB NOT NULL DEFAULT '{}'::jsonb;

-- 3. Day-of-week window — array of int (0=Sunday … 6=Saturday). Default
-- "every day" so legacy rows behave as before.
ALTER TABLE discounts
    ADD COLUMN IF NOT EXISTS days_of_week INT[] NOT NULL DEFAULT '{0,1,2,3,4,5,6}'::int[];

-- 4. Hour-of-day window — for happy hour and time-bound campaigns.
-- Stored as TIME WITHOUT TIME ZONE; restaurant-local clock.
ALTER TABLE discounts
    ADD COLUMN IF NOT EXISTS hours_from TIME,
    ADD COLUMN IF NOT EXISTS hours_to   TIME;

-- 5. Per-promotion usage cap. NULL = unlimited.
ALTER TABLE discounts
    ADD COLUMN IF NOT EXISTS max_uses   INT,
    ADD COLUMN IF NOT EXISTS used_count INT NOT NULL DEFAULT 0;

-- 6. Promo code — optional. When set, the discount only fires when the
-- cashier types the code at checkout. Tenant-scoped uniqueness so two
-- promos can't share a code within one restaurant. Partial unique index
-- so NULL codes (which we expect on the majority of rows) coexist freely.
ALTER TABLE discounts
    ADD COLUMN IF NOT EXISTS promo_code TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_discounts_tenant_promo_code
    ON discounts(tenant_id, promo_code)
    WHERE promo_code IS NOT NULL AND is_deleted = false;

-- 7. Stackability — when true the discount can stack on top of other
-- discounts. Default false matches the conservative interpretation: only
-- one promotion per ticket unless the operator opts in.
ALTER TABLE discounts
    ADD COLUMN IF NOT EXISTS is_stackable BOOLEAN NOT NULL DEFAULT false;

-- 8. Companion index for the happy-hour query path. The active-promotions
-- endpoint filters discounts by (tenant_id, active, days_of_week, hours).
-- GIN on days_of_week lets the runtime check `WHERE ARRAY[dow] && days_of_week`
-- without a full table scan once the catalog grows past a handful of rows.
CREATE INDEX IF NOT EXISTS idx_discounts_days_of_week
    ON discounts USING GIN (days_of_week)
    WHERE is_deleted = false;
