-- Down 023: drop external_menu_refs + menu_sync_events
DROP INDEX IF EXISTS idx_menu_sync_events_tenant_created;
DROP INDEX IF EXISTS idx_menu_sync_events_tenant_status;
DROP TABLE IF EXISTS menu_sync_events;

DROP INDEX IF EXISTS idx_external_menu_refs_tenant_entity;
DROP TABLE IF EXISTS external_menu_refs;
