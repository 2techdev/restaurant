/// Drift-backed implementation of the payment repository.
///
/// Manages bills and payments. The [processPayment] method orchestrates
/// the full payment flow: creating a bill when none exists, recording the
/// payment, updating the bill status, and transitioning the ticket to
/// completed when fully paid. All mutations run in a single transaction.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/payments/domain/entities/payment_entity.dart';

class PaymentRepositoryImpl {
  final AppDatabase _db;

  PaymentRepositoryImpl(this._db);

  // =========================================================================
  // Bills
  // =========================================================================

  /// Create a new bill row and return the hydrated [BillEntity].
  Future<BillEntity> createBill(BillEntity entity) async {
    await _db.into(_db.bills).insert(_billToCompanion(entity));
    return (await _getBillById(entity.id))!;
  }

  /// Return all bills associated with [ticketId].
  Future<List<BillEntity>> getBillsByTicket(String ticketId) async {
    final query = _db.select(_db.bills)
      ..where(
        (b) => b.ticketId.equals(ticketId) & b.isDeleted.equals(false),
      );
    final rows = await query.get();

    final results = <BillEntity>[];
    for (final row in rows) {
      final payments = await getPaymentsByBill(row.id);
      results.add(_billToEntity(row, payments));
    }
    return results;
  }

  // =========================================================================
  // Payments
  // =========================================================================

  /// Record a payment and return the persisted [PaymentEntity].
  Future<PaymentEntity> createPayment(PaymentEntity entity) async {
    await _db.into(_db.payments).insert(_paymentToCompanion(entity));
    return _paymentToEntity(
      (await (_db.select(_db.payments)
                ..where((p) => p.id.equals(entity.id)))
              .getSingle()),
    );
  }

  /// Return all payments for a given [billId].
  Future<List<PaymentEntity>> getPaymentsByBill(String billId) async {
    final query = _db.select(_db.payments)
      ..where(
        (p) => p.billId.equals(billId) & p.isDeleted.equals(false),
      )
      ..orderBy([(p) => OrderingTerm.asc(p.paidAt)]);
    final rows = await query.get();
    return rows.map(_paymentToEntity).toList();
  }

  // =========================================================================
  // Full payment flow
  // =========================================================================

  /// High-level payment processor.
  ///
  /// 1. If no open bill exists for [ticketId], one is created from the
  ///    ticket totals.
  /// 2. A [PaymentEntity] is recorded against the bill.
  /// 3. The bill status is updated (partially / fully paid).
  /// 4. When fully paid the ticket status transitions to "completed".
  ///
  /// All steps run inside a single database transaction.
  Future<PaymentEntity> processPayment({
    required String ticketId,
    required String tenantId,
    required PaymentMethod paymentMethod,
    required int amount,
    required int tenderedAmount,
    required String receivedBy,
    String? reference,
    int tipAmount = 0,
  }) async {
    late PaymentEntity result;

    await _db.transaction(() async {
      // --- Ensure a bill exists ---
      final existingBills = await (_db.select(_db.bills)
            ..where(
              (b) =>
                  b.ticketId.equals(ticketId) &
                  b.isDeleted.equals(false) &
                  b.status.isNotIn(['fully_paid', 'void']),
            ))
          .get();

      Bill billRow;
      if (existingBills.isNotEmpty) {
        billRow = existingBills.first;
      } else {
        // Create a bill from the ticket totals.
        final ticket = await (_db.select(_db.tickets)
              ..where((t) => t.id.equals(ticketId)))
            .getSingle();

        // Determine next bill number.
        final countExpr = _db.bills.id.count();
        final countQuery = _db.selectOnly(_db.bills)
          ..addColumns([countExpr])
          ..where(_db.bills.tenantId.equals(tenantId));
        final countResult = await countQuery.getSingle();
        final billNumber = (countResult.read(countExpr) ?? 0) + 1;

        final billId = IdGenerator.generateId();
        final now = DateTime.now();

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
                status: const Value('open'),
                createdAt: Value(now),
                updatedAt: Value(now),
                isDeleted: const Value(false),
                syncStatus: const Value(0),
              ),
            );

        billRow = await (_db.select(_db.bills)
              ..where((b) => b.id.equals(billId)))
            .getSingle();
      }

      // --- Record the payment ---
      final changeAmount = paymentMethod == PaymentMethod.cash
          ? (tenderedAmount - amount).clamp(0, tenderedAmount)
          : 0;

      final paymentId = IdGenerator.generateId();
      final now = DateTime.now();

      await _db.into(_db.payments).insert(
            PaymentsCompanion(
              id: Value(paymentId),
              tenantId: Value(tenantId),
              billId: Value(billRow.id),
              ticketId: Value(ticketId),
              paymentMethod: Value(_paymentMethodToString(paymentMethod)),
              amount: Value(amount),
              tipAmount: Value(tipAmount),
              tenderedAmount: Value(tenderedAmount),
              changeAmount: Value(changeAmount),
              reference: Value(reference),
              receivedBy: Value(receivedBy),
              paidAt: Value(now),
              createdAt: Value(now),
              updatedAt: Value(now),
              isDeleted: const Value(false),
              syncStatus: const Value(0),
            ),
          );

      // --- Update bill status ---
      final allPayments = await (_db.select(_db.payments)
            ..where(
              (p) =>
                  p.billId.equals(billRow.id) & p.isDeleted.equals(false),
            ))
          .get();
      final totalPaid = allPayments.fold<int>(0, (s, p) => s + p.amount);

      final newBillStatus =
          totalPaid >= billRow.total ? 'fully_paid' : 'partially_paid';

      await (_db.update(_db.bills)..where((b) => b.id.equals(billRow.id)))
          .write(
        BillsCompanion(
          status: Value(newBillStatus),
          updatedAt: Value(now),
        ),
      );

      // --- Update ticket status when fully paid ---
      if (newBillStatus == 'fully_paid') {
        // Read the ticket so we can resolve its tableId once.
        final ticketRow = await (_db.select(_db.tickets)
              ..where((t) => t.id.equals(ticketId)))
            .getSingle();

        await (_db.update(_db.tickets)
              ..where((t) => t.id.equals(ticketId)))
            .write(
          TicketsCompanion(
            status: const Value('completed'),
            closedAt: Value(now),
            updatedAt: Value(now),
          ),
        );

        // Free the table: clear currentOrderId, flip status back to
        // available, drop any concurrent flags. Mirrors
        // TableRepositoryImpl.clearTable() but inlined here so the whole
        // payment + table-release sequence lives in one transaction.
        final tableId = ticketRow.tableId;
        if (tableId != null && tableId.isNotEmpty) {
          await (_db.update(_db.restaurantTables)
                ..where((t) => t.id.equals(tableId)))
              .write(RestaurantTablesCompanion(
            currentOrderId: const Value(null),
            status: const Value('available'),
            flags: const Value(''),
            updatedAt: Value(now),
          ));
        }
      }

      // Fetch the persisted payment to return.
      final paymentRow = await (_db.select(_db.payments)
            ..where((p) => p.id.equals(paymentId)))
          .getSingle();
      result = _paymentToEntity(paymentRow);
    });

    return result;
  }

  // =========================================================================
  // Private helpers
  // =========================================================================

  Future<BillEntity?> _getBillById(String id) async {
    final query = _db.select(_db.bills)
      ..where((b) => b.id.equals(id) & b.isDeleted.equals(false));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    final payments = await getPaymentsByBill(id);
    return _billToEntity(row, payments);
  }

  // =========================================================================
  // Mappers – Bill
  // =========================================================================

  BillEntity _billToEntity(Bill row, List<PaymentEntity> payments) {
    return BillEntity(
      id: row.id,
      tenantId: row.tenantId,
      ticketId: row.ticketId,
      billNumber: row.billNumber.toString().padLeft(4, '0'),
      subtotal: row.subtotal,
      taxAmount: row.taxAmount,
      discountAmount: row.discountAmount,
      total: row.total,
      status: _parseBillStatus(row.status),
      payments: payments,
    );
  }

  BillsCompanion _billToCompanion(BillEntity entity) {
    return BillsCompanion(
      id: Value(entity.id),
      tenantId: Value(entity.tenantId),
      ticketId: Value(entity.ticketId),
      billNumber: Value(int.tryParse(entity.billNumber) ?? 0),
      subtotal: Value(entity.subtotal),
      taxAmount: Value(entity.taxAmount),
      discountAmount: Value(entity.discountAmount),
      total: Value(entity.total),
      status: Value(_billStatusToString(entity.status)),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
      syncStatus: const Value(0),
    );
  }

  // =========================================================================
  // Mappers – Payment
  // =========================================================================

  PaymentEntity _paymentToEntity(Payment row) {
    return PaymentEntity(
      id: row.id,
      tenantId: row.tenantId,
      billId: row.billId,
      ticketId: row.ticketId,
      paymentMethod: _parsePaymentMethod(row.paymentMethod),
      amount: row.amount,
      tipAmount: row.tipAmount,
      tenderedAmount: row.tenderedAmount,
      changeAmount: row.changeAmount,
      reference: row.reference,
      receivedBy: row.receivedBy,
      paidAt: row.paidAt,
    );
  }

  PaymentsCompanion _paymentToCompanion(PaymentEntity entity) {
    return PaymentsCompanion(
      id: Value(entity.id),
      tenantId: Value(entity.tenantId),
      billId: Value(entity.billId),
      ticketId: Value(entity.ticketId),
      paymentMethod: Value(_paymentMethodToString(entity.paymentMethod)),
      amount: Value(entity.amount),
      tipAmount: Value(entity.tipAmount),
      tenderedAmount: Value(entity.tenderedAmount),
      changeAmount: Value(entity.changeAmount),
      reference: Value(entity.reference),
      receivedBy: Value(entity.receivedBy),
      paidAt: Value(entity.paidAt),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
      syncStatus: const Value(0),
    );
  }

  // =========================================================================
  // Enum serialisation helpers
  // =========================================================================

  static PaymentMethod _parsePaymentMethod(String value) {
    return switch (value) {
      'cash' => PaymentMethod.cash,
      'credit_card' => PaymentMethod.creditCard,
      'debit_card' => PaymentMethod.debitCard,
      _ => PaymentMethod.other,
    };
  }

  static String _paymentMethodToString(PaymentMethod method) {
    return switch (method) {
      PaymentMethod.cash => 'cash',
      PaymentMethod.creditCard => 'credit_card',
      PaymentMethod.debitCard => 'debit_card',
      PaymentMethod.other => 'other',
    };
  }

  static BillStatus _parseBillStatus(String value) {
    return switch (value) {
      'open' => BillStatus.open,
      'partially_paid' => BillStatus.partiallyPaid,
      'fully_paid' => BillStatus.fullyPaid,
      'void' => BillStatus.voidStatus,
      _ => BillStatus.open,
    };
  }

  static String _billStatusToString(BillStatus status) {
    return switch (status) {
      BillStatus.open => 'open',
      BillStatus.partiallyPaid => 'partially_paid',
      BillStatus.fullyPaid => 'fully_paid',
      BillStatus.voidStatus => 'void',
    };
  }
}
