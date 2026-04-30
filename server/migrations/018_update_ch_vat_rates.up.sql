-- Migration 018: bring tax_profiles up to the 2024-01-01 Swiss VAT increase.
--
-- Old rates (7.7 / 2.5 / 3.7) are obsolete since 2024-01-01. Production DBs
-- seeded before that date carry the old values; the seed script is already
-- updated (server/cmd/seed/main.go inserts 8.1 / 2.6 / 3.8). This migration
-- patches existing rows in-place — safe to apply repeatedly because the
-- WHERE clause filters on the old rate.

UPDATE tax_profiles SET tax_rate = 8.1, updated_at = NOW()
  WHERE tax_rate = 7.7;
UPDATE tax_profiles SET tax_rate = 2.6, updated_at = NOW()
  WHERE tax_rate = 2.5;
UPDATE tax_profiles SET tax_rate = 3.8, updated_at = NOW()
  WHERE tax_rate = 3.7;

-- Update display names if they still mention the old rate
UPDATE tax_profiles SET tax_name = REPLACE(tax_name, '7.7%', '8.1%')
  WHERE tax_name LIKE '%7.7%%';
UPDATE tax_profiles SET tax_name = REPLACE(tax_name, '2.5%', '2.6%')
  WHERE tax_name LIKE '%2.5%%';
UPDATE tax_profiles SET tax_name = REPLACE(tax_name, '3.7%', '3.8%')
  WHERE tax_name LIKE '%3.7%%';
