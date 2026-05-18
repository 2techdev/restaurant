BEGIN;
DROP INDEX IF EXISTS products_snoozed_idx;
ALTER TABLE products DROP COLUMN IF EXISTS snooze_until;
ALTER TABLE products DROP COLUMN IF EXISTS is_snoozed;
COMMIT;
