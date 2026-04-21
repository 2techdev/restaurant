/// Unit tests for [RefundRepositoryImpl].
///
/// Swiss storno compliance is the central invariant this suite guards:
///   * every refund receipt references the ORIGINAL sale receipt (traceability),
///   * every audit row carries BOTH requester + approver identity,
///   * the audit action is the enum value, not a raw string,
///   * reason is mandatory (blank throws).
///
/// Uses an in-memory Drift database. Run with:
///   flutter test test/features/payments/refund_repository_impl_test.dart
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/features/payments/data/repositories/refund_repository_impl.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-1';
const _deviceId = 'DEV-TEST-01';

UserEntity _user({
  required String id,
  required String name,
  UserRole role = UserRole.cashier,
}) {
  final now = DateTime(2026, 4, 22);
  return UserEntity(
    id: id,
    tenantId: _tenantId,
    name: name,
    pinHash: 'hash',
    role: role,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );
}

final _requester = _user(id: 'cashier-1', name: 'Ayşe Kasiyer');
final _approver =
    _user(id: 'manager-1', name: 'Mehmet Yönetici', role: UserRole.manager);

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

/// Seed an original sale receipt so the refund can reference it.
Future<String> _seedOriginalReceipt(
  AppDatabase db, {
  required String ticketId,
  required String billId,
  String? number,
}) async {
  final id = IdGenerator.generateId();
  final now = DateTime.now();
  await db.into(db.receipts).insert(ReceiptsCompanion(
        id: Value(id),
        tenantId: const Value(_tenantId),
        ticketId: Value(ticketId),
        billId: Value(billId),
        receiptNumber: Value(number ?? 'R-2026-0001'),
        receiptType: const Value('sale'),
        content: const Value('{}'),
        printedAt: Value(now),
        printCount: const Value(1),
        createdAt: Value(now),
        syncStatus: const Value(0),
      ));
  return id;
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
          ticketId: ticketId, id: 'item-1', subtotal: 3500, taxAmount: 283);
      await _seedItem(db,
          ticketId: ticketId, id: 'item-2', subtotal: 3500, taxAmount: 284);

      final result = await repo.processRefund(
        ticketId: ticketId,
        tenantId: _tenantId,
        deviceId: _deviceId,
        orderItemIds: [item1],
        reason: 'Yanlış Ürün Gönderildi',
        refundMethodStr: 'original',
        approver: _approver,
        requester: _requester,
      );

      expect(result.refundAmount, equals(3783));
      expect(result.refundedItemIds, equals([item1]));
      expect(result.stornoReceiptNumber, isNotEmpty);
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
        approver: _approver,
        requester: _requester,
      );

      final payments = await db.select(db.payments).get();
      expect(payments, hasLength(1));
      expect(payments.first.amount, equals(-3783));
      expect(payments.first.paymentMethod, equals('cash'));
      expect(payments.first.reference, startsWith('STORNO-'),
          reason: 'refund payments should carry a storno reference');
    });

    test('writes audit row with itemRefunded action + manager fields',
        () async {
      final ticketId = await _seedTicket(db);
      await _seedBill(db, ticketId: ticketId);
      final item1 = await _seedItem(db,
          ticketId: ticketId, subtotal: 2000, taxAmount: 162);

      await repo.processRefund(
        ticketId: ticketId,
        tenantId: _tenantId,
        deviceId: _deviceId,
        orderItemIds: [item1],
        reason: 'Kalite Sorunu',
        refundMethodStr: 'original',
        approver: _approver,
        requester: _requester,
      );

      final logs = await db.select(db.auditLog).get();
      expect(logs, hasLength(1));
      final row = logs.first;
      expect(row.action, equals(AuditAction.itemRefunded.name));
      expect(row.userId, equals(_requester.id),
          reason: 'user* fields track the cashier who asked');
      expect(row.userName, equals(_requester.name));
      expect(row.managerId, equals(_approver.id),
          reason: 'manager* fields track the approver');
      expect(row.managerName, equals(_approver.name));
      expect(row.reason, equals('Kalite Sorunu'));
    });

    test('audit payload includes original receipt reference when present',
        () async {
      final ticketId = await _seedTicket(db);
      final billId = await _seedBill(db, ticketId: ticketId);
      await _seedOriginalReceipt(db,
          ticketId: ticketId, billId: billId, number: 'R-2026-0042');
      final item = await _seedItem(db,
          ticketId: ticketId, subtotal: 1000, taxAmount: 81);

      await repo.processRefund(
        ticketId: ticketId,
        tenantId: _tenantId,
        deviceId: _deviceId,
        orderItemIds: [item],
        reason: 'Test',
        refundMethodStr: 'cash',
        approver: _approver,
        requester: _requester,
      );

      final logs = await db.select(db.auditLog).get();
      final payload =
          jsonDecode(logs.first.newValueJson!) as Map<String, dynamic>;
      expect(payload['originalReceiptNumber'], equals('R-2026-0042'));
      expect(payload['stornoReceiptNumber'], isNotNull);
      expect(payload['refundTotal'], equals(1081));
    });

    test('creates storno receipt referencing the original sale receipt',
        () async {
      final ticketId = await _seedTicket(db);
      final billId = await _seedBill(db, ticketId: ticketId);
      await _seedOriginalReceipt(db,
          ticketId: ticketId, billId: billId, number: 'R-2026-0042');
      final item = await _seedItem(db,
          ticketId: ticketId, subtotal: 2000, taxAmount: 162);

      final result = await repo.processRefund(
        ticketId: ticketId,
        tenantId: _tenantId,
        deviceId: _deviceId,
        orderItemIds: [item],
        reason: 'Test',
        refundMethodStr: 'original',
        approver: _approver,
        requester: _requester,
      );

      expect(result.originalReceiptNumber, equals('R-2026-0042'));

      final receipts = await (db.select(db.receipts)
            ..where((r) => r.receiptType.equals('refund')))
          .get();
      expect(receipts, hasLength(1));
      final payload = jsonDecode(receipts.first.content) as Map<String, dynamic>;
      expect(payload['type'], equals('storno'));
      expect(payload['originalReceiptNumber'], equals('R-2026-0042'));
      expect(payload['reason'], equals('Test'));
      expect(payload['approvedBy'], isA<Map>());
      expect((payload['approvedBy'] as Map)['name'], equals(_approver.name));
      expect((payload['requestedBy'] as Map)['name'], equals(_requester.name));
    });
  });

  // -------------------------------------------------------------------------
  // Full refund
  // -------------------------------------------------------------------------

  group('processRefund — full order', () {
    test('refunds all non-voided items when orderItemIds is empty', () async {
      final ticketId = await _seedTicket(db);
      await _seedBill(db, ticketId: ticketId);
      await _seedItem(db,
          ticketId: ticketId, id: 'item-A', subtotal: 3000, taxAmount: 243);
      await _seedItem(db,
          ticketId: ticketId, id: 'item-B', subtotal: 4000, taxAmount: 324);
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
        orderItemIds: [],
        reason: 'Müşteri Memnuniyetsizliği',
        refundMethodStr: 'original',
        approver: _approver,
        requester: _requester,
      );

      expect(result.refundAmount, equals(7567));
      expect(result.refundedItemIds, hasLength(2));
      expect(result.refundedItemIds, isNot(contains('item-C')));
    });

    test('writes audit row with paymentRefunded action on full refund',
        () async {
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
        approver: _approver,
        requester: _requester,
      );

      final logs = await db.select(db.auditLog).get();
      expect(logs.first.action, equals(AuditAction.paymentRefunded.name));
    });
  });

  // -------------------------------------------------------------------------
  // Compliance guards
  // -------------------------------------------------------------------------

  group('processRefund — compliance guards', () {
    test('throws RefundReasonRequiredException on blank reason', () async {
      final ticketId = await _seedTicket(db);
      await _seedBill(db, ticketId: ticketId);
      await _seedItem(db, ticketId: ticketId);

      expect(
        () => repo.processRefund(
          ticketId: ticketId,
          tenantId: _tenantId,
          deviceId: _deviceId,
          orderItemIds: [],
          reason: '   ', // whitespace-only
          refundMethodStr: 'cash',
          approver: _approver,
          requester: _requester,
        ),
        throwsA(isA<RefundReasonRequiredException>()),
      );
    });

    test('blank reason does NOT create any side effects', () async {
      final ticketId = await _seedTicket(db);
      await _seedBill(db, ticketId: ticketId);
      await _seedItem(db, ticketId: ticketId);

      try {
        await repo.processRefund(
          ticketId: ticketId,
          tenantId: _tenantId,
          deviceId: _deviceId,
          orderItemIds: [],
          reason: '',
          refundMethodStr: 'cash',
          approver: _approver,
          requester: _requester,
        );
      } catch (_) {
        // expected
      }

      expect(await db.select(db.payments).get(), isEmpty);
      expect(await db.select(db.auditLog).get(), isEmpty);
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
          approver: _approver,
          requester: _requester,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Pure JSON builder (no DB)
  // -------------------------------------------------------------------------

  group('buildStornoReceiptJson', () {
    test('produces the Swiss-audit-required fields in a round-trippable JSON',
        () {
      final now = DateTime.utc(2026, 4, 22, 14, 30);
      final json = RefundRepositoryImpl.buildStornoReceiptJson(
        ticketId: 't-1',
        billId: 'b-1',
        originalReceiptId: 'r-1',
        originalReceiptNumber: 'R-2026-0001',
        stornoReceiptNumber: 'R-2026-0042',
        items: const [
          StornoLineJson(
            productName: 'Bira',
            quantity: 2,
            subtotal: 1800,
            taxAmount: 146,
          ),
        ],
        subtotal: 1800,
        taxAmount: 146,
        refundTotal: 1946,
        reason: 'Kalite Sorunu',
        notes: 'köpüksüzdü',
        approvedByUserId: 'm1',
        approvedByName: 'Manager',
        requestedByUserId: 'c1',
        requestedByName: 'Cashier',
        method: 'cash',
        timestamp: now,
      );

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['type'], 'storno');
      expect(decoded['stornoReceiptNumber'], 'R-2026-0042');
      expect(decoded['originalReceiptNumber'], 'R-2026-0001');
      expect(decoded['reason'], 'Kalite Sorunu');
      expect(decoded['notes'], 'köpüksüzdü');
      expect((decoded['approvedBy'] as Map)['name'], 'Manager');
      expect((decoded['requestedBy'] as Map)['name'], 'Cashier');
      expect(decoded['total'], 1946);
      expect(decoded['timestamp'], '2026-04-22T14:30:00.000Z');
      expect((decoded['items'] as List).first['name'], 'Bira');
    });

    test('omits notes when null', () {
      final json = RefundRepositoryImpl.buildStornoReceiptJson(
        ticketId: 't',
        billId: 'b',
        originalReceiptId: null,
        originalReceiptNumber: null,
        stornoReceiptNumber: 'S1',
        items: const [],
        subtotal: 0,
        taxAmount: 0,
        refundTotal: 0,
        reason: 'x',
        notes: null,
        approvedByUserId: 'm',
        approvedByName: 'M',
        requestedByUserId: 'c',
        requestedByName: 'C',
        method: 'cash',
        timestamp: DateTime.utc(2026, 1, 1),
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded.containsKey('notes'), isFalse);
      expect(decoded['originalReceiptNumber'], isNull);
    });
  });
}
