/// Unit tests for VoidRepositoryImpl.
///
/// Uses an in-memory Drift database. Covers:
///  - voidOrderItem: marks item as void, recalculates ticket totals
///  - voidOrderItem: auto-voids ticket when all items are voided
///  - voidTicket: voids all items + ticket + bills
///  - voidTicket: writes an audit log entry
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/void_repository_impl.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-1';
const _deviceId = 'DEV-TEST-01';
const _requestedBy = 'cashier-1';
const _approvedBy = 'manager-1';
const _reason = 'Müşteri İptali';

// ---------------------------------------------------------------------------
// DB seed helpers
// ---------------------------------------------------------------------------

Future<String> _seedTicket(AppDatabase db, {String? id}) async {
  final ticketId = id ?? IdGenerator.generateId();
  final now = DateTime.now();
  await db.into(db.tickets).insert(TicketsCompanion(
        id: Value(ticketId),
        tenantId: const Value(_tenantId),
        orderNumber: const Value(1),
        orderType: const Value('dine_in'),
        status: const Value('open'),
        channel: const Value('pos'),
        subtotal: const Value(5000),
        taxAmount: const Value(405),
        discountAmount: const Value(0),
        total: const Value(5405),
        openedAt: Value(now),
        deviceId: const Value(_deviceId),
        createdAt: Value(now),
        updatedAt: Value(now),
        isDeleted: const Value(false),
        syncStatus: const Value(0),
      ));
  return ticketId;
}

Future<String> _seedOrderItem(
  AppDatabase db, {
  required String ticketId,
  String? id,
  int subtotal = 2500,
  int taxAmount = 202,
  String status = 'ordered',
}) async {
  final itemId = id ?? IdGenerator.generateId();
  final now = DateTime.now();
  await db.into(db.orderItems).insert(OrderItemsCompanion(
        id: Value(itemId),
        tenantId: const Value(_tenantId),
        ticketId: Value(ticketId),
        productId: const Value('prod-1'),
        productName: const Value('Adana Kebap'),
        quantity: const Value(1.0),
        unitPrice: Value(subtotal),
        subtotal: Value(subtotal),
        taxAmount: Value(taxAmount),
        discountAmount: const Value(0),
        status: Value(status),
        sentToKitchen: const Value(false),
        course: const Value(1),
        createdAt: Value(now),
        updatedAt: Value(now),
        isDeleted: const Value(false),
        syncStatus: const Value(0),
      ));
  return itemId;
}

Future<String> _seedBill(
  AppDatabase db, {
  required String ticketId,
  String status = 'open',
}) async {
  final billId = IdGenerator.generateId();
  final now = DateTime.now();
  await db.into(db.bills).insert(BillsCompanion(
        id: Value(billId),
        tenantId: const Value(_tenantId),
        ticketId: Value(ticketId),
        billNumber: const Value(1),
        subtotal: const Value(5000),
        taxAmount: const Value(405),
        discountAmount: const Value(0),
        total: const Value(5405),
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
  late VoidRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = VoidRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  // -------------------------------------------------------------------------
  // voidOrderItem
  // -------------------------------------------------------------------------

  group('voidOrderItem', () {
    test('marks the item as void', () async {
      final ticketId = await _seedTicket(db);
      final itemId =
          await _seedOrderItem(db, ticketId: ticketId, subtotal: 2500);

      await repo.voidOrderItem(
        orderItemId: itemId,
        reason: _reason,
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
        tenantId: _tenantId,
        deviceId: _deviceId,
      );

      final item = await (db.select(db.orderItems)
            ..where((i) => i.id.equals(itemId)))
          .getSingle();
      expect(item.status, equals('void'));
    });

    test('recalculates ticket totals after partial void', () async {
      final ticketId = await _seedTicket(db);
      final item1Id = await _seedOrderItem(db,
          ticketId: ticketId, id: 'item-1', subtotal: 2500, taxAmount: 202);
      await _seedOrderItem(db,
          ticketId: ticketId, id: 'item-2', subtotal: 2500, taxAmount: 203);

      // Void only item 1.
      await repo.voidOrderItem(
        orderItemId: item1Id,
        reason: _reason,
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
        tenantId: _tenantId,
        deviceId: _deviceId,
      );

      final ticket = await (db.select(db.tickets)
            ..where((t) => t.id.equals(ticketId)))
          .getSingle();
      // Only item-2 remains: subtotal=2500, tax=203, total=2703
      expect(ticket.subtotal, equals(2500));
      expect(ticket.taxAmount, equals(203));
      expect(ticket.total, equals(2703));
    });

    test('auto-voids ticket when last item is voided', () async {
      final ticketId = await _seedTicket(db);
      final itemId = await _seedOrderItem(db, ticketId: ticketId);

      await repo.voidOrderItem(
        orderItemId: itemId,
        reason: _reason,
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
        tenantId: _tenantId,
        deviceId: _deviceId,
      );

      final ticket = await (db.select(db.tickets)
            ..where((t) => t.id.equals(ticketId)))
          .getSingle();
      expect(ticket.status, equals('voided'));
      expect(ticket.closedAt, isNotNull);
    });

    test('writes an audit log entry', () async {
      final ticketId = await _seedTicket(db);
      final itemId = await _seedOrderItem(db, ticketId: ticketId);

      final result = await repo.voidOrderItem(
        orderItemId: itemId,
        reason: _reason,
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
        tenantId: _tenantId,
        deviceId: _deviceId,
      );

      final logs = await db.select(db.auditLog).get();
      expect(logs, hasLength(1));
      expect(logs.first.action, equals('override:void_item'));
      expect(result.auditLogId, isNotEmpty);
    });

    test('throws StateError when item does not exist', () async {
      expect(
        () => repo.voidOrderItem(
          orderItemId: 'nonexistent',
          reason: _reason,
          approvedByUserId: _approvedBy,
          requestedByUserId: _requestedBy,
          tenantId: _tenantId,
          deviceId: _deviceId,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // voidTicket
  // -------------------------------------------------------------------------

  group('voidTicket', () {
    test('sets ticket status to voided', () async {
      final ticketId = await _seedTicket(db);
      await _seedOrderItem(db, ticketId: ticketId);

      await repo.voidTicket(
        ticketId: ticketId,
        reason: _reason,
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
        tenantId: _tenantId,
        deviceId: _deviceId,
      );

      final ticket = await (db.select(db.tickets)
            ..where((t) => t.id.equals(ticketId)))
          .getSingle();
      expect(ticket.status, equals('voided'));
      expect(ticket.closedAt, isNotNull);
    });

    test('marks all items as void', () async {
      final ticketId = await _seedTicket(db);
      await _seedOrderItem(db, ticketId: ticketId, id: 'item-A');
      await _seedOrderItem(db, ticketId: ticketId, id: 'item-B');
      await _seedOrderItem(db, ticketId: ticketId, id: 'item-C');

      final result = await repo.voidTicket(
        ticketId: ticketId,
        reason: _reason,
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
        tenantId: _tenantId,
        deviceId: _deviceId,
      );

      expect(result.voidedItemIds, hasLength(3));

      final items = await (db.select(db.orderItems)
            ..where((i) => i.ticketId.equals(ticketId)))
          .get();
      expect(items.every((i) => i.status == 'void'), isTrue);
    });

    test('voids open bills for the ticket', () async {
      final ticketId = await _seedTicket(db);
      await _seedOrderItem(db, ticketId: ticketId);
      await _seedBill(db, ticketId: ticketId, status: 'open');

      await repo.voidTicket(
        ticketId: ticketId,
        reason: _reason,
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
        tenantId: _tenantId,
        deviceId: _deviceId,
      );

      final bill = await (db.select(db.bills)
            ..where((b) => b.ticketId.equals(ticketId)))
          .getSingle();
      expect(bill.status, equals('void'));
    });

    test('does not void fully_paid bills', () async {
      final ticketId = await _seedTicket(db);
      await _seedOrderItem(db, ticketId: ticketId);
      await _seedBill(db, ticketId: ticketId, status: 'fully_paid');

      await repo.voidTicket(
        ticketId: ticketId,
        reason: _reason,
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
        tenantId: _tenantId,
        deviceId: _deviceId,
      );

      final bill = await (db.select(db.bills)
            ..where((b) => b.ticketId.equals(ticketId)))
          .getSingle();
      // fully_paid bills are NOT voided by this flow.
      expect(bill.status, equals('fully_paid'));
    });

    test('writes an audit log entry with void_ticket action', () async {
      final ticketId = await _seedTicket(db);
      await _seedOrderItem(db, ticketId: ticketId);

      await repo.voidTicket(
        ticketId: ticketId,
        reason: _reason,
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
        tenantId: _tenantId,
        deviceId: _deviceId,
      );

      final logs = await db.select(db.auditLog).get();
      expect(logs, hasLength(1));
      expect(logs.first.action, equals('override:void_ticket'));
      expect(logs.first.entityId, equals(ticketId));
    });

    test('skips already-voided items', () async {
      final ticketId = await _seedTicket(db);
      await _seedOrderItem(db, ticketId: ticketId, id: 'live', status: 'ordered');
      await _seedOrderItem(db, ticketId: ticketId, id: 'dead', status: 'void');

      final result = await repo.voidTicket(
        ticketId: ticketId,
        reason: _reason,
        approvedByUserId: _approvedBy,
        requestedByUserId: _requestedBy,
        tenantId: _tenantId,
        deviceId: _deviceId,
      );

      // Only the 'live' item was voided by this call.
      expect(result.voidedItemIds, equals(['live']));
    });
  });
}
