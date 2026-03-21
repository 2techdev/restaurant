-- Sync Events: stores all change events from POS devices for cross-device sync.
-- Each device pushes its local changes here; other devices pull from here.
CREATE TABLE IF NOT EXISTS sync_events (
    id          TEXT PRIMARY KEY,         -- UUID from device
    tenant_id   TEXT NOT NULL,
    device_id   TEXT NOT NULL,
    table_name  TEXT NOT NULL,            -- orders, products, users, etc.
    record_id   TEXT NOT NULL,            -- UUID of the changed record
    operation   TEXT NOT NULL,            -- insert, update, delete
    payload     JSONB NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL,     -- when event was created on device
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()  -- when server received it
);

CREATE INDEX IF NOT EXISTS idx_sync_events_tenant_received ON sync_events(tenant_id, received_at);
CREATE INDEX IF NOT EXISTS idx_sync_events_device ON sync_events(device_id);

-- Device sync cursors: track each device's last pull position
CREATE TABLE IF NOT EXISTS sync_device_cursors (
    device_id   TEXT NOT NULL,
    tenant_id   TEXT NOT NULL,
    last_pull_at TIMESTAMPTZ,
    last_push_at TIMESTAMPTZ,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (device_id, tenant_id)
);
