-- Reverse of migration 037 — drop child table first (FK) then parent.
DROP TABLE IF EXISTS order_profile_pricing_rules;
DROP TABLE IF EXISTS order_profiles;
