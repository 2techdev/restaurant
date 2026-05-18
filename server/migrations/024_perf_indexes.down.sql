-- Migration 024 rollback: drop performance indexes.

DROP INDEX IF EXISTS idx_sync_batches_tenant_created;
DROP INDEX IF EXISTS idx_shifts_open;
DROP INDEX IF EXISTS idx_payments_ticket_paid_at;
DROP INDEX IF EXISTS idx_audit_log_user_timestamp;
DROP INDEX IF EXISTS idx_notifications_tenant_unread;
DROP INDEX IF EXISTS idx_menu_sync_events_tenant_hash;
DROP INDEX IF EXISTS idx_products_category_displayorder;
DROP INDEX IF EXISTS idx_bills_tenant_status_paid_at;
DROP INDEX IF EXISTS idx_order_items_ticket_status;
DROP INDEX IF EXISTS idx_tickets_tenant_status_created;
