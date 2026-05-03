-- Revert: drop the typed unique index, restore the (tenant, language) one,
-- delete kitchen + z-report rows, drop the column.

DROP INDEX IF EXISTS uq_receipt_templates_default_per_lang_type;

CREATE UNIQUE INDEX IF NOT EXISTS uq_receipt_templates_default_per_lang
    ON receipt_templates(tenant_id, language)
    WHERE is_default = TRUE;

DELETE FROM receipt_templates
 WHERE template_type IN ('kitchen_ticket', 'z_report');

ALTER TABLE receipt_templates DROP COLUMN IF EXISTS template_type;
