-- 006_auth_multitenant.down.sql
DROP TABLE IF EXISTS refresh_tokens CASCADE;
DROP TABLE IF EXISTS device_pairings CASCADE;
DROP TABLE IF EXISTS app_users CASCADE;
