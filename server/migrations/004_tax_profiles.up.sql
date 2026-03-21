-- Tax Profiles: Swiss MWST rate matrix per order type and product group.
-- Rates (2024/2026): 8.1% standard, 2.6% reduced (takeaway/delivery food),
--                    3.8% accommodation (hotel/breakfast service).
CREATE TABLE IF NOT EXISTS tax_profiles (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id         UUID NOT NULL REFERENCES tenants(id),
    country_code      TEXT NOT NULL DEFAULT 'CH',
    order_type        TEXT NOT NULL,          -- dine_in, takeaway, delivery, accommodation
    product_tax_group TEXT NOT NULL,          -- food, beverage, alcohol
    tax_rate          NUMERIC(5,2) NOT NULL,
    tax_name          TEXT NOT NULL,
    is_default        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tax_profiles_tenant_id ON tax_profiles(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tax_profiles_lookup ON tax_profiles(tenant_id, order_type, product_tax_group);

CREATE TRIGGER trg_tax_profiles_updated_at
    BEFORE UPDATE ON tax_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
