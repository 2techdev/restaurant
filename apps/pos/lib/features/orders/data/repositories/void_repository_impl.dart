/// Drift-backed repository for void (iptal) operations.
///
/// Supports two void levels:
///  - [voidOrderItem] — partial void of a single line item.
///  - [voidTicket]   — full cancellation of a ticket (all items voided).
///
/// Both operations require a pre-verified [approvedByUserId] obtained via
/// [OverrideRepositoryImpl.verifyManagerPin]. They write an audit log entry
/// and update KDS items so the kitchen is informed.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';

// ---------------------------------------------------------------------------
// Void reason constants (used by the UI and stored in audit log)
// ---------------------------------------------------------------------------

/// Standard void reasons presented to the cashier.
const kVoidReasons = [
  'Müşteri İptali',
  'Yanlış Giriş',
  'Ürün Tükendi',
  'Müşteri Şikayeti',
  'Diğer',
];

// ---------------------------------------------------------------------------
// VoidResult
// ---------------------------------------------------------------------------

class VoidResult {
  final String ticketId;
  final List<String> voidedItemIds;
  final String auditLogId;

  const VoidResult({
    required this.ticketId,
    required this.voidedItemIds,
    required this.auditLogId,
  });
}

// ---------------------------------------------------------------------------
// VoidRepositoryImpl
// ---------------------------------------------------------------------------

class VoidRepositoryImpl {
  final AppDatabase _db;

  VoidRepositoryImpl(this._db);

  // =========================================================================
  // Partial void — single order item
  // =========================================================================

  /// Mark a single order item as voided and recalculate ticket totals.
  ///
  /// If the voided item was already sent to the kitchen, the corresponding
  /// KDS ticket item is updated to 'void' so the kitchen is notified.
  ///
  /// Returns a [VoidResult] for caller use (e.g. logging).
  Future<VoidResult> voidOrderItem({
    required String orderItemId,
    required String reason,
    required String approvedByUserId,
    required String requestedByUserId,
    required String tenantId,
    required String deviceId,
    String? notes,
  }) async {
    late VoidResult result;

    await _db.transaction(() async {
      // 1. Load the item.
      final itemRow = await (_db.select(_db.orderItems)
            ..where((i) => i.id.equals(orderItemId)))
          .getSingleOrNull();
      if (itemRow == null) {
        throw StateError('Order item $orderItemId not found');
      }

      // 2. Mark item as void.
      await (_db.update(_db.orderItems)
            ..where((i) => i.id.equals(orderItemId)))
          .write(
        OrderItemsCompanion(
          status: const Value('void'),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // 3. Update KDS item if it exists.
      await (_db.update(_db.kitchenTicketItems)
            ..where((k) => k.orderItemId.equals(orderItemId)))
          .write(
        KitchenTicketItemsCompanion(
          status: const Value('void'),
        ),
      );

      // 4. Recalculate ticket totals (excludes voided items).
      await _recalculateTicketTotals(itemRow.ticketId);

      // 5. Check if all remaining items are voided → void the whole ticket.
      await _maybeVoidTicket(itemRow.ticketId);

      // 6. Write audit log.
      final auditId = IdGenerator.generateId();
      await _writeAuditLog(
        id: auditId,
        tenantId: tenantId,
        deviceId: deviceId,
        userId: approvedByUserId,
        entityType: 'order_item',
        entityId: orderItemId,
        action: 'override:void_item',
        payload: {
          'requestedBy': requestedByUserId,
          'approvedBy': approvedByUserId,
          'reason': reason,
          if (notes != null) 'notes': notes,
          'ticketId': itemRow.ticketId,
          'productName': itemRow.productName,
        },
      );

      result = VoidResult(
        ticketId: itemRow.ticketId,
        voidedItemIds: [orderItemId],
        auditLogId: auditId,
      );
    });

    return result;
  }

  // =========================================================================
  // Full void — entire ticket
  // =========================================================================

  /// Void all active items on a ticket and transition the ticket to 'voided'.
  ///
  /// Associated bills are also set to 'void' status.
  Future<VoidResult> voidTicket({
    required String ticketId,
    required String reason,
    required String approvedByUserId,
    required String requestedByUserId,
    required String tenantId,
    required String deviceId,
    String? notes,
  }) async {
    late VoidResult result;

    await _db.transaction(() async {
      final now = DateTime.now();

      // 1. Load all active (non-deleted, non-void) items.
      final items = await (_db.select(_db.orderItems)
            ..where(
              (i) =>
                  i.ticketId.equals(ticketId) &
                  i.isDeleted.equals(false) &
                  i.status.isNotIn(['void']),
            ))
          .get();

      final voidedIds = items.map((i) => i.id).toList();

      // 2. Mark all items void.
      await (_db.update(_db.orderItems)
            ..where(
              (i) =>
                  i.ticketId.equals(ticketId) &
                  i.isDeleted.equals(false) &
                  i.status.isNotIn(['void']),
            ))
          .write(
        OrderItemsCompanion(
          status: const Value('void'),
          updatedAt: Value(now),
        ),
      );

      // 3. Void KDS tickets for this order.
      await (_db.update(_db.kitchenTickets)
            ..where((k) => k.ticketId.equals(ticketId)))
          .write(
        KitchenTicketsCompanion(
          status: const Value('void'),
        ),
      );

      // 4. Void KDS items: look up kitchen ticket IDs first, then void items.
      final kitchenTickets = await (_db.select(_db.kitchenTickets)
            ..where((k) => k.ticketId.equals(ticketId)))
          .get();
      if (kitchenTickets.isNotEmpty) {
        final ktIds = kitchenTickets.map((k) => k.id).toList();
        await (_db.update(_db.kitchenTicketItems)
              ..where((k) => k.kitchenTicketId.isIn(ktIds)))
            .write(
          KitchenTicketItemsCompanion(
            status: const Value('void'),
          ),
        );
      }

      // 5. Void the ticket itself.
      await (_db.update(_db.tickets)..where((t) => t.id.equals(ticketId)))
          .write(
        TicketsCompanion(
          status: const Value('voided'),
          closedAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // 6. Void associated bills (only open / partially paid).
      await (_db.update(_db.bills)
            ..where(
              (b) =>
                  b.ticketId.equals(ticketId) &
                  b.status.isIn(['open', 'partially_paid']),
            ))
          .write(
        BillsCompanion(
          status: const Value('void'),
          updatedAt: Value(now),
        ),
      );

      // 7. Write audit log.
      final auditId = IdGenerator.generateId();
      await _writeAuditLog(
        id: auditId,
        tenantId: tenantId,
        deviceId: deviceId,
        userId: approvedByUserId,
        entityType: 'ticket',
        entityId: ticketId,
        action: 'override:void_ticket',
        payload: {
          'requestedBy': requestedByUserId,
          'approvedBy': approvedByUserId,
          'reason': reason,
          if (notes != null) 'notes': notes,
          'itemCount': voidedIds.length,
        },
      );

      result = VoidResult(
        ticketId: ticketId,
        voidedItemIds: voidedIds,
        auditLogId: auditId,
      );
    });

    return result;
  }

  // =========================================================================
  // Private helpers
  // =========================================================================

  /// Recalculate ticket subtotal / tax / total from non-voided, non-deleted items.
  Future<void> _recalculateTicketTotals(String ticketId) async {
    final items = await (_db.select(_db.orderItems)
          ..where(
            (i) =>
                i.ticketId.equals(ticketId) &
                i.isDeleted.equals(false) &
                i.status.isNotIn(['void']),
          ))
        .get();

    final subtotal = items.fold<int>(0, (s, i) => s + i.subtotal);
    final taxAmount = items.fold<int>(0, (s, i) => s + i.taxAmount);

    // Preserve existing discount.
    final ticketRow = await (_db.select(_db.tickets)
          ..where((t) => t.id.equals(ticketId)))
        .getSingle();

    int discountAmount = 0;
    if (ticketRow.discountType == 'fixed' &&
        ticketRow.discountValue != null) {
      discountAmount = ticketRow.discountValue!.round();
    } else if (ticketRow.discountType == 'percentage' &&
        ticketRow.discountValue != null) {
      discountAmount = (subtotal * ticketRow.discountValue! / 100).round();
    }

    // 2026-05-14 KDV fix (same as `OrderRepositoryImpl.calculateTicketTotals`):
    // gross-inclusive prices — `taxAmount` is informational and must not
    // be re-added to the total. The void flow shares this pre-existing
    // bug; without the matching fix, voiding a line on a saved ticket
    // would recompute and re-inflate the total.
    final total = subtotal - discountAmount;

    await (_db.update(_db.tickets)..where((t) => t.id.equals(ticketId)))
        .write(
      TicketsCompanion(
        subtotal: Value(subtotal),
        taxAmount: Value(taxAmount),
        discountAmount: Value(discountAmount),
        total: Value(total < 0 ? 0 : total),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Auto-void the ticket if every item has been voided.
  Future<void> _maybeVoidTicket(String ticketId) async {
    final remaining = await (_db.select(_db.orderItems)
          ..where(
            (i) =>
                i.ticketId.equals(ticketId) &
                i.isDeleted.equals(false) &
                i.status.isNotIn(['void']),
          ))
        .get();

    if (remaining.isEmpty) {
      final now = DateTime.now();
      await (_db.update(_db.tickets)..where((t) => t.id.equals(ticketId)))
          .write(
        TicketsCompanion(
          status: const Value('voided'),
          closedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }
  }

  Future<void> _writeAuditLog({
    required String id,
    required String tenantId,
    required String deviceId,
    required String userId,
    String userName = '',
    required String entityType,
    required String entityId,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    await _db.into(_db.auditLog).insert(
          AuditLogCompanion(
            id: Value(id),
            tenantId: Value(tenantId),
            deviceId: Value(deviceId),
            userId: Value(userId),
            userName: Value(userName),
            entityType: Value(entityType),
            entityId: Value(entityId),
            action: Value(action),
            newValueJson: Value(_encodeJson(payload)),
            timestamp: Value(DateTime.now()),
          ),
        );
  }

  static String _encodeJson(Map<String, dynamic> map) {
    final buffer = StringBuffer('{');
    var first = true;
    for (final entry in map.entries) {
      if (!first) buffer.write(',');
      first = false;
      final value = entry.value;
      if (value is String) {
        buffer.write('"${entry.key}":"${value.replaceAll('"', '\\"')}"');
      } else {
        buffer.write('"${entry.key}":$value');
      }
    }
    buffer.write('}');
    return buffer.toString();
  }
}
