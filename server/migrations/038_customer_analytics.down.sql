-- Down migration for 038 — Customer Behavior Segmentation / Guest Book.

DROP INDEX IF EXISTS idx_recipients_tenant;
DROP INDEX IF EXISTS idx_recipients_customer;
DROP INDEX IF EXISTS idx_recipient_unique;
DROP TABLE IF EXISTS marketing_campaign_recipients;

DROP INDEX IF EXISTS idx_marketing_campaigns_scheduled;
DROP INDEX IF EXISTS idx_marketing_campaigns_tenant_status;
DROP TABLE IF EXISTS marketing_campaigns;

DROP INDEX IF EXISTS idx_customer_segments_tenant;
DROP TABLE IF EXISTS customer_segments;

DROP INDEX IF EXISTS idx_customers_total_spend;
DROP INDEX IF EXISTS idx_customers_last_visit;
DROP INDEX IF EXISTS idx_customers_dietary_tags;
DROP INDEX IF EXISTS idx_customers_tags;

ALTER TABLE customers
    DROP COLUMN IF EXISTS avg_ticket_cents,
    DROP COLUMN IF EXISTS favorite_product_id,
    DROP COLUMN IF EXISTS favorite_category_id,
    DROP COLUMN IF EXISTS preferred_hour_bucket,
    DROP COLUMN IF EXISTS preferred_payment_method,
    DROP COLUMN IF EXISTS dietary_tags,
    DROP COLUMN IF EXISTS allergens,
    DROP COLUMN IF EXISTS tags,
    DROP COLUMN IF EXISTS first_visit_at,
    DROP COLUMN IF EXISTS anniversary;
