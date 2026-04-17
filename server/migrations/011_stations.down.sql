-- Migration 011 rollback
ALTER TABLE products DROP COLUMN IF EXISTS station_id;
DROP TABLE IF EXISTS stations;
