-- Migration 023: external_menu_refs + menu_sync_events
-- D Strategy Aşama 1 — Magic-link menu import from gastro.2hub.ch
--
-- external_menu_refs: tenant'ın local menu entity'lerini remote sistemdeki
-- karşılığına bağlar (bidirectional ID mapping). Re-import'larda local UUID
-- korunur, remote ID değişse de local snapshot bozulmaz.
--
-- menu_sync_events: her sync olayını idempotent log'lar. payload_hash ile
-- aynı snapshot'ı iki kez apply etmek SKIP edilir.

-- ── Defensive translation columns ─────────────────────────────────────
-- Migration 022 hedeflenen DB'lerde name_translations + description_translations
-- ekliyor. Eğer 022 uygulanmamışsa (deploy drift senaryosu), apply.go yine de
-- bu kolonlara yazıyor. IF NOT EXISTS ile burada garantiliyoruz —
-- zaten uygulanmışsa no-op.
ALTER TABLE categories
    ADD COLUMN IF NOT EXISTS name_translations JSONB DEFAULT '{}'::jsonb;

ALTER TABLE products
    ADD COLUMN IF NOT EXISTS name_translations JSONB DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS description_translations JSONB DEFAULT '{}'::jsonb;

CREATE TABLE IF NOT EXISTS external_menu_refs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL,
  entity_type     TEXT NOT NULL CHECK (entity_type IN ('category','product','modifier_group','modifier')),
  local_id        UUID NOT NULL,
  remote_system   TEXT NOT NULL DEFAULT 'gastrohub',
  remote_id       TEXT NOT NULL,
  remote_version  BIGINT DEFAULT 0,
  last_synced_at  TIMESTAMPTZ,
  last_sync_from  TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uniq_local  UNIQUE (tenant_id, entity_type, local_id, remote_system),
  CONSTRAINT uniq_remote UNIQUE (tenant_id, entity_type, remote_system, remote_id)
);

CREATE INDEX IF NOT EXISTS idx_external_menu_refs_tenant_entity
  ON external_menu_refs(tenant_id, entity_type);

CREATE TABLE IF NOT EXISTS menu_sync_events (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL,
  direction       TEXT NOT NULL,
  event_type      TEXT NOT NULL,
  idempotency_key TEXT NOT NULL UNIQUE,
  payload_hash    TEXT NOT NULL,
  payload         JSONB NOT NULL,
  status          TEXT NOT NULL CHECK (status IN ('pending','applied','failed','skipped')),
  error           TEXT,
  retry_count     INT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  applied_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_menu_sync_events_tenant_status
  ON menu_sync_events(tenant_id, status);

CREATE INDEX IF NOT EXISTS idx_menu_sync_events_tenant_created
  ON menu_sync_events(tenant_id, created_at DESC);
