-- Migration 024: performance-tuning indexes
--
-- Adds composite indexes hot paths (list/paginate/aggregate) hit but
-- existing single-column indexes don't cover. Target query patterns:
--
--   1. tickets list by tenant + status, sorted by created_at desc
--   2. order_items by ticket + status (KDS lane filtering)
--   3. bills list by tenant + status + paid_at
--   4. products in a category sorted by display_order
--   5. menu_sync_events idempotency lookup on (tenant, payload_hash)
--   6. notifications inbox by tenant + read_at NULL
--   7. audit_log filter by entity for compliance lookups
--
-- All statements are CREATE INDEX IF NOT EXISTS so the migration is
-- idempotent and safe to re-apply over partial runs.
--
-- Note: a future prod-scale migration should switch to CREATE INDEX
-- CONCURRENTLY (which cannot run inside the migrator's wrapping txn).
-- Pilot tenant sizes are small enough that blocking CREATE INDEX is OK
-- (sub-second on ~10k rows).

-- 1. tickets(tenant, status, created_at desc) — covers ?status=open & date-paginated lists
CREATE INDEX IF NOT EXISTS idx_tickets_tenant_status_created
  ON tickets(tenant_id, status, created_at DESC)
  WHERE is_deleted = FALSE;

-- 2. order_items(ticket, status) — KDS lane / served check
CREATE INDEX IF NOT EXISTS idx_order_items_ticket_status
  ON order_items(ticket_id, status);

-- 3. bills(tenant, status, paid_at desc) — reports + admin list
CREATE INDEX IF NOT EXISTS idx_bills_tenant_status_paid_at
  ON bills(tenant_id, status, paid_at DESC);

-- 4. products by category — menu reads sorted by display_order
CREATE INDEX IF NOT EXISTS idx_products_category_displayorder
  ON products(tenant_id, category_id, display_order)
  WHERE is_deleted = FALSE;

-- 5. menu_sync_events idempotency — applyImport short-circuit hits this
--    on every retry; without it the seq scan grows linearly with imports
CREATE INDEX IF NOT EXISTS idx_menu_sync_events_tenant_hash
  ON menu_sync_events(tenant_id, payload_hash);

-- 6. notifications inbox (table exists from migration 016)
CREATE INDEX IF NOT EXISTS idx_notifications_tenant_unread
  ON notifications(tenant_id, created_at DESC)
  WHERE read_at IS NULL;

-- 7. audit_log entity lookups already have idx_audit_log_entity. Add
--    user+timestamp for "what did user X do this week" admin queries.
CREATE INDEX IF NOT EXISTS idx_audit_log_user_timestamp
  ON audit_log(user_id, timestamp DESC)
  WHERE user_id IS NOT NULL;

-- 8. payments by ticket — settlement lookup hits this every receipt print
CREATE INDEX IF NOT EXISTS idx_payments_ticket_paid_at
  ON payments(ticket_id, paid_at DESC);

-- 9. shifts open lookup — getCurrentShift in every order flow
CREATE INDEX IF NOT EXISTS idx_shifts_open
  ON shifts(tenant_id, user_id, opened_at DESC)
  WHERE status = 'open';

-- 10. sync_batches recent — sync UI shows last N batches per tenant
CREATE INDEX IF NOT EXISTS idx_sync_batches_tenant_created
  ON sync_batches(tenant_id, created_at DESC);
