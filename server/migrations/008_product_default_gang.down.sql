-- Migration 008 rollback
ALTER TABLE products DROP COLUMN IF EXISTS default_gang;
