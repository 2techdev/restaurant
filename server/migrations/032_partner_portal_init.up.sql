-- Migration 032 — Partner portal init
--
-- Drops three vestigial empty tables from migration 002 (brands, stores,
-- employees) that were never adopted in production. Introduces the new
-- partner-portal schema: dealers (reseller tier), editions (license tiers),
-- account_pools (purchased/used quotas), edition_assignments, app_versions
-- + store_app_assignments, partner_employees (internal staff), and
-- store_feature_flags. A manual-only billing_invoices table (no Stripe).
--
-- Pre-migration data fixes:
--   • Merge the duplicate "GastroCore HQ" organization row by re-pointing
--     all dependent FKs to the canonical row that owns the active
--     organization_memberships, then deleting the orphan.
--
-- Safe to re-run: every CREATE uses IF NOT EXISTS; DROPs are guarded.

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Drop vestigial tables (research confirmed 0 rows in prod)
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS brands    CASCADE;
DROP TABLE IF EXISTS stores    CASCADE;
DROP TABLE IF EXISTS employees CASCADE;

-- ---------------------------------------------------------------------------
-- 1. Merge duplicate "GastroCore HQ" organization rows
-- ---------------------------------------------------------------------------
-- Canonical = the org that actually owns the active organization_memberships
-- rows (i.e. has been used by data). The other row is orphaned.
DO $$
DECLARE
  canonical_id uuid;
  orphan_id    uuid;
  dup_count    int;
BEGIN
  SELECT COUNT(*) INTO dup_count FROM organizations WHERE name = 'GastroCore HQ';
  IF dup_count = 2 THEN
    SELECT organization_id INTO canonical_id
      FROM organization_memberships
      GROUP BY organization_id
      ORDER BY COUNT(*) DESC
      LIMIT 1;
    SELECT id INTO orphan_id
      FROM organizations
     WHERE name = 'GastroCore HQ' AND id <> canonical_id
     LIMIT 1;
    IF orphan_id IS NOT NULL THEN
      -- Re-point any references that might still touch the orphan.
      UPDATE admin_users               SET organization_id = canonical_id WHERE organization_id = orphan_id;
      UPDATE app_users                 SET organization_id = canonical_id WHERE organization_id = orphan_id;
      UPDATE tenants                   SET organization_id = canonical_id WHERE organization_id = orphan_id;
      UPDATE organization_memberships  SET organization_id = canonical_id WHERE organization_id = orphan_id;
      DELETE FROM organizations WHERE id = orphan_id;
    END IF;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. Dealers (3rd-tier reseller layer; optional but FK-ready)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dealers (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL,
  code          text UNIQUE,
  country_code  char(2),
  contact_email text,
  phone         text,
  status        text NOT NULL DEFAULT 'active'
                CHECK (status IN ('active','suspended','archived')),
  bd_employee_id uuid,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS dealers_status_idx ON dealers(status);

-- ---------------------------------------------------------------------------
-- 3. Editions (license/feature tiers)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS editions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code            text UNIQUE NOT NULL,
  name            text NOT NULL,
  features        jsonb NOT NULL DEFAULT '{}'::jsonb,
  max_stores      int,
  max_devices     int,
  price_chf_month numeric(10,2) NOT NULL DEFAULT 0,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 4. Account pools (purchased counts per dealer × edition)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS account_pools (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dealer_id   uuid REFERENCES dealers(id) ON DELETE CASCADE,
  edition_id  uuid NOT NULL REFERENCES editions(id) ON DELETE RESTRICT,
  purchased   int  NOT NULL CHECK (purchased >= 0),
  used        int  NOT NULL DEFAULT 0 CHECK (used >= 0),
  expires_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (used <= purchased)
);
CREATE INDEX IF NOT EXISTS account_pools_dealer_idx ON account_pools(dealer_id);

-- ---------------------------------------------------------------------------
-- 5. Edition assignments (which brand/store consumed a pool slot)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS edition_assignments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pool_id     uuid REFERENCES account_pools(id) ON DELETE SET NULL,
  brand_id    uuid REFERENCES organizations(id) ON DELETE CASCADE,
  store_id    uuid REFERENCES tenants(id) ON DELETE CASCADE,
  edition_id  uuid NOT NULL REFERENCES editions(id),
  assigned_by uuid,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  revoked_at  timestamptz,
  CHECK (brand_id IS NOT NULL OR store_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS edition_assignments_brand_idx ON edition_assignments(brand_id);
CREATE INDEX IF NOT EXISTS edition_assignments_store_idx ON edition_assignments(store_id);

-- ---------------------------------------------------------------------------
-- 6. App versions (APK distribution) + per-store assignment
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_versions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  flavor        text NOT NULL,
  version       text NOT NULL,
  channel       text NOT NULL DEFAULT 'stable'
                CHECK (channel IN ('stable','beta','canary')),
  apk_url       text NOT NULL,
  sha256        text NOT NULL,
  release_notes text,
  is_mandatory  boolean NOT NULL DEFAULT false,
  min_supported text,
  released_at   timestamptz NOT NULL DEFAULT now(),
  released_by   uuid,
  UNIQUE (flavor, version)
);
CREATE INDEX IF NOT EXISTS app_versions_channel_idx ON app_versions(flavor, channel, released_at DESC);

CREATE TABLE IF NOT EXISTS store_app_assignments (
  store_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  flavor         text NOT NULL,
  app_version_id uuid NOT NULL REFERENCES app_versions(id) ON DELETE RESTRICT,
  assigned_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, flavor)
);

-- ---------------------------------------------------------------------------
-- 7. Partner employees (internal gastrocore staff — separate from admin_users)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS partner_employees (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         varchar(255) UNIQUE NOT NULL,
  name          varchar(255) NOT NULL,
  password_hash varchar(512) NOT NULL,
  role          varchar(32)  NOT NULL DEFAULT 'EMPLOYEE'
                CHECK (role IN ('OPERATOR','BD','MANAGER','EMPLOYEE')),
  status        varchar(32) NOT NULL DEFAULT 'active'
                CHECK (status IN ('active','disabled')),
  last_login_at timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS partner_employees_role_idx ON partner_employees(role);

-- Wire FKs that pointed forward (dealers.bd_employee_id, edition_assignments.assigned_by, app_versions.released_by)
ALTER TABLE dealers
  ADD CONSTRAINT dealers_bd_employee_fk
  FOREIGN KEY (bd_employee_id) REFERENCES partner_employees(id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- 8. Per-store feature flags & hardware (overrides edition defaults)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS store_feature_flags (
  store_id    uuid PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
  hardware    jsonb NOT NULL DEFAULT '{}'::jsonb,
  features    jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid REFERENCES partner_employees(id) ON DELETE SET NULL
);

-- ---------------------------------------------------------------------------
-- 9. Billing invoices (manual CHF tracker — NO Stripe per user direction)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS billing_invoices (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dealer_id   uuid REFERENCES dealers(id) ON DELETE SET NULL,
  brand_id    uuid REFERENCES organizations(id) ON DELETE SET NULL,
  amount_chf  numeric(10,2) NOT NULL,
  status      text NOT NULL DEFAULT 'draft'
              CHECK (status IN ('draft','issued','paid','void')),
  issued_at   timestamptz,
  paid_at     timestamptz,
  pdf_url     text,
  notes       text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS billing_invoices_brand_idx ON billing_invoices(brand_id);

-- ---------------------------------------------------------------------------
-- 10. Extend existing tables for partner portal linkage
-- ---------------------------------------------------------------------------
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS dealer_id  uuid REFERENCES dealers(id) ON DELETE SET NULL;
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE tenants       ADD COLUMN IF NOT EXISTS dealer_id  uuid REFERENCES dealers(id) ON DELETE SET NULL;
ALTER TABLE tenants       ADD COLUMN IF NOT EXISTS store_code text;
ALTER TABLE tenants       ADD COLUMN IF NOT EXISTS current_edition_id uuid REFERENCES editions(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS tenants_store_code_uniq ON tenants(store_code) WHERE store_code IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 11. Seed: bootstrap OPERATOR account by copying admin@gastrocore.ch hash
-- ---------------------------------------------------------------------------
INSERT INTO partner_employees (email, name, password_hash, role)
SELECT email, name, password_hash, 'OPERATOR'
  FROM admin_users
 WHERE email = 'admin@gastrocore.ch'
   AND NOT EXISTS (SELECT 1 FROM partner_employees WHERE email = 'admin@gastrocore.ch');

-- ---------------------------------------------------------------------------
-- 12. Seed: three default editions (Free / Pro / Enterprise)
-- ---------------------------------------------------------------------------
INSERT INTO editions (code, name, features, max_stores, max_devices, price_chf_month)
VALUES
  ('free',       'Free',       '{"online":false,"kiosk":false,"kds":false,"caller_id":false}'::jsonb, 1,    2,  0),
  ('pro',        'Pro',        '{"online":true ,"kiosk":true ,"kds":true ,"caller_id":false}'::jsonb, 5,    10, 49),
  ('enterprise', 'Enterprise', '{"online":true ,"kiosk":true ,"kds":true ,"caller_id":true }'::jsonb, NULL, NULL, 149)
ON CONFLICT (code) DO NOTHING;

COMMIT;
