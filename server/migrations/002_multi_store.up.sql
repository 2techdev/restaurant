-- Multi-Store Architecture
-- Adds Organization > Brand > Store hierarchy to support multi-location restaurants.

-- ============================================================
-- ORGANIZATIONS
-- ============================================================
CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    legal_name VARCHAR(255),
    tax_id VARCHAR(50),
    country VARCHAR(2) NOT NULL DEFAULT 'CH',
    address TEXT,
    phone VARCHAR(50),
    email VARCHAR(255),
    logo TEXT,
    plan VARCHAR(20) NOT NULL DEFAULT 'trial',
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    trial_ends_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- BRANDS
-- ============================================================
CREATE TABLE IF NOT EXISTS brands (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    name VARCHAR(255) NOT NULL,
    logo TEXT,
    description TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- STORES (branches)
-- ============================================================
CREATE TABLE IF NOT EXISTS stores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    brand_id UUID NOT NULL REFERENCES brands(id),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    store_code VARCHAR(20) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    legal_name VARCHAR(255),
    country VARCHAR(2) NOT NULL DEFAULT 'CH',
    address TEXT,
    city VARCHAR(100),
    postal_code VARCHAR(10),
    phone VARCHAR(50),
    email VARCHAR(255),
    timezone VARCHAR(50) NOT NULL DEFAULT 'Europe/Zurich',
    currency VARCHAR(3) NOT NULL DEFAULT 'CHF',
    tax_rate DECIMAL(5,2) DEFAULT 8.1,
    manager_name VARCHAR(255),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    expires_at TIMESTAMPTZ,
    business_hours JSONB,
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- ADMIN USERS (dashboard access)
-- ============================================================
CREATE TABLE IF NOT EXISTS admin_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    role VARCHAR(30) NOT NULL DEFAULT 'viewer',
    store_ids UUID[] DEFAULT '{}',
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- EMPLOYEES (POS staff)
-- ============================================================
CREATE TABLE IF NOT EXISTS employees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES stores(id),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    name VARCHAR(255) NOT NULL,
    pin_hash VARCHAR(255),
    role VARCHAR(20) NOT NULL DEFAULT 'waiter',
    is_active BOOLEAN NOT NULL DEFAULT true,
    phone VARCHAR(50),
    email VARCHAR(255),
    avatar TEXT,
    permissions JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX idx_brands_org ON brands(organization_id);
CREATE INDEX idx_stores_brand ON stores(brand_id);
CREATE INDEX idx_stores_org ON stores(organization_id);
CREATE INDEX idx_stores_code ON stores(store_code);
CREATE INDEX idx_stores_status ON stores(organization_id, status);
CREATE INDEX idx_admin_users_org ON admin_users(organization_id);
CREATE INDEX idx_admin_users_email ON admin_users(email);
CREATE INDEX idx_employees_store ON employees(store_id);
CREATE INDEX idx_employees_org ON employees(organization_id);

-- ============================================================
-- UPDATED_AT TRIGGERS for new tables
-- ============================================================
CREATE TRIGGER trg_organizations_updated_at
    BEFORE UPDATE ON organizations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_brands_updated_at
    BEFORE UPDATE ON brands
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_stores_updated_at
    BEFORE UPDATE ON stores
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_admin_users_updated_at
    BEFORE UPDATE ON admin_users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_employees_updated_at
    BEFORE UPDATE ON employees
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- LINK EXISTING TENANTS to the new hierarchy
-- ============================================================
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id);
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES stores(id);
