-- Migration 035 — Product "sold out" snooze
--
-- Two columns on products so a manager can flip an item to "86'd" (sold out)
-- without deleting it from the menu. is_snoozed gates the POS at the catalog
-- layer; snooze_until is an optional auto-reset deadline (e.g. end of dinner
-- service). A small background goroutine in the Go server ticks every minute
-- and flips is_snoozed back to false once snooze_until passes — this keeps
-- the catalog accurate without forcing the operator to remember to un-86 in
-- the morning.
--
-- "Today only" semantics: if snooze_until is NULL, the item stays sold out
-- until manually toggled. If set, it reverts automatically.

BEGIN;

ALTER TABLE products ADD COLUMN IF NOT EXISTS is_snoozed   boolean     NOT NULL DEFAULT false;
ALTER TABLE products ADD COLUMN IF NOT EXISTS snooze_until timestamptz;

-- Partial index — only rows that are actively snoozed get indexed. Tiny.
CREATE INDEX IF NOT EXISTS products_snoozed_idx
  ON products(snooze_until)
  WHERE is_snoozed = true AND snooze_until IS NOT NULL;

COMMIT;
