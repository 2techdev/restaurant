-- Rollback migration 006: drop in reverse dependency order

DROP TABLE IF EXISTS manager_pins;
DROP TABLE IF EXISTS lan_sync_peers;
DROP TABLE IF EXISTS dashboard_cache;
DROP TABLE IF EXISTS license_tokens;
DROP TABLE IF EXISTS fiscal_signatures;
DROP TABLE IF EXISTS fiscal_tse_config;
