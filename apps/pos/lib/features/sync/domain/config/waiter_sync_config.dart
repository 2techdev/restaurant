/// Sync configuration for the Waiter flavor.
///
/// Waiter devices run on staff phones/tablets and act as mobile POS
/// terminals: they create orders, update table status, and send items to
/// the kitchen. They also need up-to-date menu and floor-plan data.
///
/// Push to cloud:
///   - tickets, order_items, order_item_modifiers  — table-side orders
///   - restaurant_tables                            — table status changes
///   - kitchen_tickets, kitchen_ticket_items        — kitchen send events
///
/// Pull from cloud:
///   - products, categories, modifiers, modifier_groups,
///     product_modifier_groups, product_prices      — menu (refreshed on login)
///   - restaurant_tables                            — table status from POS
///   - tickets, order_items                         — active orders (shared view)
library;

import 'sync_config.dart';

const waiterSyncConfig = SyncConfig(
  deviceType: SyncDeviceType.waiter,
  pushEntities: {
    'tickets',
    'order_items',
    'order_item_modifiers',
    'restaurant_tables',
    'kitchen_tickets',
    'kitchen_ticket_items',
  },
  pullEntities: {
    'products',
    'categories',
    'modifier_groups',
    'modifiers',
    'product_modifier_groups',
    'product_prices',
    'restaurant_tables',
    'tickets',
    'order_items',
  },
);
