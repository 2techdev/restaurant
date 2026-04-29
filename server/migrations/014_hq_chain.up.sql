-- 014_hq_chain.up.sql
-- HQ (Headquarters) Chain Restaurant logic.
-- Number 014 because 013 was claimed by the parallel "menu sync" task.
-- Adds organization-level master-menu, lock policies, version history,
-- per-tenant membership and HQ-level user roles.
--
-- Coexists with the existing `organizations` table (002_multi_store) and
-- the `tenants` table (001_initial). New tables use additive migrations
-- so re-running on partially migrated databases is safe.

-- ============================================================
-- ORGANIZATIONS — extend existing table for HQ semantics
-- ============================================================
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS owner_user_id UUID REFERENCES users(id);
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS settings_json JSONB DEFAULT '{}';

-- ============================================================
-- ORGANIZATION MEMBERSHIPS — which tenant (restaurant) belongs to which org
-- A tenant may be a "master" tenant (the one editing the HQ menu) OR a follower.
-- ============================================================
CREATE TABLE IF NOT EXISTS organization_memberships (
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_master       BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (organization_id, tenant_id)
);

CREATE INDEX IF NOT EXISTS idx_org_memberships_tenant ON organization_memberships(tenant_id);
CREATE INDEX IF NOT EXISTS idx_org_memberships_org    ON organization_memberships(organization_id);

-- Backfill: where tenants.organization_id is set, treat as a member.
INSERT INTO organization_memberships (organization_id, tenant_id, joined_at, is_master)
SELECT t.organization_id, t.id, NOW(), FALSE
FROM tenants t
WHERE t.organization_id IS NOT NULL
ON CONFLICT (organization_id, tenant_id) DO NOTHING;

-- ============================================================
-- MENU POLICIES — per-organization lock rules for HQ master products
-- ============================================================
CREATE TABLE IF NOT EXISTS menu_policies (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id       UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    product_id            UUID NOT NULL,                       -- HQ master product id
    lock_type             TEXT NOT NULL CHECK (lock_type IN ('PRICE_LOCKED','FULLY_LOCKED','FLEXIBLE')),
    allow_local_additions BOOLEAN NOT NULL DEFAULT TRUE,
    allow_local_disable   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(organization_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_menu_policies_org ON menu_policies(organization_id);
CREATE INDEX IF NOT EXISTS idx_menu_policies_product ON menu_policies(product_id);

-- ============================================================
-- MASTER MENUS — current published version pointer per org
-- ============================================================
CREATE TABLE IF NOT EXISTS master_menus (
    organization_id UUID PRIMARY KEY REFERENCES organizations(id) ON DELETE CASCADE,
    current_version INT NOT NULL DEFAULT 0,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- MASTER MENU VERSIONS — immutable snapshot history of HQ menu
-- ============================================================
CREATE TABLE IF NOT EXISTS master_menu_versions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    version         INT NOT NULL,
    snapshot        JSONB NOT NULL,
    published_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_by    UUID REFERENCES users(id),
    UNIQUE(organization_id, version)
);

CREATE INDEX IF NOT EXISTS idx_master_menu_versions_org ON master_menu_versions(organization_id, version DESC);

-- ============================================================
-- USERS — HQ role + organization scope (org_role kept separate from
-- the legacy free-form `role` column to avoid breaking POS rows).
-- ============================================================
ALTER TABLE users ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id);
ALTER TABLE users ADD COLUMN IF NOT EXISTS org_role TEXT;

-- Soft check: enforced application-side. Hard CHECK omitted because legacy
-- `role` rows in users predate the HQ role taxonomy and live alongside.
-- Allowed values: HQ_ADMIN, HQ_MANAGER, RESTAURANT_MANAGER, RESTAURANT_STAFF, POS_OPERATOR.

CREATE INDEX IF NOT EXISTS idx_users_organization ON users(organization_id) WHERE organization_id IS NOT NULL;

-- ============================================================
-- PER-TENANT MENU VERSIONS — created here only if the parallel
-- "menu sync" task has not landed yet. Use IF NOT EXISTS to avoid
-- collision; ALTERs add HQ-specific fields if the table predates this.
-- ============================================================
CREATE TABLE IF NOT EXISTS menu_versions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    version         INT NOT NULL,
    snapshot        JSONB NOT NULL,
    source          TEXT NOT NULL DEFAULT 'local',  -- 'local' | 'master'
    organization_id UUID REFERENCES organizations(id),
    master_version  INT,
    published_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_by    UUID,
    UNIQUE(tenant_id, version)
);

ALTER TABLE menu_versions ADD COLUMN IF NOT EXISTS source          TEXT NOT NULL DEFAULT 'local';
ALTER TABLE menu_versions ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id);
ALTER TABLE menu_versions ADD COLUMN IF NOT EXISTS master_version  INT;

CREATE INDEX IF NOT EXISTS idx_menu_versions_tenant ON menu_versions(tenant_id, version DESC);
CREATE INDEX IF NOT EXISTS idx_menu_versions_org    ON menu_versions(organization_id) WHERE organization_id IS NOT NULL;

-- ============================================================
-- TRIGGERS
-- ============================================================
DROP TRIGGER IF EXISTS trg_menu_policies_updated_at ON menu_policies;
CREATE TRIGGER trg_menu_policies_updated_at
    BEFORE UPDATE ON menu_policies
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
