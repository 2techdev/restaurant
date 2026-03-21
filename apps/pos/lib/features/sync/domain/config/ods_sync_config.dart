/// Sync configuration for the ODS (Order Display Screen) flavor.
///
/// ODS is a pure read-only display mounted at the counter that shows
/// orders moving from "Preparing" to "Ready for pickup". It never pushes
/// any data — it only pulls ticket / order status changes in real time.
///
/// Push to cloud:  (none)
///
/// Pull from cloud:
///   - tickets      — order numbers and overall status
///   - order_items  — per-item status (preparing → ready → served)
library;

import 'sync_config.dart';

const odsSyncConfig = SyncConfig(
  deviceType: SyncDeviceType.ods,
  pushEntities: {},
  pullEntities: {
    'tickets',
    'order_items',
  },
);
