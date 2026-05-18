-- Down migration for 036_loyalty_giftcards.
-- Drops new tables; reverts customer columns and loyalty_transactions check.
-- Existing loyalty_transactions / customers.loyalty_points data is preserved.

DROP TABLE IF EXISTS gift_card_transactions;
DROP TABLE IF EXISTS gift_cards;
DROP TABLE IF EXISTS loyalty_bonus_campaigns;
DROP TABLE IF EXISTS loyalty_tiers;
DROP TABLE IF EXISTS loyalty_program_settings;

ALTER TABLE loyalty_transactions DROP CONSTRAINT IF EXISTS loyalty_transactions_type_check;

ALTER TABLE customers DROP COLUMN IF EXISTS tier_upgrade_at;
ALTER TABLE customers DROP COLUMN IF EXISTS current_tier;
ALTER TABLE customers DROP COLUMN IF EXISTS total_earned;

DROP INDEX IF EXISTS idx_customers_tenant_tier;
