-- Migration 006: German tax rates and fiscal configuration
--
-- Adds support for German MwSt rates (19% / 7%) and the Fiskaly TSE
-- configuration required by KassenSichV (§146a AO).
--
-- This migration is additive and does not affect existing Swiss MWST data.

-- ---------------------------------------------------------------------------
-- German tax rates
-- ---------------------------------------------------------------------------

-- Insert German MwSt rates into tax_rates (if the table exists from migration 004).
-- The 'country_code' column discriminates between CH and DE profiles.
ALTER TABLE tax_profiles ADD COLUMN IF NOT EXISTS country_code VARCHAR(2) NOT NULL DEFAULT 'CH';
ALTER TABLE tax_profiles ADD COLUMN IF NOT EXISTS requires_tse BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE tax_profiles ADD COLUMN IF NOT EXISTS currency VARCHAR(3) NOT NULL DEFAULT 'CHF';

-- German standard profile
INSERT INTO tax_profiles (
    id,
    name,
    country_code,
    currency,
    requires_tse,
    is_tax_inclusive,
    rounding_mode,
    created_at,
    updated_at
)
SELECT
    gen_random_uuid(),
    'German MwSt',
    'DE',
    'EUR',
    TRUE,
    TRUE,
    'none',
    NOW(),
    NOW()
WHERE NOT EXISTS (
    SELECT 1 FROM tax_profiles WHERE country_code = 'DE'
);

-- ---------------------------------------------------------------------------
-- Fiskaly TSE configuration table
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS fiscal_tse_config (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL,
    tse_id          UUID,                              -- Fiskaly TSE UUID
    client_id       UUID,                              -- POS client UUID
    tse_state       VARCHAR(20) NOT NULL DEFAULT 'UNKNOWN',
    tse_serial_number VARCHAR(128),
    signature_algorithm VARCHAR(64),
    signature_counter   BIGINT NOT NULL DEFAULT 0,
    fiskaly_env     VARCHAR(20) NOT NULL DEFAULT 'test',
    last_self_test_at TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fiscal_tse_config_tenant
    ON fiscal_tse_config(tenant_id);

-- ---------------------------------------------------------------------------
-- Transaction signature log (audit trail for every signed receipt)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS fiscal_signatures (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL,
    receipt_id          VARCHAR(64) NOT NULL,
    transaction_id      VARCHAR(64) NOT NULL,   -- Fiskaly tx UUID
    transaction_number  BIGINT NOT NULL,
    signature_counter   BIGINT NOT NULL,
    start_time          TIMESTAMPTZ NOT NULL,
    end_time            TIMESTAMPTZ NOT NULL,
    signature_value     TEXT NOT NULL,          -- Base64 signature
    tse_serial_number   VARCHAR(128) NOT NULL,
    algorithm           VARCHAR(64) NOT NULL,
    public_key          TEXT NOT NULL,
    process_type        VARCHAR(64) NOT NULL DEFAULT 'Kassenbeleg-V1',
    process_data        TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fiscal_signatures_tenant
    ON fiscal_signatures(tenant_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_signatures_receipt
    ON fiscal_signatures(receipt_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_signatures_created_at
    ON fiscal_signatures(created_at);
