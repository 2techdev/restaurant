-- Migration 008: optional default_gang on products
-- Allows backoffice to hint which course (1/2/3) a product defaults to.
-- POS/Waiter may override per order. Null = no default.

ALTER TABLE products
    ADD COLUMN IF NOT EXISTS default_gang SMALLINT NULL
    CHECK (default_gang IS NULL OR default_gang BETWEEN 1 AND 3);
