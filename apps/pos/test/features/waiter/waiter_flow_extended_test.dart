/// Extended WaiterOrderService tests covering markServed, reorderFromTable,
/// getOrdersForTable and the full dine-in order lifecycle.
///
/// Run with:
///   flutter test test/features/waiter/waiter_flow_extended_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/kitchen/data/repositories/kitchen_repository_impl.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/tables/data/repositories/table_repository_impl.dart';
import 'package:gastrocore_pos/features/waiter/services/waiter_order_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-waiter-ext';
const _deviceId = 'DEV-WAITER-EXT-01';
const _waiterId = 'waiter-ext-01';
const _waiterName = 'Sophie Schmid';

ProductEntity _makeProduct({
  String? id,
  String name = 'Zürcher Geschnetzeltes',
  int price = 2800,
  String taxGroup = 'food',
}) {
  return ProductEntity(
    id: id ?? IdGenerator.generateId(),
    tenantId: _tenantId,
    categoryId: 'cat-main',
    name: name,
    price: price,
    costPrice: 900,
    taxGroup: taxGroup,
    isActive: true,
    displayOrder: 0,
    printerGroup: 'kitchen',
  );
}

/// Seeds a floor + table, returns (floorId, tableId).
Future<(String, String)> _seedTable(AppDatabase db, {String tableName = 'T1'}) async {
  final floorId = IdGenerator.generateId();
  final tableId = IdGenerator.generateId();
  final now = DateTime.now();

  await db.into(db.floors).insert(FloorsCompanion(
        id: Value(floorId),
        tenantId: const Value(_tenantId),
        name: const Value('Ground Floor'),
        displayOrder: const Value(0),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));

  await db.into(db.restaurantTables).insert(RestaurantTablesCompanion(
        id: Value(tableId),
        tenantId: const Value(_tenantId),
        floorId: Value(floorId),
        name: Value(tableName),
        capacity: const Value(4),
        shape: const Value('rectangle'),
        posX: const Value(50),
        posY: const Value(50),
        width: const Value(120),
        height: const Value(80),
        status: const Value('available'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));

  return (floorId, tableId);
}

WaiterOrderService _makeService(AppDatabase db) {
  return WaiterOrderService(
    orderRepo: OrderRepositoryImpl(db),
    kitchenRepo: KitchenRepositoryImpl(db),
    tableRepo: TableRepositoryImpl(db),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // markServed
  // =========================================================================

  group('WaiterOrderService.markServed', () {
    late AppDatabase db;
    late WaiterOrderService svc;

    setUp(() async {
      db = AppDatabase.createInMemory();
      svc = _makeService(db);
    });

    tearDown(() async => db.close());

    test('sets ticket status to served', () async {
      final (_, tableId) = await _seedTable(db);

      final ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      await svc.markServed(ticket.id);

      final repo = OrderRepositoryImpl(db);
      final updated = await repo.getTicketById(ticket.id);
      expect(updated!.status, equals(TicketStatus.served));
    });

    test('marks all sent/preparing/ready items as served', () async {
      final (_, tableId) = await _seedTable(db);
      final product = _makeProduct();

      final ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      await svc.addItemToTicket(
        ticketId: ticket.id,
        product: product,
        quantity: 1,
      );

      await svc.sendToKitchen(ticketId: ticket.id, waiterName: _waiterName);
      await svc.markServed(ticket.id);

      final repo = OrderRepositoryImpl(db);
      final updated = await repo.getTicketById(ticket.id);
      expect(updated!.status, equals(TicketStatus.served));
      for (final item in updated.items) {
        expect(item.status, equals(OrderItemStatus.served));
      }
    });
  });

  // =========================================================================
  // getOrdersForTable
  // =========================================================================

  group('WaiterOrderService.getOrdersForTable', () {
    late AppDatabase db;
    late WaiterOrderService svc;

    setUp(() async {
      db = AppDatabase.createInMemory();
      svc = _makeService(db);
    });

    tearDown(() async => db.close());

    test('returns open orders for a specific table', () async {
      final (_, tableId) = await _seedTable(db);

      await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      final orders = await svc.getOrdersForTable(
        tenantId: _tenantId,
        tableId: tableId,
      );
      expect(orders.length, equals(1));
      expect(orders.first.tableId, equals(tableId));
    });

    test('excludes completed orders for the table', () async {
      final (_, tableId) = await _seedTable(db);

      final ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      final repo = OrderRepositoryImpl(db);
      await repo.updateTicketStatus(ticket.id, TicketStatus.completed);

      final orders = await svc.getOrdersForTable(
        tenantId: _tenantId,
        tableId: tableId,
      );
      expect(orders, isEmpty);
    });

    test('returns empty list for table with no orders', () async {
      final (_, tableId) = await _seedTable(db);
      final orders = await svc.getOrdersForTable(
        tenantId: _tenantId,
        tableId: tableId,
      );
      expect(orders, isEmpty);
    });
  });

  // =========================================================================
  // reorderFromTable
  // =========================================================================

  group('WaiterOrderService.reorderFromTable', () {
    late AppDatabase db;
    late WaiterOrderService svc;

    setUp(() async {
      db = AppDatabase.createInMemory();
      svc = _makeService(db);
    });

    tearDown(() async => db.close());

    test('returns null when no previous order exists', () async {
      final (_, tableId) = await _seedTable(db);

      final result = await svc.reorderFromTable(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );
      expect(result, isNull);
    });

    test('creates new draft ticket copying items from previous order', () async {
      final (_, tableId) = await _seedTable(db);
      final product1 = _makeProduct(name: 'Rösti');
      final product2 = _makeProduct(name: 'Bratwurst');

      // Open original order and add 2 items.
      final original = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );
      await svc.addItemToTicket(ticketId: original.id, product: product1);
      await svc.addItemToTicket(ticketId: original.id, product: product2);

      // Reorder.
      final reorder = await svc.reorderFromTable(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      expect(reorder, isNotNull);
      expect(reorder!.id, isNot(equals(original.id)));
      expect(reorder.tableId, equals(tableId));
      // The reorder should have the same items as the original.
      expect(reorder.items.length, equals(2));
      expect(
        reorder.items.map((i) => i.productName),
        containsAll(['Rösti', 'Bratwurst']),
      );
    });

    test('new reorder ticket preserves guest count from template', () async {
      final (_, tableId) = await _seedTable(db);
      final product = _makeProduct();

      final original = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
        guestCount: 4,
      );
      await svc.addItemToTicket(ticketId: original.id, product: product);

      final reorder = await svc.reorderFromTable(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      expect(reorder!.guestCount, equals(4));
    });
  });

  // =========================================================================
  // Full dine-in lifecycle: open → add items → send → serve → bill requested
  // =========================================================================

  group('WaiterOrderService — full dine-in lifecycle', () {
    late AppDatabase db;
    late WaiterOrderService svc;

    setUp(() async {
      db = AppDatabase.createInMemory();
      svc = _makeService(db);
    });

    tearDown(() async => db.close());

    test('complete dine-in lifecycle without error', () async {
      final (_, tableId) = await _seedTable(db);
      final food = _makeProduct(name: 'Fondue', price: 3200, taxGroup: 'food');
      final drink = _makeProduct(name: 'Wein', price: 1200, taxGroup: 'beverage');

      // Step 1: open order
      final ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
        guestCount: 3,
      );
      expect(ticket.status, equals(TicketStatus.draft));
      expect(ticket.channel, equals(OrderChannel.waiter));
      expect(ticket.guestCount, equals(3));

      // Step 2: add items
      final afterFood = await svc.addItemToTicket(
        ticketId: ticket.id,
        product: food,
        quantity: 2,
      );
      expect(afterFood!.items.length, equals(1));
      expect(afterFood.items.first.quantity, equals(2));

      await svc.addItemToTicket(
        ticketId: ticket.id,
        product: drink,
        quantity: 1,
      );

      // Step 3: send to kitchen
      final afterSend = await svc.sendToKitchen(
        ticketId: ticket.id,
        waiterName: _waiterName,
      );
      expect(afterSend!.status, equals(TicketStatus.sent));

      // Kitchen ticket should have been created.
      final kitchenTickets = await db.select(db.kitchenTickets).get();
      expect(kitchenTickets.length, equals(1));
      expect(kitchenTickets.first.waiterName, equals(_waiterName));

      // Step 4: mark served
      await svc.markServed(ticket.id);
      final repo = OrderRepositoryImpl(db);
      final served = await repo.getTicketById(ticket.id);
      expect(served!.status, equals(TicketStatus.served));

      // Step 5: request bill
      await svc.requestBill(ticket.id);
      final billed = await repo.getTicketById(ticket.id);
      expect(billed!.status, equals(TicketStatus.billRequested));
    });

    test('Swiss VAT for food dine-in is 8.1%', () async {
      final (_, tableId) = await _seedTable(db);
      final food = _makeProduct(name: 'Schnitzel', price: 2000, taxGroup: 'food');

      final ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      final afterItem = await svc.addItemToTicket(
        ticketId: ticket.id,
        product: food,
        quantity: 1,
      );

      // taxAmount = round(2000 * 8.1 / 108.1) = round(149.86) = 150
      expect(afterItem!.items.first.taxAmount, equals(150));
    });

    test('Swiss VAT for food takeaway is 2.6%', () async {
      final (_, tableId) = await _seedTable(db);
      final food = _makeProduct(name: 'Sandwich', price: 1200, taxGroup: 'food');

      final ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
        orderType: OrderType.takeaway,
      );

      final afterItem = await svc.addItemToTicket(
        ticketId: ticket.id,
        product: food,
        quantity: 1,
      );

      // taxAmount = round(1200 * 2.6 / 102.6) = round(30.41) = 30
      expect(afterItem!.items.first.taxAmount, equals(30));
    });

    test('addItemToTicket returns null for completed ticket', () async {
      final (_, tableId) = await _seedTable(db);
      final product = _makeProduct();

      final ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      final repo = OrderRepositoryImpl(db);
      await repo.updateTicketStatus(ticket.id, TicketStatus.completed);

      final result = await svc.addItemToTicket(
        ticketId: ticket.id,
        product: product,
      );
      expect(result, isNull);
    });
  });
}
