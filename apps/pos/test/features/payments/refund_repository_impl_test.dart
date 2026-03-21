/// Unit tests for RefundRepositoryImpl.
///
/// Uses an in-memory Drift database. Covers:
///  - processRefund (partial): calculates correct refund total from items
///  - processRefund (full): includes all non-voided items
///  - processRefund: creates a receipt record with type='refund'
///  - processRefund: creates a negative payment record
///  - processRefund: writes an audit log entry
///  - processRefund: creates a bill if none exists
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/payments/data/repositories/refund_repository_impl.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-1';
const _deviceId = 'DEV-TEST-01';
const _requestedBy = 'cashier-1';
const _approvedBy = 'manager-1';

// ---------------------------------------------------------------------------
// Seed helpers
// ---------------------------------------------------------------------------

Future<String> _seedTicket(AppDatabase db, {String? id}) async {
  final ticketId = id ?? IdGenerator.generateId();
  final now = DateTime.now();
  await db.into(db.tickets).insert(TicketsCompanion(
        id: Value(ticketId),
        tenantId: const Value(_tenantId),
        orderNumber: const Value(1),
        orderType: const Value('dine_in'),
        status: const Value('completed'),
        channel: const Value('pos'),
        subtotal: const Value(7000),
        taxAmount: const Value(567),
        discountAmount: const Value(0),
        total: const Value(7567),
        openedAt: Value(now),
        deviceId: const Value(_deviceId),
        createdAt: Value(now),
        updatedAt: Value(now),
        isDeleted: const Value(false),
        syncStatus: const Value(0),
      ));
  return ticketId;
}

Future<String> _seedItem(
  AppDatabase db, {
  required String ticketId,
  String? id,
  int subtotal = 3500,
  int taxAmount = 283,
  String status = 'served',
}) async {
  final itemId = id ?? IdGenerator.generateId();
  final now = DateTime.now();
  await db.into(db.orderItems).insert(OrderItemsCompanion(
        id: Value(itemId),
        tenantId: const Value(_tenantId),
        ticketId: Value(ticketId),
        productId: const Value('prod-1'),
        productName: const Value('Izgara Tavuk'),
        quantity: const Value(1.0),
        unitPrice: Value(subtotal),
        subtotal: Value(subtotal),
        taxAmount: Value(taxAmount),
        discountAmount: const Value(0),
        status: Value(status),
        sentToKitchen: const Value(true),
        course: const Value(1),
        createdAt: Value(now),
        updatedAt: Value(now),
        isDeleted: const Value(false),
        syncStatus: const Value(0),
      ));
  return itemId;
}

Future<String> _seedBill(AppDatabase db,
    {required String ticketId, String status = 'fully_paid'}) async {
  final billId = IdGenerator.generateId();
  final now = DateTime.now();
  await db.into(db.bills).insert(BillsCompanion(
        id: Value(billId),
        tenantId: const Value(_tenantId),
        ticketId: Value(ticketId),
        billNumber: const Value(1),
        subtotal: const Value(7000),
        taxAmount: const Value(567),
        discountAmount: const Value(0),
        total: const Value(7567),
        status: Value(status),
        createdAt: Value(now),
        updatedAt: Value(now),
        isDeleted: const Value(false),
        syncStatus: const Value(0),
      ));
  return billId;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;
  late RefundRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = RefundRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  // -------------------------------------------------------------------------
  // Partial refund
  // -------------------------------------------------------------------------

  group('processRefund — partial (selected items)', () {
    test('refund total equals subtotal + tax of selected items', () async {
      final ticketId = await _seedTicket(db);
      await _seedBill(db, ticketId: ticketId);
      final item1 = await _seedItem(db,
          ticketId: ticketId,
          id: 'item-1',
          subtotal: 3500,
          taxAmount: 283);
      await _seedItem(db,
          ticketId: ticketId,
          id: 'item-2',
          subtotal: 3500,
          taxAmount: 284);

      final result = await repo.processRefund(
        ticketId: ticketId,
        tenantId: _tenantId,
        deviceId: _deviceId,
        orderItemIds: [item1], // partial: only item-1
        reason: 'Yanlış Ürün Gönderildi',
        refundMethodStr: 'original',
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
      );

      // 3500 + 283 = 3783
      expect(result.refundAmount, equals(3783));
      expect(result.refundedItemIds, equals([item1]));
    });

    test('creates a negative payment record', () async {
      final ticketId = await _seedTicket(db);
      await _seedBill(db, ticketId: ticketId);
      final item1 = await _seedItem(db,
          ticketId: ticketId, subtotal: 3500, taxAmount: 283);

      await repo.processRefund(
        ticketId: ticketId,
        tenantId: _tenantId,
        deviceId: _deviceId,
        orderItemIds: [item1],
        reason: 'Test',
        refundMethodStr: 'cash',
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
      );

      final payments = await db.select(db.payments).get();
      expect(payments, hasLength(1));
      expect(payments.first.amount, isNegative);
      expect(payments.first.amount, equals(-3783));
      expect(payments.first.paymentMethod, equals('cash'));
    });

    test('creates a receipt with type=refund', () async {
      final ticketId = await _seedTicket(db);
      await _seedBill(db, ticketId: ticketId);
      final item1 =
          await _seedItem(db, ticketId: ticketId, subtotal: 2000, taxAmount: 162);

      final result = await repo.processRefund(
        ticketId: ticketId,
        tenantId: _tenantId,
        deviceId: _deviceId,
        orderItemIds: [item1],
        reason: 'Test',
        refundMethodStr: 'original',
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
      );

      final receipts = await db.select(db.receipts).get();
      expect(receipts, hasLength(1));
      expect(receipts.first.receiptType, equals('refund'));
      expect(result.receiptId, equals(receipts.first.id));
    });

    test('writes an audit log entry with refund_item action', () async {
      final ticketId = await _seedTicket(db);
      await _seedBill(db, ticketId: ticketId);
      final item1 =
          await _seedItem(db, ticketId: ticketId, subtotal: 2000, taxAmount: 162);

      await repo.processRefund(
        ticketId: ticketId,
        tenantId: _tenantId,
        deviceId: _deviceId,
        orderItemIds: [item1],
        reason: 'Kalite Sorunu',
        refundMethodStr: 'original',
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
      );

      final logs = await db.select(db.auditLog).get();
      expect(logs, hasLength(1));
      expect(logs.first.action, equals('override:refund_item'));
    });
  });

  // -------------------------------------------------------------------------
  // Full refund (empty orderItemIds)
  // -------------------------------------------------------------------------

  group('processRefund — full order', () {
    test('refunds all non-voided items when orderItemIds is empty', () async {
      final ticketId = await _seedTicket(db);
      await _seedBill(db, ticketId: ticketId);
      await _seedItem(db,
          ticketId: ticketId,
          id: 'item-A',
          subtotal: 3000,
          taxAmount: 243);
      await _seedItem(db,
          ticketId: ticketId,
          id: 'item-B',
          subtotal: 4000,
          taxAmount: 324);
      // A voided item should NOT be included.
      await _seedItem(db,
          ticketId: ticketId,
          id: 'item-C',
          subtotal: 2000,
          taxAmount: 162,
          status: 'void');

      final result = await repo.processRefund(
        ticketId: ticketId,
        tenantId: _tenantId,
        deviceId: _deviceId,
        orderItemIds: [], // full refund
        reason: 'Müşteri Memnuniyetsizliği',
        refundMethodStr: 'original',
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
      );

      // item-A (3243) + item-B (4324) = 7567; item-C excluded (void)
      expect(result.refundAmount, equals(7567));
      expect(result.refundedItemIds, hasLength(2));
      expect(result.refundedItemIds, isNot(contains('item-C')));
    });

    test('writes an audit log entry with refund_ticket action', () async {
      final ticketId = await _seedTicket(db);
      await _seedBill(db, ticketId: ticketId);
      await _seedItem(db, ticketId: ticketId, subtotal: 7000, taxAmount: 567);

      await repo.processRefund(
        ticketId: ticketId,
        tenantId: _tenantId,
        deviceId: _deviceId,
        orderItemIds: [],
        reason: 'Test',
        refundMethodStr: 'cash',
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
      );

      final logs = await db.select(db.auditLog).get();
      expect(logs.first.action, equals('override:refund_ticket'));
    });
  });

  // -------------------------------------------------------------------------
  // Bill creation
  // -------------------------------------------------------------------------

  group('processRefund — bill handling', () {
    test('creates a bill when none exists for the ticket', () async {
      final ticketId = await _seedTicket(db);
      // NO bill seeded.
      final item =
          await _seedItem(db, ticketId: ticketId, subtotal: 3500, taxAmount: 283);

      await repo.processRefund(
        ticketId: ticketId,
        tenantId: _tenantId,
        deviceId: _deviceId,
        orderItemIds: [item],
        reason: 'Test',
        refundMethodStr: 'original',
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
      );

      final bills = await db.select(db.bills).get();
      expect(bills, hasLength(1));
    });

    test('reuses existing bill when one is present', () async {
      final ticketId = await _seedTicket(db);
      await _seedBill(db, ticketId: ticketId);
      final item =
          await _seedItem(db, ticketId: ticketId, subtotal: 3500, taxAmount: 283);

      await repo.processRefund(
        ticketId: ticketId,
        tenantId: _tenantId,
        deviceId: _deviceId,
        orderItemIds: [item],
        reason: 'Test',
        refundMethodStr: 'original',
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
      );

      final bills = await db.select(db.bills).get();
      // Still only one bill.
      expect(bills, hasLength(1));
    });

    test('throws StateError when ticket does not exist', () async {
      expect(
        () => repo.processRefund(
          ticketId: 'nonexistent',
          tenantId: _tenantId,
          deviceId: _deviceId,
          orderItemIds: [],
          reason: 'Test',
          refundMethodStr: 'cash',
          approvedByUserId: _approvedBy,
          requestedByUserId: _requestedBy,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
