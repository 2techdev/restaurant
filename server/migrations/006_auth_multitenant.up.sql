-- 006_auth_multitenant.up.sql
-- Unified app_users, device_pairings, and persisted refresh_tokens tables
-- to support the full multi-tenant auth system.
--
-- "Brand" in the API maps to the existing `organizations` table.
-- app_users is the unified table for all credential-based logins:
--   brand_manager, store_manager, waiter, kiosk, kds

-- ============================================================
-- APP USERS (all credential-based logins)
-- ============================================================
CREATE TABLE IF NOT EXISTS app_users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    store_id        UUID REFERENCES stores(id) ON DELETE CASCADE,
    -- NULL store_id = org-level access (brand_manager)
    -- NOT NULL store_id = scoped to a specific store
    email           VARCHAR(255),
    username        VARCHAR(100),
    password_hash   TEXT NOT NULL,
    role            VARCHAR(50) NOT NULL DEFAULT 'waiter',
    -- roles: brand_manager, store_manager, waiter, kiosk, kds
    display_name    VARCHAR(255),
    pin_hash        TEXT,   -- optional: allows dual PIN + password login
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    last_login      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Email uniqueness is global (one account per email across all orgs)
CREATE UNIQUE INDEX IF NOT EXISTS idx_app_users_email
    ON app_users(email) WHERE email IS NOT NULL;

-- Username is unique per store (two stores can have "mario" as a waiter)
CREATE UNIQUE INDEX IF NOT EXISTS idx_app_users_username_store
    ON app_users(store_id, username)
    WHERE username IS NOT NULL AND store_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_app_users_org   ON app_users(organization_id);
CREATE INDEX IF NOT EXISTS idx_app_users_store ON app_users(store_id);
CREATE INDEX IF NOT EXISTS idx_app_users_role  ON app_users(organization_id, role);

-- ============================================================
-- DEVICE PAIRINGS (KDS / ODS pairing via 6-digit codes)
-- ============================================================
CREATE TABLE IF NOT EXISTS device_pairings (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id     UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    pairing_code VARCHAR(6) NOT NULL,
    device_type  VARCHAR(50) NOT NULL DEFAULT 'kds', -- kds, ods
    device_name  VARCHAR(255),
    user_id      UUID REFERENCES app_users(id) ON DELETE SET NULL,
    paired_at    TIMESTAMPTZ,
    expires_at   TIMESTAMPTZ NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_pairings_store ON device_pairings(store_id);
-- Code lookup: only one active (unpaired) code per store at a time
CREATE UNIQUE INDEX IF NOT EXISTS idx_device_pairings_active_code
    ON device_pairings(store_id, pairing_code)
    WHERE paired_at IS NULL;

-- ============================================================
-- REFRESH TOKENS (persisted for server-side revocation)
-- ============================================================
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    token_hash  TEXT NOT NULL UNIQUE,  -- SHA-256(raw_token), hex-encoded
    device_id   VARCHAR(255),           -- optional client device tag
    expires_at  TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash ON refresh_tokens(token_hash);
-- Clean-up index: quickly find expired tokens for background jobs
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires ON refresh_tokens(expires_at);

-- ============================================================
-- AUTO-UPDATE updated_at
-- ============================================================
CREATE TRIGGER trg_app_users_updated_at
    BEFORE UPDATE ON app_users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
