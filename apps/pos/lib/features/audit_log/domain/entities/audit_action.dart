/// All auditable actions in GastroCore POS.
///
/// Each constant maps to an [AuditLogEntry.action] string stored in the DB.
/// The [label] is a human-readable description shown in the Audit Log screen.
enum AuditAction {
  // Orders
  orderCreated('Order Created'),
  orderEdited('Order Edited'),
  orderCancelled('Order Cancelled'),
  orderVoided('Order Voided'),
  itemVoided('Item Voided'),

  // Payments
  paymentReceived('Payment Received'),
  paymentRefunded('Payment Refunded'),
  itemRefunded('Item Refunded'),

  // Discounts
  discountApplied('Discount Applied'),

  // Shifts & Day close
  shiftOpened('Shift Opened'),
  shiftClosed('Shift Closed'),
  dayOpened('Day Opened'),
  dayClosed('Day Closed'),

  // Prices
  priceChanged('Price Changed'),

  // Menu availability (sold-out / 86'd toggle — operator-facing and loggable
  // because it can hide revenue-bearing products from the POS grid).
  productAvailabilityChanged('Product Availability Changed'),

  // Auth
  userLoggedIn('User Logged In'),
  userLoggedOut('User Logged Out'),

  // Manager operations
  managerOverride('Manager Override'),

  // Settings
  settingChanged('Setting Changed'),

  // Cash drawer
  cashDrawerOpened('Cash Drawer Opened'),

  // Backup
  backupCreated('Backup Created'),
  backupRestored('Backup Restored');

  const AuditAction(this.label);

  final String label;

  static AuditAction fromString(String value) {
    return AuditAction.values.firstWhere(
      (a) => a.name == value,
      orElse: () => AuditAction.orderEdited,
    );
  }
}
