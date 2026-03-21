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

  // Payments
  paymentReceived('Payment Received'),
  paymentRefunded('Payment Refunded'),

  // Discounts
  discountApplied('Discount Applied'),

  // Shifts
  shiftOpened('Shift Opened'),
  shiftClosed('Shift Closed'),

  // Prices
  priceChanged('Price Changed'),

  // Auth
  userLoggedIn('User Logged In'),
  userLoggedOut('User Logged Out'),

  // Manager operations
  managerOverride('Manager Override'),

  // Settings
  settingChanged('Setting Changed'),

  // Cash drawer
  cashDrawerOpened('Cash Drawer Opened');

  const AuditAction(this.label);

  final String label;

  static AuditAction fromString(String value) {
    return AuditAction.values.firstWhere(
      (a) => a.name == value,
      orElse: () => AuditAction.orderEdited,
    );
  }
}
