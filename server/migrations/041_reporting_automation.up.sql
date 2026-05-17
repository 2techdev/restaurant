-- ---------------------------------------------------------------------------
-- 041 — Reporting automation: scheduled email reports + threshold alerts.
--
-- Three concerns:
--   1. scheduled_reports — tenant-defined recurring email reports (daily
--      digest, weekly summary, monthly P&L, etc.). Cron driven, configurable
--      recipients / format / filters.
--   2. report_logs       — one row per send attempt. Status + error + count.
--   3. threshold_alerts  — tenant-defined business-metric thresholds
--      (e.g. "sales dropped 20% vs 7-day avg", "stock-outs > 5",
--      "online-order ACK delayed").
--   4. alert_logs        — one row per alert firing (or suppression).
--
-- Tenant scoping is application-layer via middleware.GetTenantID(); no RLS
-- (matches the rest of the schema). All tables are idempotent.
-- ---------------------------------------------------------------------------

-- ===========================================================================
-- 1. scheduled_reports — recurring email report definitions
-- ===========================================================================
CREATE TABLE IF NOT EXISTS scheduled_reports (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL,
    name                TEXT NOT NULL,
    report_type         TEXT NOT NULL,
        -- one of: daily_digest | sales_summary | hourly_sales |
        --         staff_performance | inventory_health | customer_activity
    schedule_cron       TEXT NOT NULL,
        -- 5-field cron (m h dom mon dow) in tenant timezone. Examples:
        --   "59 23 * * *"   → 23:59 every day  (daily digest)
        --   "0  9  * * 1"   → 09:00 every Monday  (weekly)
        --   "0  9  1 * *"   → 09:00 on the 1st   (monthly)
    recipients_emails   TEXT[] NOT NULL DEFAULT '{}',
    format              TEXT NOT NULL DEFAULT 'html',
        -- html | pdf | csv
    filters_jsonb       JSONB NOT NULL DEFAULT '{}'::jsonb,
        -- free-form filters: { "order_type": "all" | "dine_in" | "takeaway" |
        -- "delivery", "scope": "tenant" | "chain", … }
    locale              TEXT NOT NULL DEFAULT 'tr',
        -- language for the rendered email body (tr|de|en|fr|it)
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    last_sent_at        TIMESTAMPTZ,
    last_status         TEXT,
        -- success | failed | skipped
    next_run_at         TIMESTAMPTZ,
        -- pre-computed by scheduler so the every-minute tick can do an
        -- indexed `WHERE next_run_at <= now()` instead of parsing cron per row
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT scheduled_reports_format_check
        CHECK (format IN ('html', 'pdf', 'csv')),
    CONSTRAINT scheduled_reports_report_type_check
        CHECK (report_type IN (
            'daily_digest',
            'sales_summary',
            'hourly_sales',
            'staff_performance',
            'inventory_health',
            'customer_activity'
        )),
    CONSTRAINT scheduled_reports_locale_check
        CHECK (locale IN ('tr', 'de', 'en', 'fr', 'it'))
);

CREATE INDEX IF NOT EXISTS scheduled_reports_tenant_idx
    ON scheduled_reports (tenant_id);
CREATE INDEX IF NOT EXISTS scheduled_reports_due_idx
    ON scheduled_reports (next_run_at)
    WHERE is_active = TRUE;

-- ===========================================================================
-- 2. report_logs — one row per send attempt
-- ===========================================================================
CREATE TABLE IF NOT EXISTS report_logs (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scheduled_report_id      UUID
        REFERENCES scheduled_reports(id) ON DELETE SET NULL,
    tenant_id                UUID NOT NULL,
    report_type              TEXT NOT NULL,
    sent_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_to_emails           TEXT[] NOT NULL DEFAULT '{}',
    sent_recipients_count    INT NOT NULL DEFAULT 0,
    status                   TEXT NOT NULL,
        -- success | failed | skipped
    error_message            TEXT,
    duration_ms              INT,
    trigger_source           TEXT NOT NULL DEFAULT 'scheduler',
        -- scheduler | manual | digest_cron

    CONSTRAINT report_logs_status_check
        CHECK (status IN ('success', 'failed', 'skipped'))
);

CREATE INDEX IF NOT EXISTS report_logs_tenant_idx
    ON report_logs (tenant_id, sent_at DESC);
CREATE INDEX IF NOT EXISTS report_logs_schedule_idx
    ON report_logs (scheduled_report_id, sent_at DESC);

-- ===========================================================================
-- 3. threshold_alerts — business-metric threshold definitions
-- ===========================================================================
CREATE TABLE IF NOT EXISTS threshold_alerts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL,
    name                TEXT NOT NULL,
    alert_type          TEXT NOT NULL,
        -- sales_drop | stockout_count | online_ack_delay | revenue_target |
        -- refund_spike | failed_payments
    threshold_jsonb     JSONB NOT NULL DEFAULT '{}'::jsonb,
        -- per-type config. Examples:
        --   sales_drop:        { "percent": 20, "compare_to": "7d_avg" }
        --   stockout_count:    { "count": 5 }
        --   online_ack_delay:  { "minutes": 10 }
        --   revenue_target:    { "amount_cents": 100000 }
    recipients_emails   TEXT[] NOT NULL DEFAULT '{}',
    cooldown_minutes    INT NOT NULL DEFAULT 60,
        -- once fired, suppress re-firing for this many minutes
    locale              TEXT NOT NULL DEFAULT 'tr',
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    last_triggered_at   TIMESTAMPTZ,
    last_value          NUMERIC,
        -- the metric value at last firing (e.g. 18.5 percent, 7 items)
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT threshold_alerts_alert_type_check
        CHECK (alert_type IN (
            'sales_drop',
            'stockout_count',
            'online_ack_delay',
            'revenue_target',
            'refund_spike',
            'failed_payments'
        )),
    CONSTRAINT threshold_alerts_locale_check
        CHECK (locale IN ('tr', 'de', 'en', 'fr', 'it'))
);

CREATE INDEX IF NOT EXISTS threshold_alerts_tenant_idx
    ON threshold_alerts (tenant_id);
CREATE INDEX IF NOT EXISTS threshold_alerts_active_idx
    ON threshold_alerts (tenant_id, is_active)
    WHERE is_active = TRUE;

-- ===========================================================================
-- 4. alert_logs — one row per alert firing or suppressed evaluation
-- ===========================================================================
CREATE TABLE IF NOT EXISTS alert_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    alert_id            UUID
        REFERENCES threshold_alerts(id) ON DELETE SET NULL,
    tenant_id           UUID NOT NULL,
    triggered_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    value               NUMERIC,
    message             TEXT,
    sent_to             TEXT[] NOT NULL DEFAULT '{}',
    status              TEXT NOT NULL,
        -- fired | suppressed_cooldown | send_failed
    error_message       TEXT,

    CONSTRAINT alert_logs_status_check
        CHECK (status IN ('fired', 'suppressed_cooldown', 'send_failed'))
);

CREATE INDEX IF NOT EXISTS alert_logs_tenant_idx
    ON alert_logs (tenant_id, triggered_at DESC);
CREATE INDEX IF NOT EXISTS alert_logs_alert_idx
    ON alert_logs (alert_id, triggered_at DESC);
