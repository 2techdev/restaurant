/// Sync configuration for the POS flavor.
///
/// POS is the primary order-creation device.
///
/// Push to cloud:
///   - tickets, order_items, order_item_modifiers  — created / modified locally
///   - payments, bills                              — payment records
///   - kitchen_tickets, kitchen_ticket_items        — kitchen print jobs
///   - shifts, cash_movements, receipts             — cashiering
///   - restaurant_tables                            — table status updates
///
/// Pull from cloud:
///   - products, categories, modifiers, modifier_groups,
///     product_modifier_groups, product_prices, product_specifications,
///     combo_items                                  — menu data from back-office
///   - tax_profiles, order_type_rules               — pricing rules
///   - users                                        — staff accounts
///   - restaurant_tables                            — table status from waiters
library;

import 'sync_config.dart';

const posSyncConfig = SyncConfig(
  deviceType: SyncDeviceType.pos,
  pushEntities: {
    'tickets',
    'order_items',
    'order_item_modifiers',
    'payments',
    'bills',
    'kitchen_tickets',
    'kitchen_ticket_items',
    'shifts',
    'cash_movements',
    'receipts',
    'restaurant_tables',
  },
  pullEntities: {
    'products',
    'categories',
    'modifier_groups',
    'modifiers',
    'product_modifier_groups',
    'product_prices',
    'product_specifications',
    'combo_items',
    'tax_profiles',
    'order_type_rules',
    'users',
    'restaurant_tables',
  },
);
