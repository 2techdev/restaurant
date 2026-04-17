-- Migration 008: Printer configurations
-- One row per physical printer per store.
-- Target is "kitchen", "bar", or "receipt". Stores may have a second
-- (backup) row with the same target — at most one primary + one backup
-- per (store_id, target) is enforced by a partial unique index.

CREATE TABLE IF NOT EXISTS printer_configs (
    id           TEXT        PRIMARY KEY,
    tenant_id    UUID        NOT NULL REFERENCES tenants(id),
    store_id     TEXT        NOT NULL,
    target       TEXT        NOT NULL CHECK (target IN ('kitchen','bar','receipt')),
    name         TEXT        NOT NULL,
    type         TEXT        NOT NULL DEFAULT 'ethernet' CHECK (type IN ('ethernet','usb')),
    ip           TEXT        NOT NULL DEFAULT '',
    port         INTEGER     NOT NULL DEFAULT 9100,
    usb_path     TEXT        NOT NULL DEFAULT '',
    paper_width  TEXT        NOT NULL DEFAULT '80mm' CHECK (paper_width IN ('58mm','80mm')),
    enabled      BOOLEAN     NOT NULL DEFAULT TRUE,
    is_backup    BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted   BOOLEAN     NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_printer_configs_store
    ON printer_configs(store_id)
    WHERE is_deleted = FALSE;

-- At most one primary per (store, target) and at most one backup per (store, target).
CREATE UNIQUE INDEX IF NOT EXISTS uniq_printer_configs_primary
    ON printer_configs(store_id, target)
    WHERE is_deleted = FALSE AND is_backup = FALSE;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_printer_configs_backup
    ON printer_configs(store_id, target)
    WHERE is_deleted = FALSE AND is_backup = TRUE;
