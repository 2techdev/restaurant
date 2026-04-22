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

  // Tables — merge one occupied table's ticket into another. Needs its
  // own action because a merge touches two tickets + two tables and the
  // reason text carries the source/target pair.
  tableMerged('Table Merged'),

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

  // CRM — customer attached to an open ticket or detached from it.
  customerLinkedToTicket('Customer Linked To Ticket'),

  // Loyalty — puan cashed at settlement. Logged against the customer so
  // the daily close report can explain every revenue deduction.
  loyaltyRedeemed('Loyalty Redeemed'),

  // Receipt reprint — Swiss tax compliance trail for every extra copy of a
  // settled receipt. The first print fired directly out of the payment flow
  // is NOT audited here; only reprints (repeated prints or prints of an
  // already-completed ticket opened from history) fire this action.
  receiptReprinted('Receipt Reprinted'),

  // Auth
  userLoggedIn('User Logged In'),
  userLoggedOut('User Logged Out'),

  // Shift clock — waiter-level time tracking, separate from session login.
  // A single terminal session can span many clock-in / clock-out cycles
  // (lock screen, cash relief, etc.), so these actions are ONLY emitted
  // by explicit Mesai (shift) buttons, never by PIN login/logout.
  userClockedIn('User Clocked In'),
  userClockedOut('User Clocked Out'),

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
