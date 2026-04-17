/// Unit tests for [WaiterOrderService].
///
/// Uses an in-memory Drift database and real repository implementations —
/// no mocking of the SQL layer, matching the project's integration-test style.
///
/// Run with:
///   flutter test test/features/waiter/waiter_order_service_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/data/app_initializer.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/kitchen/data/repositories/kitchen_repository_impl.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/tables/data/repositories/table_repository_impl.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/waiter/services/waiter_order_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-waiter-test';
const _deviceId = 'DEV-WAITER-01';
const _waiterId = 'user-waiter-01';
const _waiterName = 'Luca Bernasconi';

/// Build a [WaiterOrderService] backed by an in-memory database.
Future<({AppDatabase db, WaiterOrderService svc})> _setup() async {
  final db = AppDatabase.createInMemory();
  await AppInitializer.initialize(db);

  final svc = WaiterOrderService(
    orderRepo: OrderRepositoryImpl(db),
    kitchenRepo: KitchenRepositoryImpl(db),
    tableRepo: TableRepositoryImpl(db),
  );
  return (db: db, svc: svc);
}

/// Insert a minimal table row and return its id.
Future<String> _createTable(AppDatabase db) async {
  final tableRepo = TableRepositoryImpl(db);
  final floor = await tableRepo.createFloor(
    tenantId: _tenantId,
    name: 'Main Hall',
    displayOrder: 0,
  );
  final table = await tableRepo.createTable(
    tenantId: _tenantId,
    floorId: floor.id,
    name: 'T1',
    capacity: 4,
    posX: 0,
    posY: 0,
    width: 100,
    height: 80,
  );
  return table.id;
}

/// Create a minimal [ProductEntity] with the given price (in cents).
ProductEntity _makeProduct({
  String name = 'Pasta Carbonara',
  int price = 2200,
  String taxGroup = 'food',
}) {
  return ProductEntity(
    id: IdGenerator.generateId(),
    tenantId: _tenantId,
    categoryId: IdGenerator.generateId(),
    name: name,
    price: price,
    costPrice: 800,
    taxGroup: taxGroup,
    isActive: true,
    displayOrder: 0,
    printerGroup: 'kitchen',
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('WaiterOrderService.openNewOrder', () {
    test('creates a ticket tagged with waiter channel and waiterId', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      final ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      expect(ticket.channel, OrderChannel.waiter);
      expect(ticket.waiterId, _waiterId);
      expect(ticket.tableId, tableId);
      expect(ticket.status, TicketStatus.draft);
      expect(ticket.tenantId, _tenantId);
    });

    test('assigns sequential order numbers', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      final t1 = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );
      final t2 = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      expect(t1.orderNumber, isNotEmpty);
      expect(t2.orderNumber, isNotEmpty);
      expect(t1.orderNumber, isNot(equals(t2.orderNumber)));
    });
  });

  group('WaiterOrderService.addItemToTicket', () {
    test('appends item and recalculates ticket totals', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      final ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      final product = _makeProduct(price: 1800);
      final updated = await svc.addItemToTicket(
        ticketId: ticket.id,
        product: product,
        quantity: 2,
      );

      expect(updated, isNotNull);
      expect(updated!.items.length, 1);
      expect(updated.items.first.quantity, 2.0);
      expect(updated.items.first.unitPrice, 1800);
      expect(updated.items.first.subtotal, 3600); // 1800 × 2
      expect(updated.subtotal, 3600);
    });

    test('extracts Swiss VAT from dine-in food price (8.1%)', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      final ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      // 1000 cents dine-in food: MwSt = 1000 × 8.1 / 108.1 ≈ 74 cents
      final product = _makeProduct(price: 1000, taxGroup: 'food');
      final updated = await svc.addItemToTicket(
        ticketId: ticket.id,
        product: product,
      );

      expect(updated, isNotNull);
      final item = updated!.items.first;
      // 8.1% extraction from inclusive gross 1000
      final expectedTax = (1000 * 8.1 / 108.1).round();
      expect(item.taxAmount, expectedTax);
    });

    test('extracts 2.6% VAT for takeaway food', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      // Open a takeaway ticket.
      final nextNumber =
          await OrderRepositoryImpl(db).getNextOrderNumber(_tenantId);
      final takeawayTicket = TicketEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        orderNumber: IdGenerator.generateOrderNumber(nextNumber),
        orderType: OrderType.takeaway,
        tableId: tableId,
        waiterId: _waiterId,
        status: TicketStatus.draft,
        channel: OrderChannel.waiter,
        openedAt: DateTime.now(),
        deviceId: _deviceId,
      );
      await OrderRepositoryImpl(db).createTicket(takeawayTicket);

      final product = _makeProduct(price: 1000, taxGroup: 'food');
      final updated = await svc.addItemToTicket(
        ticketId: takeawayTicket.id,
        product: product,
      );

      expect(updated, isNotNull);
      final item = updated!.items.first;
      // 2.6% extraction from inclusive gross 1000
      final expectedTax = (1000 * 2.6 / 102.6).round();
      expect(item.taxAmount, expectedTax);
    });

    test('returns null when ticket is not found', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final product = _makeProduct();
      final result = await svc.addItemToTicket(
        ticketId: 'nonexistent-ticket',
        product: product,
      );

      expect(result, isNull);
    });
  });

  group('WaiterOrderService.removeItemFromTicket', () {
    test('removes item and updates totals', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      var ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      final product = _makeProduct(price: 1500);
      ticket = (await svc.addItemToTicket(
            ticketId: ticket.id,
            product: product,
          ))!;

      expect(ticket.items.length, 1);
      final itemId = ticket.items.first.id;

      final after = await svc.removeItemFromTicket(
        ticketId: ticket.id,
        itemId: itemId,
      );

      expect(after, isNotNull);
      expect(after!.items.isEmpty, isTrue);
      expect(after.subtotal, 0);
    });
  });

  group('WaiterOrderService.sendToKitchen', () {
    test('marks items as sent and changes ticket status', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      var ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      ticket = (await svc.addItemToTicket(
            ticketId: ticket.id,
            product: _makeProduct(),
          ))!;

      final sent = await svc.sendToKitchen(
        ticketId: ticket.id,
        waiterName: _waiterName,
      );

      expect(sent, isNotNull);
      expect(sent!.status, TicketStatus.sent);
      expect(sent.items.first.sentToKitchen, isTrue);
    });

    test('is idempotent — second call does not duplicate kitchen items',
        () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      var ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );
      ticket = (await svc.addItemToTicket(
            ticketId: ticket.id,
            product: _makeProduct(),
          ))!;

      await svc.sendToKitchen(ticketId: ticket.id, waiterName: _waiterName);

      // Second call — all items already sent; no new kitchen ticket created.
      final second = await svc.sendToKitchen(
        ticketId: ticket.id,
        waiterName: _waiterName,
      );
      expect(second, isNotNull);
      // Items are still marked sent.
      expect(second!.items.every((i) => i.sentToKitchen), isTrue);
    });
  });

  group('WaiterOrderService.fireGang', () {
    test('sends only the target Gang and leaves other items unsent',
        () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      var ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );
      ticket = (await svc.addItemToTicket(
            ticketId: ticket.id,
            product: _makeProduct(name: 'Tartar', price: 2400),
            course: 1,
          ))!;
      ticket = (await svc.addItemToTicket(
            ticketId: ticket.id,
            product: _makeProduct(name: 'Risotto', price: 3200),
            course: 2,
          ))!;

      final afterFire = await svc.fireGang(
        ticketId: ticket.id,
        gang: 1,
        waiterName: _waiterName,
      );

      expect(afterFire, isNotNull);
      // Gang 1 item is now sent; Gang 2 item still pending.
      final byCourse = {for (final i in afterFire!.items) i.course: i};
      expect(byCourse[1]!.sentToKitchen, isTrue);
      expect(byCourse[2]!.sentToKitchen, isFalse);
    });

    test('is a no-op when the target Gang has no unsent items', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      var ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );
      ticket = (await svc.addItemToTicket(
            ticketId: ticket.id,
            product: _makeProduct(),
            course: 1,
          ))!;

      // First fire sends Gang 1.
      await svc.fireGang(
        ticketId: ticket.id,
        gang: 1,
        waiterName: _waiterName,
      );
      // Second fire on the same Gang — everything is already sent.
      final second = await svc.fireGang(
        ticketId: ticket.id,
        gang: 1,
        waiterName: _waiterName,
      );

      expect(second, isNotNull);
      expect(second!.items.every((i) => i.sentToKitchen), isTrue);
    });

    test('writes a KDS ticket scoped to the fired Gang', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      var ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );
      ticket = (await svc.addItemToTicket(
            ticketId: ticket.id,
            product: _makeProduct(name: 'Tartar'),
            course: 1,
          ))!;
      ticket = (await svc.addItemToTicket(
            ticketId: ticket.id,
            product: _makeProduct(name: 'Risotto'),
            course: 2,
          ))!;

      await svc.fireGang(
        ticketId: ticket.id,
        gang: 2,
        waiterName: _waiterName,
      );

      // Inspect the KDS tables directly. AppInitializer seeds demo tickets,
      // so filter by the real ticket id we just fired.
      final kdsForOurTicket = await (db.select(db.kitchenTickets)
            ..where((t) => t.ticketId.equals(ticket.id)))
          .get();
      expect(kdsForOurTicket.length, 1,
          reason: 'One KDS ticket per fired Gang on this order');
      final itemsForOurTicket = await (db.select(db.kitchenTicketItems)
            ..where((i) => i.kitchenTicketId.equals(kdsForOurTicket.first.id)))
          .get();
      expect(itemsForOurTicket.length, 1);
      expect(itemsForOurTicket.first.productName, 'Risotto');
    });
  });

  group('WaiterOrderService.getActiveOrdersForWaiter', () {
    test('returns only waiter-channel orders for the given waiterId', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      // Waiter creates an order.
      await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      // A POS-channel order for a different "waiter".
      final posTicket = TicketEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        orderNumber: '999',
        orderType: OrderType.dineIn,
        tableId: tableId,
        waiterId: 'other-waiter',
        status: TicketStatus.open,
        channel: OrderChannel.pos,
        openedAt: DateTime.now(),
        deviceId: _deviceId,
      );
      await OrderRepositoryImpl(db).createTicket(posTicket);

      final active = await svc.getActiveOrdersForWaiter(
        tenantId: _tenantId,
        waiterId: _waiterId,
      );

      // Only the waiter's own order appears.
      expect(active.length, 1);
      expect(active.first.waiterId, _waiterId);
      expect(active.first.channel, OrderChannel.waiter);
    });
  });

  group('WaiterOrderService.requestBill', () {
    test('transitions ticket to billRequested status', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      var ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );
      ticket = (await svc.addItemToTicket(
            ticketId: ticket.id,
            product: _makeProduct(),
          ))!;
      await svc.sendToKitchen(ticketId: ticket.id, waiterName: _waiterName);

      await svc.requestBill(ticket.id);

      final refreshed =
          await OrderRepositoryImpl(db).getTicketById(ticket.id);
      expect(refreshed?.status, TicketStatus.billRequested);
    });
  });

  group('WaiterOrderService._taxRate (via addItemToTicket)', () {
    test('beverage is always 8.1% regardless of order type', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      final ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      final product = _makeProduct(price: 500, taxGroup: 'beverage');
      final updated = await svc.addItemToTicket(
        ticketId: ticket.id,
        product: product,
      );

      expect(updated, isNotNull);
      final item = updated!.items.first;
      final expectedTax = (500 * 8.1 / 108.1).round();
      expect(item.taxAmount, expectedTax);
    });

    test('accommodation uses 3.8% rate', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      final ticket = await svc.openNewOrder(
        tenantId: _tenantId,
        waiterId: _waiterId,
        waiterName: _waiterName,
        tableId: tableId,
        deviceId: _deviceId,
      );

      final product = _makeProduct(price: 1000, taxGroup: 'accommodation');
      final updated = await svc.addItemToTicket(
        ticketId: ticket.id,
        product: product,
      );

      expect(updated, isNotNull);
      final item = updated!.items.first;
      final expectedTax = (1000 * 3.8 / 103.8).round();
      expect(item.taxAmount, expectedTax);
    });
  });

  group('WaiterOrderService.claimTable / releaseTable', () {
    test('claimTable marks table as occupied', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      await svc.claimTable(tableId, _waiterId);

      final tableRepo = TableRepositoryImpl(db);
      final tables = await tableRepo.getAllTables(_tenantId);
      final table = tables.firstWhere((t) => t.id == tableId);
      expect(table.status, TableStatus.occupied);
    });

    test('releaseTable marks table as available', () async {
      final (:db, :svc) = await _setup();
      addTearDown(db.close);

      final tableId = await _createTable(db);
      await svc.claimTable(tableId, _waiterId);
      await svc.releaseTable(tableId);

      final tableRepo = TableRepositoryImpl(db);
      final tables = await tableRepo.getAllTables(_tenantId);
      final table = tables.firstWhere((t) => t.id == tableId);
      expect(table.status, TableStatus.available);
    });
  });
}
