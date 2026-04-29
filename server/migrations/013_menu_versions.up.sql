-- Migration 013: Cloud-master menu sync — per-tenant snapshot versions,
-- POS API key, and version pointer column on tenants.
--
-- The Go backend (api.2hub.ch) is the authoritative source of menu data.
-- POS clients pull /api/v1/menu/version + /api/v1/menu/snapshot using a
-- per-tenant API key. Backoffice users press "Publish" which freezes the
-- live menu tables into an immutable JSON snapshot row.

-- ============================================================
-- TENANTS — POS API key + current version pointer
-- ============================================================
ALTER TABLE tenants
    ADD COLUMN IF NOT EXISTS pos_api_key            TEXT,
    ADD COLUMN IF NOT EXISTS menu_version_current   INTEGER NOT NULL DEFAULT 0;

-- pos_api_key holds the bcrypt/PBKDF2 hash, NOT the plain key. The plain
-- key is shown ONCE at rotation time. Index allows constant-time lookup
-- by hash prefix during auth.
CREATE INDEX IF NOT EXISTS idx_tenants_pos_api_key
    ON tenants(pos_api_key)
    WHERE pos_api_key IS NOT NULL;

-- ============================================================
-- MENU_VERSIONS — immutable per-tenant snapshots
-- ============================================================
CREATE TABLE IF NOT EXISTS menu_versions (
    id            UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID         NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    version       INTEGER      NOT NULL,
    snapshot      JSONB        NOT NULL,
    published_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    published_by  UUID         REFERENCES users(id) ON DELETE SET NULL,
    UNIQUE (tenant_id, version)
);

CREATE INDEX IF NOT EXISTS idx_menu_versions_tenant_published
    ON menu_versions(tenant_id, published_at DESC);

CREATE INDEX IF NOT EXISTS idx_menu_versions_tenant_version
    ON menu_versions(tenant_id, version DESC);
