-- Migration 024: Super admin impersonation (F1)
-- Wallee-style ghost login — super admin (e.g. developer@2tech.ch) drops into
-- a target tenant's admin user account for 15 minutes without a password.
--
-- Schema:
--   admin_users.is_super_admin   — boolean flag, default false (existing rows safe)
--   impersonation_sessions       — full audit row per impersonation: who, target,
--                                   when started/ended, reason, ip, user-agent.
--
-- audit_log doesn't FK to admin_users (its user_id → users), so impersonation
-- audit lives in its own table. Destructive-action piggyback (`impersonated_by`
-- on audit_log) is a v1.1 follow-up.

ALTER TABLE admin_users
    ADD COLUMN IF NOT EXISTS is_super_admin BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS impersonation_sessions (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    super_admin_id    UUID NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
    target_user_id    UUID NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
    target_tenant_id  UUID NOT NULL,
    started_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at          TIMESTAMPTZ,
    reason            TEXT,
    ip_address        TEXT,
    user_agent        TEXT
);

CREATE INDEX IF NOT EXISTS idx_impersonation_super_admin
    ON impersonation_sessions(super_admin_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_impersonation_tenant
    ON impersonation_sessions(target_tenant_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_impersonation_active
    ON impersonation_sessions(super_admin_id) WHERE ended_at IS NULL;
