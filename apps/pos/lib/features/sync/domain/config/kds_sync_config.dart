/// Sync configuration for the KDS (Kitchen Display System) flavor.
///
/// KDS is read-only from a business-logic perspective: it receives kitchen
/// tickets from the POS/Waiter and lets kitchen staff mark items as
/// preparing → ready. It pushes back only status updates on
/// kitchen_tickets / kitchen_ticket_items.
///
/// Push to cloud:
///   - kitchen_tickets       — status updates (preparing, ready, done)
///   - kitchen_ticket_items  — per-item status updates
///
/// Pull from cloud:
///   - kitchen_tickets, kitchen_ticket_items  — new print jobs from POS/Waiter
///   - products                               — to display item names / icons
///   - order_items                            — for allergy / modifier notes
library;

import 'sync_config.dart';

const kdsSyncConfig = SyncConfig(
  deviceType: SyncDeviceType.kds,
  pushEntities: {
    'kitchen_tickets',
    'kitchen_ticket_items',
  },
  pullEntities: {
    'kitchen_tickets',
    'kitchen_ticket_items',
    'products',
    'order_items',
  },
);
