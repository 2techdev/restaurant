-- Drop materialized views first
DROP MATERIALIZED VIEW IF EXISTS mv_product_performance;
DROP MATERIALIZED VIEW IF EXISTS mv_daily_sales;

-- Drop trigger function
DROP FUNCTION IF EXISTS update_updated_at() CASCADE;

-- Drop cloud-only tables
DROP TABLE IF EXISTS api_keys;
DROP TABLE IF EXISTS sync_batches;
DROP TABLE IF EXISTS tenant_subscriptions;
DROP TABLE IF EXISTS device_registrations;

-- Drop audit log
DROP TABLE IF EXISTS audit_log;

-- Drop receipts
DROP TABLE IF EXISTS receipts;

-- Drop kitchen
DROP TABLE IF EXISTS kitchen_ticket_items;
DROP TABLE IF EXISTS kitchen_tickets;

-- Drop cash movements
DROP TABLE IF EXISTS cash_movements;

-- Drop shifts
DROP TABLE IF EXISTS shifts;

-- Drop payments and bills
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS bills;

-- Drop order items
DROP TABLE IF EXISTS order_item_modifiers;
DROP TABLE IF EXISTS order_items;

-- Drop tickets
DROP TABLE IF EXISTS tickets;

-- Drop tables and floors
DROP TABLE IF EXISTS restaurant_tables;
DROP TABLE IF EXISTS floors;

-- Drop modifiers
DROP TABLE IF EXISTS product_modifier_groups;
DROP TABLE IF EXISTS modifiers;
DROP TABLE IF EXISTS modifier_groups;

-- Drop products and categories
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS categories;

-- Drop users
DROP TABLE IF EXISTS users;

-- Drop tenants
DROP TABLE IF EXISTS tenants;

-- Drop extension
DROP EXTENSION IF EXISTS "uuid-ossp";
