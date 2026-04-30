-- Rollback migration 018 — revert to pre-2024 Swiss VAT rates.
UPDATE tax_profiles SET tax_rate = 7.7 WHERE tax_rate = 8.1;
UPDATE tax_profiles SET tax_rate = 2.5 WHERE tax_rate = 2.6;
UPDATE tax_profiles SET tax_rate = 3.7 WHERE tax_rate = 3.8;
UPDATE tax_profiles SET tax_name = REPLACE(tax_name, '8.1%', '7.7%') WHERE tax_name LIKE '%8.1%%';
UPDATE tax_profiles SET tax_name = REPLACE(tax_name, '2.6%', '2.5%') WHERE tax_name LIKE '%2.6%%';
UPDATE tax_profiles SET tax_name = REPLACE(tax_name, '3.8%', '3.7%') WHERE tax_name LIKE '%3.8%%';
