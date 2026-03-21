/// Repository integration tests for PaymentRepositoryImpl.
///
/// Uses an in-memory Drift database.  Tests cover:
///   - Bill creation and querying
///   - Payment recording (createPayment)
///   - Full processPayment flow (auto-bill, status transitions, ticket completion)
///   - Partial & split payments
///   - Change calculation for cash payments
///   - Card payments (no change)
///
/// Run with:
///   flutter test test/features/payments/data/payment_repository_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/payments/data/repositories/payment_repository_impl.dart';
import 'package:gastrocore_pos/features/payments/domain/entities/payment_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-pay-test';
const _deviceId = 'DEV-PAY-01';
const _userId = 'user-cashier-01';

PaymentRepositoryImpl _makeRepo(AppDatabase db) => PaymentRepositoryImpl(db);

/// Create and persist a ticket with [itemCount] items at [unitPrice] each.
/// Returns the created ticket.
Future<TicketEntity> _seedTicket(
  AppDatabase db, {
  int itemCount = 2,
  int unitPrice = 2500,
  OrderType orderType = OrderType.dineIn,
}) async {
  final orderRepo = OrderRepositoryImpl(db);
  final ticketId = IdGenerator.generateId();
  final items = List.generate(itemCount, (i) {
    final itemId = IdGenerator.generateId();
    return OrderItemEntity(
      id: itemId,
      tenantId: _tenantId,
      ticketId: ticketId,
      productId: 'prod-$i',
      productName: 'Product $i',
      quantity: 1,
      unitPrice: unitPrice,
      subtotal: unitPrice,
      taxGroup: 'food',
    );
  });

  final ticket = TicketEntity(
    id: ticketId,
    tenantId: _tenantId,
    orderNumber: IdGenerator.generateId().substring(0, 6),
    orderType: orderType,
    status: TicketStatus.sent,
    openedAt: DateTime(2026, 3, 20, 9, 0),
    deviceId: _deviceId,
    items: items,
  );

  await orderRepo.createTicket(ticket);
  await orderRepo.calculateTicketTotals(ticketId);
  return (await orderRepo.getTicketById(ticketId))!;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PaymentRepositoryImpl — Bill Operations', () {
    late AppDatabase db;
    late PaymentRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase.createInMemory();
      repo = _makeRepo(db);
    });

    tearDown(() async => db.close());

    test('getBillsByTicket returns empty list for unknown ticket', () async {
      final bills = await repo.getBillsByTicket('nonexistent-ticket');
      expect(bills, isEmpty);
    });
  });

  // =========================================================================
  // processPayment — happy paths
  // =========================================================================

  group('PaymentRepositoryImpl — processPayment', () {
    late AppDatabase db;
    late PaymentRepositoryImpl payRepo;

    setUp(() async {
      db = AppDatabase.createInMemory();
      payRepo = _makeRepo(db);
    });

    tearDown(() async => db.close());

    // -----------------------------------------------------------------------
    // Cash payment — full amount
    // -----------------------------------------------------------------------

    test('Cash payment auto-creates a bill and returns payment entity', () async {
      final ticket = await _seedTicket(db, itemCount: 1, unitPrice: 3000);

      final payment = await payRepo.processPayment(
        ticketId: ticket.id,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.cash,
        amount: 3000,
        tenderedAmount: 5000,
        receivedBy: _userId,
      );

      expect(payment.id, isNotEmpty);
      expect(payment.ticketId, equals(ticket.id));
      expect(payment.paymentMethod, equals(PaymentMethod.cash));
      expect(payment.amount, equals(3000));
      expect(payment.tenderedAmount, equals(5000));
    });

    test('Cash payment calculates correct change', () async {
      final ticket = await _seedTicket(db, itemCount: 1, unitPrice: 2500);

      final payment = await payRepo.processPayment(
        ticketId: ticket.id,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.cash,
        amount: 2500,
        tenderedAmount: 5000,
        receivedBy: _userId,
      );

      // Change = tendered - amount = 2500.
      expect(payment.changeAmount, equals(2500));
    });

    test('Cash payment with exact tender has zero change', () async {
      final ticket = await _seedTicket(db, itemCount: 1, unitPrice: 1800);

      final payment = await payRepo.processPayment(
        ticketId: ticket.id,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.cash,
        amount: 1800,
        tenderedAmount: 1800,
        receivedBy: _userId,
      );

      expect(payment.changeAmount, equals(0));
    });

    // -----------------------------------------------------------------------
    // Card payment — no change
    // -----------------------------------------------------------------------

    test('Card payment has zero change regardless of amounts', () async {
      final ticket = await _seedTicket(db, itemCount: 1, unitPrice: 4500);

      final payment = await payRepo.processPayment(
        ticketId: ticket.id,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.creditCard,
        amount: 4500,
        tenderedAmount: 4500,
        receivedBy: _userId,
      );

      expect(payment.changeAmount, equals(0));
      expect(payment.paymentMethod, equals(PaymentMethod.creditCard));
    });

    // -----------------------------------------------------------------------
    // Bill & ticket status transitions
    // -----------------------------------------------------------------------

    test('Fully paid ticket transitions to completed status', () async {
      final ticket = await _seedTicket(db, itemCount: 2, unitPrice: 2500);
      // Total = 5000 cents.
      final totalAmount = 5000;

      await payRepo.processPayment(
        ticketId: ticket.id,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.cash,
        amount: totalAmount,
        tenderedAmount: totalAmount,
        receivedBy: _userId,
      );

      // Ticket status should now be completed.
      final ticketRow = await (db.select(db.tickets)
            ..where((t) => t.id.equals(ticket.id)))
          .getSingle();
      expect(ticketRow.status, equals('completed'));
    });

    test('Bill is fully_paid after full cash payment', () async {
      final ticket = await _seedTicket(db, itemCount: 1, unitPrice: 2000);

      await payRepo.processPayment(
        ticketId: ticket.id,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.cash,
        amount: 2000,
        tenderedAmount: 2000,
        receivedBy: _userId,
      );

      // Verify bill status via direct DB.
      final billRows = await (db.select(db.bills)
            ..where((b) => b.ticketId.equals(ticket.id)))
          .get();
      expect(billRows, isNotEmpty);
      expect(billRows.first.status, equals('fully_paid'));
    });

    // -----------------------------------------------------------------------
    // Partial payment (split bills)
    // -----------------------------------------------------------------------

    test('Partial payment leaves bill in partially_paid status', () async {
      final ticket = await _seedTicket(db, itemCount: 2, unitPrice: 3000);
      // Total = 6000, pay 3000 first.

      await payRepo.processPayment(
        ticketId: ticket.id,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.cash,
        amount: 3000,
        tenderedAmount: 3000,
        receivedBy: _userId,
      );

      final billRows = await (db.select(db.bills)
            ..where((b) => b.ticketId.equals(ticket.id)))
          .get();
      expect(billRows, isNotEmpty);
      expect(billRows.first.status, equals('partially_paid'));

      // Ticket should NOT be completed yet.
      final ticketRow = await (db.select(db.tickets)
            ..where((t) => t.id.equals(ticket.id)))
          .getSingle();
      expect(ticketRow.status, isNot(equals('completed')));
    });

    test('Two partial payments that sum to full amount complete the ticket',
        () async {
      final ticket = await _seedTicket(db, itemCount: 2, unitPrice: 2000);
      // Total = 4000.

      // First payment: 2000.
      await payRepo.processPayment(
        ticketId: ticket.id,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.cash,
        amount: 2000,
        tenderedAmount: 2000,
        receivedBy: _userId,
      );

      // Second payment: 2000.
      await payRepo.processPayment(
        ticketId: ticket.id,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.cash,
        amount: 2000,
        tenderedAmount: 2000,
        receivedBy: _userId,
      );

      final billRows = await (db.select(db.bills)
            ..where((b) => b.ticketId.equals(ticket.id)))
          .get();
      expect(billRows.first.status, equals('fully_paid'));

      final ticketRow = await (db.select(db.tickets)
            ..where((t) => t.id.equals(ticket.id)))
          .getSingle();
      expect(ticketRow.status, equals('completed'));
    });

    // -----------------------------------------------------------------------
    // Tip
    // -----------------------------------------------------------------------

    test('processPayment records tip amount', () async {
      final ticket = await _seedTicket(db, itemCount: 1, unitPrice: 2000);

      final payment = await payRepo.processPayment(
        ticketId: ticket.id,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.cash,
        amount: 2000,
        tenderedAmount: 2500,
        tipAmount: 200,
        receivedBy: _userId,
      );

      expect(payment.tipAmount, equals(200));
    });

    // -----------------------------------------------------------------------
    // getPaymentsByBill
    // -----------------------------------------------------------------------

    test('getPaymentsByBill returns all payments for a bill', () async {
      final ticket = await _seedTicket(db, itemCount: 2, unitPrice: 1500);
      // Total = 3000.

      // Two payments of 1500.
      await payRepo.processPayment(
        ticketId: ticket.id,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.cash,
        amount: 1500,
        tenderedAmount: 1500,
        receivedBy: _userId,
      );
      await payRepo.processPayment(
        ticketId: ticket.id,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.creditCard,
        amount: 1500,
        tenderedAmount: 1500,
        receivedBy: _userId,
      );

      // Find the bill.
      final billRows = await (db.select(db.bills)
            ..where((b) => b.ticketId.equals(ticket.id)))
          .get();
      expect(billRows, isNotEmpty);

      final payments = await payRepo.getPaymentsByBill(billRows.first.id);
      expect(payments.length, equals(2));
      expect(
        payments.map((p) => p.paymentMethod),
        containsAll([PaymentMethod.cash, PaymentMethod.creditCard]),
      );
    });

    test('getPaymentsByBill returns empty for unknown bill id', () async {
      final payments = await payRepo.getPaymentsByBill('nonexistent-bill');
      expect(payments, isEmpty);
    });

    // -----------------------------------------------------------------------
    // Reference storage
    // -----------------------------------------------------------------------

    test('processPayment stores an external reference when provided', () async {
      final ticket = await _seedTicket(db, itemCount: 1, unitPrice: 5000);
      const ref = 'WALLEE-TX-12345';

      final payment = await payRepo.processPayment(
        ticketId: ticket.id,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.creditCard,
        amount: 5000,
        tenderedAmount: 5000,
        receivedBy: _userId,
        reference: ref,
      );

      expect(payment.reference, equals(ref));
    });
  });

  // =========================================================================
  // BillEntity derived properties
  // =========================================================================

  group('BillEntity — derived properties', () {
    test('totalPaid sums all payment amounts', () {
      final payments = [
        _makePayment(amount: 1000),
        _makePayment(amount: 2000),
      ];
      final bill = BillEntity(
        id: 'bill-1',
        tenantId: _tenantId,
        ticketId: 'ticket-1',
        billNumber: '0001',
        subtotal: 3000,
        taxAmount: 0,
        total: 3000,
        payments: payments,
      );
      expect(bill.totalPaid, equals(3000));
    });

    test('remainingBalance is zero when fully paid', () {
      final bill = BillEntity(
        id: 'bill-2',
        tenantId: _tenantId,
        ticketId: 'ticket-2',
        billNumber: '0002',
        subtotal: 2500,
        taxAmount: 0,
        total: 2500,
        payments: [_makePayment(amount: 2500)],
      );
      expect(bill.remainingBalance, equals(0));
      expect(bill.isFullyPaid, isTrue);
    });

    test('isFullyPaid is false when balance remains', () {
      final bill = BillEntity(
        id: 'bill-3',
        tenantId: _tenantId,
        ticketId: 'ticket-3',
        billNumber: '0003',
        subtotal: 4000,
        taxAmount: 0,
        total: 4000,
        payments: [_makePayment(amount: 1500)],
      );
      expect(bill.isFullyPaid, isFalse);
      expect(bill.remainingBalance, equals(2500));
    });

    test('totalPaid is zero with no payments', () {
      const bill = BillEntity(
        id: 'bill-4',
        tenantId: _tenantId,
        ticketId: 'ticket-4',
        billNumber: '0004',
        subtotal: 1000,
        taxAmount: 0,
        total: 1000,
      );
      expect(bill.totalPaid, equals(0));
      expect(bill.isFullyPaid, isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// Inline helpers
// ---------------------------------------------------------------------------

PaymentEntity _makePayment({
  String? id,
  int amount = 1000,
  PaymentMethod method = PaymentMethod.cash,
}) {
  return PaymentEntity(
    id: id ?? IdGenerator.generateId(),
    tenantId: _tenantId,
    billId: 'bill-x',
    ticketId: 'ticket-x',
    paymentMethod: method,
    amount: amount,
    receivedBy: _userId,
    paidAt: DateTime(2026, 3, 20, 10, 0),
  );
}
