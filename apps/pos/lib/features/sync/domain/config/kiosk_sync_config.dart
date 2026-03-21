/// Sync configuration for the Kiosk flavor.
///
/// Kiosk devices are customer-facing self-ordering terminals. They submit
/// new orders to the cloud (which the POS and KDS then pick up) and need
/// a current copy of the menu including availability / stock status.
///
/// Push to cloud:
///   - tickets       — customer orders placed at the kiosk
///   - order_items   — items within kiosk orders
///
/// Pull from cloud:
///   - products      — menu items including is_active / stock availability
///   - categories    — category visibility and display order
///   - product_prices — price overrides (happy hour, kiosk-specific pricing)
///   - product_specifications — allergen / nutritional info shown at kiosk
///   - modifiers, modifier_groups, product_modifier_groups — customisation
library;

import 'sync_config.dart';

const kioskSyncConfig = SyncConfig(
  deviceType: SyncDeviceType.kiosk,
  pushEntities: {
    'tickets',
    'order_items',
  },
  pullEntities: {
    'products',
    'categories',
    'product_prices',
    'product_specifications',
    'modifiers',
    'modifier_groups',
    'product_modifier_groups',
  },
);
