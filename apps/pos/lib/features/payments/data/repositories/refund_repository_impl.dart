/// Drift-backed repository for refund (iade) operations.
///
/// Supports partial refunds (selected items) and full order refunds.
/// Every refund:
///  1. Calculates the refund total from selected items.
///  2. Creates a negative payment record (refund transaction).
///  3. Writes a receipt record with type='refund'.
///  4. Writes an audit log entry.
///  5. Returns a [RefundResult] for caller use.
///
/// Manager override must be verified **before** calling [processRefund].
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';

// ---------------------------------------------------------------------------
// Refund reason constants
// ---------------------------------------------------------------------------

/// Standard refund reasons presented to the cashier.
const kRefundReasons = [
  'Müşteri Memnuniyetsizliği',
  'Yanlış Ürün Gönderildi',
  'Kalite Sorunu',
  'Müşteri İptali',
  'Diğer',
];

// ---------------------------------------------------------------------------
// RefundResult
// ---------------------------------------------------------------------------

class RefundResult {
  final String ticketId;
  final int refundAmount; // cents, positive value
  final List<String> refundedItemIds;
  final String receiptId;
  final String auditLogId;

  const RefundResult({
    required this.ticketId,
    required this.refundAmount,
    required this.refundedItemIds,
    required this.receiptId,
    required this.auditLogId,
  });
}

// ---------------------------------------------------------------------------
// RefundRepositoryImpl
// ---------------------------------------------------------------------------

class RefundRepositoryImpl {
  final AppDatabase _db;

  RefundRepositoryImpl(this._db);

  // =========================================================================
  // Process refund
  // =========================================================================

  /// Process a refund for the given [ticketId].
  ///
  /// - [orderItemIds]: item IDs to refund. Empty list = full order refund.
  /// - [reason]: mandatory reason string.
  /// - [refundMethodStr]: 'original' | 'cash'. Recorded in the payment row.
  /// - [approvedByUserId]: verified manager/admin who authorised this.
  /// - [requestedByUserId]: cashier who initiated the request.
  Future<RefundResult> processRefund({
    required String ticketId,
    required String tenantId,
    required String deviceId,
    required List<String> orderItemIds,
    required String reason,
    required String refundMethodStr,
    required String approvedByUserId,
    required String requestedByUserId,
    String? notes,
    double taxRate = 0.10,
  }) async {
    late RefundResult result;

    await _db.transaction(() async {
      final now = DateTime.now();

      // 1. Load the ticket.
      final ticket = await (_db.select(_db.tickets)
            ..where((t) => t.id.equals(ticketId)))
          .getSingleOrNull();
      if (ticket == null) throw StateError('Ticket $ticketId not found');

      // 2. Determine which items to refund.
      List<OrderItem> items;
      if (orderItemIds.isEmpty) {
        // Full order refund.
        items = await (_db.select(_db.orderItems)
              ..where(
                (i) =>
                    i.ticketId.equals(ticketId) &
                    i.isDeleted.equals(false) &
                    i.status.isNotIn(['void']),
              ))
            .get();
      } else {
        items = await (_db.select(_db.orderItems)
              ..where((i) => i.id.isIn(orderItemIds) & i.isDeleted.equals(false)))
            .get();
      }

      // 3. Calculate refund total.
      final refundSubtotal = items.fold<int>(0, (s, i) => s + i.subtotal);
      final refundTax = items.fold<int>(0, (s, i) => s + i.taxAmount);
      final refundTotal = refundSubtotal + refundTax;

      // 4. Find or create a bill for this ticket.
      final existingBills = await (_db.select(_db.bills)
            ..where(
              (b) =>
                  b.ticketId.equals(ticketId) &
                  b.isDeleted.equals(false),
            )
            ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
          .get();

      String billId;
      if (existingBills.isNotEmpty) {
        billId = existingBills.first.id;
      } else {
        // Create bill from ticket totals.
        final countExpr = _db.bills.id.count();
        final countResult = await (_db.selectOnly(_db.bills)
              ..addColumns([countExpr])
              ..where(_db.bills.tenantId.equals(tenantId)))
            .getSingle();
        final billNumber = (countResult.read(countExpr) ?? 0) + 1;
        billId = IdGenerator.generateId();

        await _db.into(_db.bills).insert(
              BillsCompanion(
                id: Value(billId),
                tenantId: Value(tenantId),
                ticketId: Value(ticketId),
                billNumber: Value(billNumber),
                subtotal: Value(ticket.subtotal),
                taxAmount: Value(ticket.taxAmount),
                discountAmount: Value(ticket.discountAmount),
                total: Value(ticket.total),
                status: const Value('fully_paid'),
                createdAt: Value(now),
                updatedAt: Value(now),
                isDeleted: const Value(false),
                syncStatus: const Value(0),
              ),
            );
      }

      // 5. Create a refund payment record (negative amount convention:
      //    we store the absolute value and use receipt type to denote refund).
      final paymentId = IdGenerator.generateId();
      await _db.into(_db.payments).insert(
            PaymentsCompanion(
              id: Value(paymentId),
              tenantId: Value(tenantId),
              billId: Value(billId),
              ticketId: Value(ticketId),
              paymentMethod: Value(
                  refundMethodStr == 'cash' ? 'cash' : 'credit_card'),
              amount: Value(-refundTotal), // negative signals refund
              tipAmount: const Value(0),
              tenderedAmount: Value(refundTotal),
              changeAmount: const Value(0),
              reference: Value('REFUND-${IdGenerator.generateId().substring(0, 8).toUpperCase()}'),
              receivedBy: Value(approvedByUserId),
              paidAt: Value(now),
              createdAt: Value(now),
              updatedAt: Value(now),
              isDeleted: const Value(false),
              syncStatus: const Value(0),
            ),
          );

      // 6. Create a receipt record.
      final receiptId = IdGenerator.generateId();
      final receiptContent = _buildReceiptJson(
        ticketId: ticketId,
        items: items,
        refundTotal: refundTotal,
        reason: reason,
        approvedBy: approvedByUserId,
        method: refundMethodStr,
        timestamp: now,
      );

      await _db.into(_db.receipts).insert(
            ReceiptsCompanion(
              id: Value(receiptId),
              tenantId: Value(tenantId),
              ticketId: Value(ticketId),
              billId: Value(billId),
              receiptNumber: Value(
                  IdGenerator.generateReceiptNumber(now, paymentId.hashCode.abs() % 9999 + 1)),
              receiptType: const Value('refund'),
              content: Value(receiptContent),
              printedAt: Value(now),
              printCount: const Value(0),
              createdAt: Value(now),
              syncStatus: const Value(0),
            ),
          );

      // 7. Audit log.
      final auditId = IdGenerator.generateId();
      await _db.into(_db.auditLog).insert(
            AuditLogCompanion(
              id: Value(auditId),
              tenantId: Value(tenantId),
              deviceId: Value(deviceId),
              userId: Value(approvedByUserId),
              userName: Value(approvedByUserId),
              entityType: Value(
                  orderItemIds.isEmpty ? 'ticket' : 'order_item'),
              entityId: Value(ticketId),
              action: Value(orderItemIds.isEmpty
                  ? 'override:refund_ticket'
                  : 'override:refund_item'),
              newValueJson: Value(_encodeJson({
                'requestedBy': requestedByUserId,
                'approvedBy': approvedByUserId,
                'reason': reason,
                if (notes != null) 'notes': notes,
                'refundTotal': refundTotal,
                'itemCount': items.length,
                'method': refundMethodStr,
              })),
              timestamp: Value(now),
            ),
          );

      result = RefundResult(
        ticketId: ticketId,
        refundAmount: refundTotal,
        refundedItemIds: items.map((i) => i.id).toList(),
        receiptId: receiptId,
        auditLogId: auditId,
      );
    });

    return result;
  }

  // =========================================================================
  // Helpers
  // =========================================================================

  String _buildReceiptJson({
    required String ticketId,
    required List<OrderItem> items,
    required int refundTotal,
    required String reason,
    required String approvedBy,
    required String method,
    required DateTime timestamp,
  }) {
    final itemList = items
        .map((i) =>
            '{"name":"${i.productName}","qty":${i.quantity},"amount":${i.subtotal}}')
        .join(',');

    return '{"type":"refund","ticketId":"$ticketId","reason":"${reason.replaceAll('"', '\\"')}",'
        '"method":"$method","approvedBy":"$approvedBy",'
        '"total":$refundTotal,"items":[$itemList],'
        '"timestamp":"${timestamp.toIso8601String()}"}';
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
