-- 015_device_pairing.up.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Device-scoped API keys for POS tablets. Replaces the per-tenant key
-- (`tenants.pos_api_key`) with a one-row-per-tablet model so that:
--   * Each tablet has its own credential (revocable individually).
--   * The audit trail records which device hit which menu version.
--   * Operators don't have to copy-paste plain keys — POS pairs by login,
--     server mints the key and POS stores it in OS keystore.
--
-- Naming: this table is INTENTIONALLY distinct from `device_registrations`
-- (legacy ad-hoc heartbeat path used by the older device-pairing flow). The
-- new table is the canonical home for *credential-bearing* device entries.
--
-- API surface:
--   POST   /api/v1/me/devices/register   — POS calls after admin login
--   GET    /api/v1/me/devices            — backoffice lists tablets
--   DELETE /api/v1/me/devices/{id}       — backoffice revokes a tablet
--
-- Auth:
--   * Menu sync endpoints (`GET /menu/version|snapshot`) accept either a
--     JWT or X-API-Key. The X-API-Key path now matches against
--     `pos_devices.api_key_hash` first, falling back to the legacy
--     `tenants.pos_api_key` so old keys keep working until rotated out.

CREATE TABLE IF NOT EXISTS pos_devices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    -- The admin user who paired the tablet. ON DELETE SET NULL: if the user
    -- is removed we keep the audit trail row but lose the back-reference.
    user_id             UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    -- Operator-given label, e.g. "Pizzeria Da Mario - Kasa 1". Unique per
    -- tenant so the backoffice list reads cleanly.
    name                TEXT NOT NULL,
    -- Optional fingerprint (model + Android ID hash) to detect a wipe-and-
    -- re-pair on the same physical hardware. Not security-critical.
    device_fingerprint  TEXT,
    -- bcrypt hash of the plaintext key. Plaintext is shown to POS exactly
    -- once (in the register response) and never persisted server-side.
    api_key_hash        TEXT NOT NULL,
    -- First 12 chars of the plaintext key (e.g. "gc_dev_aBcD"). Used as
    -- a lookup index so we don't have to bcrypt-compare every row.
    api_key_prefix      TEXT NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at        TIMESTAMPTZ,
    revoked_at          TIMESTAMPTZ,
    UNIQUE (tenant_id, name)
);

-- Lookup path: `validateDeviceApiKey` parses the prefix from the incoming
-- key, hits this index, then bcrypt-verifies the matching candidates.
CREATE INDEX IF NOT EXISTS pos_devices_api_key_prefix_idx
    ON pos_devices (api_key_prefix)
    WHERE revoked_at IS NULL;

-- Backoffice list query path.
CREATE INDEX IF NOT EXISTS pos_devices_tenant_id_idx
    ON pos_devices (tenant_id)
    WHERE revoked_at IS NULL;
