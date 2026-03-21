/// Override action types and the OverrideLogEntity domain object.
///
/// An "override" is any privileged operation that requires approval from a
/// user whose [UserRole] grants the relevant permission (manager or admin).
/// Every override is recorded in the audit log for full traceability.
library;

import 'dart:convert';

// ---------------------------------------------------------------------------
// OverrideAction enum
// ---------------------------------------------------------------------------

/// The type of operation that triggered a manager override request.
enum OverrideAction {
  /// Cancel a single order item (partial void).
  voidItem,

  /// Cancel an entire ticket before or after payment.
  voidTicket,

  /// Refund one or more items from a completed order.
  refundItem,

  /// Full refund of a completed order.
  refundTicket,

  /// Apply a percentage-based discount to an order.
  discountPercent,

  /// Apply a fixed-amount discount to an order.
  discountFixed,

  /// Override the unit price of an order item.
  priceChange,
}

/// Human-readable display labels for [OverrideAction].
extension OverrideActionLabel on OverrideAction {
  String get label => switch (this) {
        OverrideAction.voidItem => 'Ürün İptali',
        OverrideAction.voidTicket => 'Sipariş İptali',
        OverrideAction.refundItem => 'Kısmi İade',
        OverrideAction.refundTicket => 'Tam İade',
        OverrideAction.discountPercent => 'Yüzde İndirim',
        OverrideAction.discountFixed => 'Tutar İndirim',
        OverrideAction.priceChange => 'Fiyat Değişikliği',
      };

  /// Serialised string stored in AuditLog.action column.
  String get auditKey => switch (this) {
        OverrideAction.voidItem => 'override:void_item',
        OverrideAction.voidTicket => 'override:void_ticket',
        OverrideAction.refundItem => 'override:refund_item',
        OverrideAction.refundTicket => 'override:refund_ticket',
        OverrideAction.discountPercent => 'override:discount_percent',
        OverrideAction.discountFixed => 'override:discount_fixed',
        OverrideAction.priceChange => 'override:price_change',
      };

  static OverrideAction fromAuditKey(String key) {
    return switch (key) {
      'override:void_item' => OverrideAction.voidItem,
      'override:void_ticket' => OverrideAction.voidTicket,
      'override:refund_item' => OverrideAction.refundItem,
      'override:refund_ticket' => OverrideAction.refundTicket,
      'override:discount_percent' => OverrideAction.discountPercent,
      'override:discount_fixed' => OverrideAction.discountFixed,
      'override:price_change' => OverrideAction.priceChange,
      _ => OverrideAction.voidTicket,
    };
  }
}

// ---------------------------------------------------------------------------
// Permission helpers
// ---------------------------------------------------------------------------

/// Roles that can approve override requests.
const _managerRoles = {'admin', 'manager'};

/// Whether [roleName] is allowed to approve overrides (manager or admin).
bool canApproveOverride(String roleName) => _managerRoles.contains(roleName);

// ---------------------------------------------------------------------------
// OverrideLogEntity
// ---------------------------------------------------------------------------

/// Immutable record of a completed manager override.
///
/// Backed by a row in the [AuditLog] table with
/// `entityType = 'override'` and `action = overrideAction.auditKey`.
class OverrideLogEntity {
  final String id;
  final String tenantId;
  final String deviceId;

  /// The staff member who requested the override (cashier / waiter).
  final String requestedByUserId;
  final String requestedByName;

  /// The manager / admin who approved by entering their PIN.
  final String approvedByUserId;
  final String approvedByName;

  /// The type of privileged operation.
  final OverrideAction action;

  /// 'ticket' | 'order_item' | 'bill'
  final String entityType;

  /// Primary key of the affected entity.
  final String entityId;

  /// Mandatory reason selected / entered by the cashier.
  final String reason;

  /// Optional free-text notes.
  final String? notes;

  /// Supplementary data (amounts, old/new values, etc.) encoded as JSON.
  final Map<String, dynamic> metadata;

  final DateTime timestamp;

  const OverrideLogEntity({
    required this.id,
    required this.tenantId,
    required this.deviceId,
    required this.requestedByUserId,
    required this.requestedByName,
    required this.approvedByUserId,
    required this.approvedByName,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.reason,
    this.notes,
    this.metadata = const {},
    required this.timestamp,
  });

  /// Serialise [metadata] to JSON string for database storage.
  String get metadataJson => jsonEncode({
        'requestedBy': requestedByUserId,
        'requestedByName': requestedByName,
        'approvedBy': approvedByUserId,
        'approvedByName': approvedByName,
        'reason': reason,
        if (notes != null) 'notes': notes,
        ...metadata,
      });

  @override
  String toString() =>
      'OverrideLogEntity(id: $id, action: ${action.auditKey}, entity: $entityId)';
}
