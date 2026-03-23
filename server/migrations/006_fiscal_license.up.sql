-- GastroCore Migration 006: Fiscal signing, licensing, LAN sync, dashboard cache
-- Adds tables required by:
--   • German KassenSichV (TSE fiscal signing)
--   • Ed25519 license token management
--   • LAN peer-to-peer synchronisation
--   • Dashboard statistics cache

-- ============================================================
-- FISCAL TSE CONFIGURATION
-- One row per tenant / TSE device pair.
-- ============================================================
CREATE TABLE fiscal_tse_config (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    tse_serial_number   TEXT NOT NULL,
    tse_public_key      TEXT NOT NULL,          -- PEM or Base64-encoded public key
    signature_algorithm TEXT NOT NULL DEFAULT 'ecdsa-plain-SHA384',
    certificate_pem     TEXT,                   -- Full TSE certificate chain
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    activated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deactivated_at      TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_fiscal_tse_config_tenant ON fiscal_tse_config(tenant_id);
CREATE UNIQUE INDEX idx_fiscal_tse_config_active
    ON fiscal_tse_config(tenant_id) WHERE is_active = TRUE;

CREATE TRIGGER trg_fiscal_tse_config_updated_at
    BEFORE UPDATE ON fiscal_tse_config
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- FISCAL SIGNATURES
-- One row per signed receipt (DSFinV-K compliant).
-- ============================================================
CREATE TABLE fiscal_signatures (
    id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id            UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    receipt_id           UUID NOT NULL,         -- references receipts(id) — no FK to allow soft-delete
    tse_serial_number    TEXT NOT NULL,
    transaction_number   BIGINT NOT NULL,
    signature_algorithm  TEXT NOT NULL,
    signature_value      TEXT NOT NULL,         -- Base64-encoded TSE signature
    process_type         TEXT NOT NULL DEFAULT 'Kassenbeleg-V1',
    process_data         TEXT NOT NULL,         -- Signed data string per DSFinV-K spec
    tse_timestamp        TIMESTAMPTZ NOT NULL,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_fiscal_signatures_tenant ON fiscal_signatures(tenant_id);
CREATE INDEX idx_fiscal_signatures_receipt ON fiscal_signatures(receipt_id);
CREATE INDEX idx_fiscal_signatures_tse_serial
    ON fiscal_signatures(tse_serial_number, transaction_number);

-- ============================================================
-- LICENSE TOKENS
-- Stores Ed25519-signed license tokens per tenant/device.
-- Only one token per tenant should be active at a time.
-- ============================================================
CREATE TABLE license_tokens (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    token_raw           TEXT NOT NULL,          -- Original Base64url token string
    business_id         TEXT NOT NULL,          -- businessId extracted from payload
    tier                TEXT NOT NULL DEFAULT 'free',  -- free | professional | enterprise
    issued_at           TIMESTAMPTZ NOT NULL,
    expires_at          TIMESTAMPTZ NOT NULL,
    device_fingerprint  TEXT,                   -- NULL = not device-locked
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    activated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_license_tokens_tenant ON license_tokens(tenant_id);
CREATE INDEX idx_license_tokens_tenant_active
    ON license_tokens(tenant_id, is_active);

-- ============================================================
-- DASHBOARD CACHE
-- Pre-computed stats for the management dashboard to avoid
-- expensive aggregation queries on every page load.
-- ============================================================
CREATE TABLE dashboard_cache (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    store_id        UUID,                       -- NULL = all stores for tenant
    cache_key       TEXT NOT NULL,              -- e.g. 'daily_summary:2026-03-21'
    payload         JSONB NOT NULL,             -- Arbitrary stats payload
    computed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL,       -- Cache TTL
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_dashboard_cache_tenant ON dashboard_cache(tenant_id);
CREATE UNIQUE INDEX idx_dashboard_cache_tenant_key
    ON dashboard_cache(tenant_id, cache_key);
CREATE INDEX idx_dashboard_cache_expires ON dashboard_cache(expires_at);

-- ============================================================
-- LAN SYNC PEERS
-- Registry of POS devices discovered via mDNS on the same LAN.
-- ============================================================
CREATE TABLE lan_sync_peers (
    device_id       TEXT NOT NULL,
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    device_name     TEXT NOT NULL,
    ip_address      TEXT NOT NULL,
    port            INTEGER NOT NULL DEFAULT 7070,
    app_version     TEXT,
    schema_version  INTEGER,
    is_reachable    BOOLEAN NOT NULL DEFAULT FALSE,
    last_seen_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (device_id, tenant_id)
);

CREATE INDEX idx_lan_sync_peers_tenant ON lan_sync_peers(tenant_id);
CREATE INDEX idx_lan_sync_peers_reachable
    ON lan_sync_peers(tenant_id, is_reachable) WHERE is_reachable = TRUE;

CREATE TRIGGER trg_lan_sync_peers_updated_at
    BEFORE UPDATE ON lan_sync_peers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- MANAGER PIN AUDIT LOG
-- Records every manager-PIN override for compliance.
-- ============================================================
CREATE TABLE manager_pins (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    manager_id      UUID NOT NULL,              -- references users(id)
    manager_name    TEXT NOT NULL,
    action          TEXT NOT NULL,              -- e.g. 'void_ticket', 'apply_discount'
    entity_type     TEXT,
    entity_id       TEXT,
    reason          TEXT,
    device_id       TEXT NOT NULL,
    authorised_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_manager_pins_tenant ON manager_pins(tenant_id);
CREATE INDEX idx_manager_pins_manager ON manager_pins(tenant_id, manager_id);
CREATE INDEX idx_manager_pins_authorised_at
    ON manager_pins(tenant_id, authorised_at DESC);
