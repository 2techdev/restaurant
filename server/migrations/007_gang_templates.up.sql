-- Migration 007: Gang (course) templates
-- Adds server-side gang_templates table.
-- These records are synced down to Flutter clients at first login and define
-- the multi-course service structure shown in POS, KDS and Waiter apps.

CREATE TABLE IF NOT EXISTS gang_templates (
    id          TEXT        PRIMARY KEY,
    tenant_id   UUID        NOT NULL REFERENCES tenants(id),
    name        TEXT        NOT NULL,
    sort_order  INTEGER     NOT NULL DEFAULT 1,
    color       TEXT        NOT NULL DEFAULT '#528DFF',
    is_default  BOOLEAN     NOT NULL DEFAULT FALSE,
    is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status INTEGER     NOT NULL DEFAULT 0,
    is_deleted  BOOLEAN     NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_gang_templates_tenant
    ON gang_templates(tenant_id)
    WHERE is_deleted = FALSE;
