-- ---------------------------------------------------------------------------
-- 038 — Customer Behavior Segmentation / Guest Book.
--
-- Brings the customers table up to Lightspeed Guest Book parity:
--   * Lifecycle dates: first_visit_at + anniversary (last_visit_at already exists).
--   * Roll-up aggregates: avg_ticket_cents, favorite_category_id, favorite_product_id,
--     preferred_hour_bucket (0–23), preferred_payment_method.
--   * Free-form classification: tags[], allergens[], dietary_tags[].
--
-- New tables:
--   * customer_segments         — saved filter definitions (dynamic by default).
--   * marketing_campaigns       — email/sms/push campaigns linked to a segment.
--                                 Kept separate from the existing `campaigns`
--                                 table, which is the promotional / discount
--                                 schedule (campaigns_discount_id_fkey).
--   * marketing_campaign_recipients — per-customer send + open + click + convert
--                                 attribution rows.
--
-- All new columns are nullable / defaulted; idempotent (IF NOT EXISTS).
-- ---------------------------------------------------------------------------

-- 1. Customers — extended profile columns.
ALTER TABLE customers
    ADD COLUMN IF NOT EXISTS anniversary              DATE,
    ADD COLUMN IF NOT EXISTS first_visit_at           TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS tags                     TEXT[] NOT NULL DEFAULT '{}'::text[],
    ADD COLUMN IF NOT EXISTS allergens                TEXT[] NOT NULL DEFAULT '{}'::text[],
    ADD COLUMN IF NOT EXISTS dietary_tags             TEXT[] NOT NULL DEFAULT '{}'::text[],
    ADD COLUMN IF NOT EXISTS preferred_payment_method TEXT,
    ADD COLUMN IF NOT EXISTS preferred_hour_bucket    INT CHECK (preferred_hour_bucket IS NULL OR (preferred_hour_bucket BETWEEN 0 AND 23)),
    ADD COLUMN IF NOT EXISTS favorite_category_id     TEXT,
    ADD COLUMN IF NOT EXISTS favorite_product_id      TEXT,
    ADD COLUMN IF NOT EXISTS avg_ticket_cents         BIGINT NOT NULL DEFAULT 0;

-- GIN index for tag-based segment lookups
-- (`WHERE tags @> ARRAY['VIP']` or `tags && ARRAY['VIP','Vegan']`).
CREATE INDEX IF NOT EXISTS idx_customers_tags
    ON customers USING GIN (tags)
    WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_customers_dietary_tags
    ON customers USING GIN (dietary_tags)
    WHERE is_deleted = false;

-- Composite on last_visit + total_spend so the "haven't returned in 30 days"
-- and "top spenders" filters don't sequential-scan as the table grows.
CREATE INDEX IF NOT EXISTS idx_customers_last_visit
    ON customers (tenant_id, last_visit_at DESC NULLS LAST)
    WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_customers_total_spend
    ON customers (tenant_id, total_spent_cents DESC)
    WHERE is_deleted = false;

-- 2. customer_segments — saved filter definitions.
CREATE TABLE IF NOT EXISTS customer_segments (
    id           TEXT PRIMARY KEY,
    tenant_id    TEXT NOT NULL,
    name         TEXT NOT NULL,
    description  TEXT,
    -- definition: { combinator: "AND" | "OR", filters: [...] }
    -- Supported filter types (matched in Go):
    --   last_visit_before_days, last_visit_after_days,
    --   total_visits_min, total_visits_max, total_visits_eq,
    --   total_spend_min_cents, total_spend_max_cents,
    --   has_tag, has_allergen, has_dietary_tag,
    --   birthday_in_days, anniversary_in_days,
    --   first_visit_before_days,
    --   preferred_hour_bucket_in, preferred_payment_method
    definition   JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_dynamic   BOOLEAN NOT NULL DEFAULT true,
    created_by   TEXT,
    created_at   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    is_deleted   BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_customer_segments_tenant
    ON customer_segments (tenant_id)
    WHERE is_deleted = false;

-- 3. marketing_campaigns — email / sms / push, segment-targeted.
--    Distinct from the existing public.campaigns table (which is the
--    promotion-schedule binding to discounts via campaigns.discount_id).
CREATE TABLE IF NOT EXISTS marketing_campaigns (
    id              TEXT PRIMARY KEY,
    tenant_id       TEXT NOT NULL,
    segment_id      TEXT REFERENCES customer_segments(id),
    name            TEXT NOT NULL,
    channel         TEXT NOT NULL DEFAULT 'email'
        CHECK (channel IN ('email', 'sms', 'push')),
    subject         TEXT,
    body_html       TEXT,
    body_text       TEXT,
    -- template_key: 'welcome' | 'birthday' | 're_engagement' | 'loyalty_milestone' | 'custom'
    template_key    TEXT,
    scheduled_at    TIMESTAMP WITH TIME ZONE,
    sent_at         TIMESTAMP WITH TIME ZONE,
    status          TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'scheduled', 'sending', 'sent', 'failed', 'cancelled')),
    sent_count      INT NOT NULL DEFAULT 0,
    opened_count    INT NOT NULL DEFAULT 0,
    clicked_count   INT NOT NULL DEFAULT 0,
    converted_count INT NOT NULL DEFAULT 0,
    created_by      TEXT,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_marketing_campaigns_tenant_status
    ON marketing_campaigns (tenant_id, status)
    WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_marketing_campaigns_scheduled
    ON marketing_campaigns (scheduled_at)
    WHERE status = 'scheduled' AND is_deleted = false;

-- 4. marketing_campaign_recipients — per-customer attribution log.
CREATE TABLE IF NOT EXISTS marketing_campaign_recipients (
    id                  TEXT PRIMARY KEY,
    campaign_id         TEXT NOT NULL REFERENCES marketing_campaigns(id),
    customer_id         TEXT NOT NULL REFERENCES customers(id),
    tenant_id           TEXT NOT NULL,
    sent_at             TIMESTAMP WITH TIME ZONE,
    opened_at           TIMESTAMP WITH TIME ZONE,
    clicked_at          TIMESTAMP WITH TIME ZONE,
    converted_order_id  TEXT,
    error               TEXT,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_recipient_unique
    ON marketing_campaign_recipients (campaign_id, customer_id);

CREATE INDEX IF NOT EXISTS idx_recipients_customer
    ON marketing_campaign_recipients (customer_id, sent_at DESC);

CREATE INDEX IF NOT EXISTS idx_recipients_tenant
    ON marketing_campaign_recipients (tenant_id, sent_at DESC);
