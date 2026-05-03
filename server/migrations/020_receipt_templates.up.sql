-- Receipt templates — Swiss MWST-compliant printable receipt layouts
-- Variables resolved at print time by server (preview) and POS (real print).
--
-- Supported variables:
--   {{tenant_name}} {{tenant_address}} {{tenant_phone}} {{tenant_uid}}
--   {{tenant_iban}} {{tenant_website}}
--   {{order_no}} {{date_ch}} {{time_ch}} {{table_or_takeaway}} {{cashier_name}}
--   {{customer_name}} {{items_ch}}
--   {{subtotal}} {{subtotal_net}} {{discount}} {{tip}}
--   {{vat_8_1_amount}} {{vat_2_6_amount}} {{vat_3_8_amount}}
--   {{vat_breakdown}} (rendered convenience block)
--   {{total}} {{rounded_total}} {{rounding_diff}}
--   {{payment_method}}
--   {{fiskaly_signature}} {{tsr_serial}}
--   {{discount_line_if_any}} {{rounding_line_if_cash}} {{rounded_total_line_if_cash}}
--   {{twint_qr_if_tip}}

CREATE TABLE IF NOT EXISTS receipt_templates (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    language    TEXT NOT NULL DEFAULT 'de'
                CHECK (language IN ('de', 'fr', 'it', 'en', 'tr')),
    width_mm    INT NOT NULL DEFAULT 80
                CHECK (width_mm IN (58, 80)),
    is_default  BOOLEAN NOT NULL DEFAULT FALSE,
    header      TEXT,
    body_format TEXT NOT NULL,
    footer      TEXT,
    paper_cut   BOOLEAN NOT NULL DEFAULT TRUE,
    open_drawer BOOLEAN NOT NULL DEFAULT FALSE,
    copies      INT NOT NULL DEFAULT 1 CHECK (copies BETWEEN 1 AND 5),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, name)
);

CREATE INDEX IF NOT EXISTS idx_receipt_templates_tenant
    ON receipt_templates(tenant_id);

-- Only one default per (tenant, language) — ensures sane lookup
CREATE UNIQUE INDEX IF NOT EXISTS uq_receipt_templates_default_per_lang
    ON receipt_templates(tenant_id, language)
    WHERE is_default = TRUE;

-- ===========================================================
-- Default Swiss DE template seed for every tenant (multi-line)
-- ===========================================================
INSERT INTO receipt_templates (
    tenant_id, name, language, width_mm, is_default,
    header, body_format, footer
)
SELECT
    t.id,
    'Standard CH (DE)',
    'de',
    80,
    TRUE,
    -- header
    E'{{tenant_name}}\n{{tenant_address}}\nUID: {{tenant_uid}}\n{{tenant_phone}}\n================================',
    -- body_format
    E'Beleg Nr: {{order_no}}\n{{date_ch}} {{time_ch}}\nTisch: {{table_or_takeaway}}\nMitarbeiter: {{cashier_name}}\n================================\n{{items_ch}}\n================================\nZwischensumme:    {{subtotal}}\n{{discount_line_if_any}}--------------------------------\n{{vat_breakdown}}================================\nTOTAL:            CHF {{total}}\n{{rounding_line_if_cash}}{{rounded_total_line_if_cash}}================================\nZahlungsart: {{payment_method}}',
    -- footer
    E'\nVielen Dank für Ihren Besuch!\n{{tenant_iban}}\n{{tenant_website}}\n\n{{twint_qr_if_tip}}\n================================'
FROM tenants t
ON CONFLICT (tenant_id, name) DO NOTHING;
