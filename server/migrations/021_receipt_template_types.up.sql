-- Receipt template types — kitchen_ticket / customer_receipt / z_report
-- Each type can have its own default per language, so the partial unique
-- index is widened to include template_type.

ALTER TABLE receipt_templates
    ADD COLUMN IF NOT EXISTS template_type TEXT NOT NULL DEFAULT 'customer_receipt'
    CHECK (template_type IN ('kitchen_ticket', 'customer_receipt', 'z_report'));

-- Backfill (existing rows already get the default; this is belt-and-braces).
UPDATE receipt_templates
   SET template_type = 'customer_receipt'
 WHERE template_type IS NULL OR template_type = '';

-- Replace the (tenant, language) partial unique index with one that includes
-- template_type so a tenant can have one default per (language, type).
DROP INDEX IF EXISTS uq_receipt_templates_default_per_lang;
CREATE UNIQUE INDEX IF NOT EXISTS uq_receipt_templates_default_per_lang_type
    ON receipt_templates(tenant_id, language, template_type)
    WHERE is_default = TRUE;

-- ===========================================================
-- Seed: Standart Mutfak Fişi (kitchen ticket) per tenant
-- ===========================================================
INSERT INTO receipt_templates (
    tenant_id, name, template_type, language, width_mm, is_default,
    header, body_format, footer
)
SELECT
    t.id,
    'Standart Mutfak Fisi',
    'kitchen_ticket',
    COALESCE(t.default_language, 'de'),
    80,
    TRUE,
    E'*** KUECHE / MUTFAK ***\nBeleg: {{order_no}}\n{{date_ch}} {{time_ch}}\nTisch: {{table_or_takeaway}}\nMitarbeiter: {{cashier_name}}\n--------------------------------',
    E'{{items_kitchen}}\n--------------------------------',
    E''
FROM tenants t
ON CONFLICT (tenant_id, name) DO NOTHING;

-- ===========================================================
-- Seed: Standart Z-Rapor (Z-report) per tenant
-- ===========================================================
INSERT INTO receipt_templates (
    tenant_id, name, template_type, language, width_mm, is_default,
    header, body_format, footer
)
SELECT
    t.id,
    'Standart Z-Rapor',
    'z_report',
    COALESCE(t.default_language, 'de'),
    80,
    TRUE,
    E'==== Z-RAPOR ====\n{{tenant_name}}\n{{date_ch}} {{time_ch}}\n--------------------------------',
    E'Toplam Ciro:      {{total_revenue}}\nSiparis Sayisi:   {{order_count}}\nOrt. Siparis:     {{avg_order}}\n--------------------------------\nMWST 8.1%:        {{vat_8_1_amount}}\nMWST 2.6%:        {{vat_2_6_amount}}\nMWST 3.8%:        {{vat_3_8_amount}}\n--------------------------------\nNakit:            {{cash_total}}\nKarte:            {{card_total}}\nTWINT:            {{twint_total}}',
    E'================================'
FROM tenants t
ON CONFLICT (tenant_id, name) DO NOTHING;
