/// Drift-backed repository for refund (iade / Swiss "Storno") operations.
///
/// Supports partial refunds (selected items) and full order refunds.
/// Every refund:
///  1. Validates inputs — reason must be non-blank, approver must be set.
///  2. Calculates the refund total from selected items.
///  3. Creates a negative payment record (refund transaction).
///  4. Writes a storno receipt record with type='refund' that references
///     the original bill / receipt number (Swiss MWST audit requirement —
///     every storno slip must trace back to the original sale receipt).
///  5. Writes an [AuditAction.paymentRefunded] or [AuditAction.itemRefunded]
///     row with BOTH requester + approver populated (managerId/managerName),
///     so downstream CSV export and report filters pick it up under the
///     proper enum category rather than a raw string bucket.
///  6. Returns a [RefundResult] for caller use.
///
/// Manager override must be verified **before** calling [processRefund].
/// The caller is also expected to invoke
/// [ManagerOverrideNotifier.logOverride] for the per-tenant override log —
/// this repository does NOT write to that table, only the audit log.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';

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
// Errors
// ---------------------------------------------------------------------------

class RefundReasonRequiredException implements Exception {
  const RefundReasonRequiredException();
  @override
  String toString() => 'Refund reason is required (Swiss storno compliance)';
}

// ---------------------------------------------------------------------------
// RefundResult
// ---------------------------------------------------------------------------

class RefundResult {
  final String ticketId;
  final int refundAmount; // cents, positive value
  final List<String> refundedItemIds;
  final String receiptId;
  final String stornoReceiptNumber;
  final String? originalReceiptNumber;
  final String auditLogId;

  const RefundResult({
    required this.ticketId,
    required this.refundAmount,
    required this.refundedItemIds,
    required this.receiptId,
    required this.stornoReceiptNumber,
    required this.originalReceiptNumber,
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
  /// - [reason]: MANDATORY reason string. A blank / whitespace-only reason
  ///   throws [RefundReasonRequiredException] — required for Swiss storno
  ///   compliance.
  /// - [refundMethodStr]: 'original' | 'cash'. Recorded in the payment row.
  /// - [approver]: manager/admin who verified the PIN. Both id and name
  ///   are written into the audit log row for traceability.
  /// - [requester]: cashier who initiated the request.
  Future<RefundResult> processRefund({
    required String ticketId,
    required String tenantId,
    required String deviceId,
    required List<String> orderItemIds,
    required String reason,
    required String refundMethodStr,
    required UserEntity approver,
    required UserEntity requester,
    String? notes,
  }) async {
    if (reason.trim().isEmpty) {
      throw const RefundReasonRequiredException();
    }

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

      // 4b. Look up the ORIGINAL sale receipt for this bill so the storno
      //     slip can reference it. Missing original is non-fatal (offline
      //     receipt might not yet have been created) — we just omit the
      //     cross-reference in that case.
      final originalReceipts = await (_db.select(_db.receipts)
            ..where((r) =>
                r.billId.equals(billId) &
                r.receiptType.equals('sale'))
            ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
          .get();
      final originalReceipt =
          originalReceipts.isNotEmpty ? originalReceipts.first : null;

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
              reference: Value(
                  'STORNO-${IdGenerator.generateId().substring(0, 8).toUpperCase()}'),
              receivedBy: Value(approver.id),
              paidAt: Value(now),
              createdAt: Value(now),
              updatedAt: Value(now),
              isDeleted: const Value(false),
              syncStatus: const Value(0),
            ),
          );

      // 6. Create a storno receipt record that references the original sale.
      //    Reserve the receipt number from the per-tenant atomic counter
      //    (Swiss fiscal compliance — no duplicates, no gaps by accident).
      final receiptId = IdGenerator.generateId();
      final sequence = await _db.receiptCounterDao.nextReceiptNumber(tenantId);
      final stornoReceiptNumber =
          IdGenerator.generateReceiptNumber(now, sequence);
      final receiptContent = buildStornoReceiptJson(
        ticketId: ticketId,
        billId: billId,
        originalReceiptId: originalReceipt?.id,
        originalReceiptNumber: originalReceipt?.receiptNumber,
        stornoReceiptNumber: stornoReceiptNumber,
        items: items
            .map((i) => StornoLineJson(
                  productName: i.productName,
                  quantity: i.quantity,
                  subtotal: i.subtotal,
                  taxAmount: i.taxAmount,
                ))
            .toList(growable: false),
        subtotal: refundSubtotal,
        taxAmount: refundTax,
        refundTotal: refundTotal,
        reason: reason.trim(),
        notes: notes?.trim().isEmpty ?? true ? null : notes!.trim(),
        approvedByUserId: approver.id,
        approvedByName: approver.name,
        requestedByUserId: requester.id,
        requestedByName: requester.name,
        method: refundMethodStr,
        timestamp: now,
      );

      await _db.into(_db.receipts).insert(
            ReceiptsCompanion(
              id: Value(receiptId),
              tenantId: Value(tenantId),
              ticketId: Value(ticketId),
              billId: Value(billId),
              receiptNumber: Value(stornoReceiptNumber),
              receiptType: const Value('refund'),
              content: Value(receiptContent),
              printedAt: Value(now),
              printCount: const Value(0),
              createdAt: Value(now),
              syncStatus: const Value(0),
            ),
          );

      // 7. Audit log — enum action + manager fields populated.
      final auditId = IdGenerator.generateId();
      final auditAction = orderItemIds.isEmpty
          ? AuditAction.paymentRefunded
          : AuditAction.itemRefunded;
      await _db.into(_db.auditLog).insert(
            AuditLogCompanion(
              id: Value(auditId),
              tenantId: Value(tenantId),
              deviceId: Value(deviceId),
              // The requester acted; the manager authorised.
              userId: Value(requester.id),
              userName: Value(requester.name),
              managerId: Value(approver.id),
              managerName: Value(approver.name),
              action: Value(auditAction.name),
              entityType: Value(
                  orderItemIds.isEmpty ? 'ticket' : 'order_item'),
              entityId: Value(ticketId),
              reason: Value(reason.trim()),
              newValueJson: Value(jsonEncode({
                'ticketId': ticketId,
                'billId': billId,
                'originalReceiptId': originalReceipt?.id,
                'originalReceiptNumber': originalReceipt?.receiptNumber,
                'stornoReceiptId': receiptId,
                'stornoReceiptNumber': stornoReceiptNumber,
                'refundTotal': refundTotal,
                'refundSubtotal': refundSubtotal,
                'refundTax': refundTax,
                'itemCount': items.length,
                'method': refundMethodStr,
                if (notes != null && notes.trim().isNotEmpty)
                  'notes': notes.trim(),
              })),
              timestamp: Value(now),
            ),
          );

      result = RefundResult(
        ticketId: ticketId,
        refundAmount: refundTotal,
        refundedItemIds: items.map((i) => i.id).toList(),
        receiptId: receiptId,
        stornoReceiptNumber: stornoReceiptNumber,
        originalReceiptNumber: originalReceipt?.receiptNumber,
        auditLogId: auditId,
      );
    });

    return result;
  }

  // =========================================================================
  // Public helpers (exposed for unit testing the serialisation shape)
  // =========================================================================

  /// Build the storno receipt content JSON. Pure function, no DB access.
  ///
  /// Swiss MWST audit rules require the storno slip to carry:
  ///   * the storno receipt number (own running number),
  ///   * the ORIGINAL receipt number / id (traceability),
  ///   * the refund reason,
  ///   * the cashier who requested + the manager who authorised,
  ///   * per-line items plus subtotal + tax + total,
  ///   * timestamp in ISO-8601.
  static String buildStornoReceiptJson({
    required String ticketId,
    required String billId,
    required String? originalReceiptId,
    required String? originalReceiptNumber,
    required String stornoReceiptNumber,
    required List<StornoLineJson> items,
    required int subtotal,
    required int taxAmount,
    required int refundTotal,
    required String reason,
    required String? notes,
    required String approvedByUserId,
    required String approvedByName,
    required String requestedByUserId,
    required String requestedByName,
    required String method,
    required DateTime timestamp,
  }) {
    return jsonEncode({
      'type': 'storno',
      'stornoReceiptNumber': stornoReceiptNumber,
      'originalReceiptId': originalReceiptId,
      'originalReceiptNumber': originalReceiptNumber,
      'ticketId': ticketId,
      'billId': billId,
      'reason': reason,
      if (notes != null) 'notes': notes,
      'requestedBy': {
        'id': requestedByUserId,
        'name': requestedByName,
      },
      'approvedBy': {
        'id': approvedByUserId,
        'name': approvedByName,
      },
      'method': method,
      'items': items
          .map((l) => {
                'name': l.productName,
                'qty': l.quantity,
                'subtotal': l.subtotal,
                'tax': l.taxAmount,
              })
          .toList(),
      'subtotal': subtotal,
      'tax': taxAmount,
      'total': refundTotal,
      'timestamp': timestamp.toIso8601String(),
    });
  }
}

/// Single line item used when constructing the storno receipt payload.
/// Declared outside the repository so unit tests can build fixtures.
class StornoLineJson {
  const StornoLineJson({
    required this.productName,
    required this.quantity,
    required this.subtotal,
    required this.taxAmount,
  });

  final String productName;
  final double quantity;
  final int subtotal;
  final int taxAmount;
}
