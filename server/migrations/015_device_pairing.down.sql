-- 015_device_pairing.down.sql
DROP INDEX IF EXISTS pos_devices_tenant_id_idx;
DROP INDEX IF EXISTS pos_devices_api_key_prefix_idx;
DROP TABLE IF EXISTS pos_devices;
