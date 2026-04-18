/// Repository integration tests for OrderRepositoryImpl.
///
/// Uses an in-memory Drift database — no mocking of SQL layer.
/// Covers ticket CRUD, item management, status transitions, and total
/// recalculation with modifiers.
///
/// Run with:
///   flutter test test/features/orders/data/order_repository_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-repo-test';
const _deviceId = 'DEV-REPO-01';

OrderRepositoryImpl _makeRepo(AppDatabase db) => OrderRepositoryImpl(db);

TicketEntity _makeTicket({
  String? id,
  OrderType orderType = OrderType.dineIn,
  TicketStatus status = TicketStatus.draft,
  List<OrderItemEntity> items = const [],
  DiscountType discountType = DiscountType.none,
  int discountValue = 0,
}) {
  return TicketEntity(
    id: id ?? IdGenerator.generateId(),
    tenantId: _tenantId,
    orderNumber: IdGenerator.generateId().substring(0, 6),
    orderType: orderType,
    status: status,
    openedAt: DateTime(2026, 3, 20, 10, 0),
    deviceId: _deviceId,
    items: items,
    discountType: discountType,
    discountValue: discountValue,
  );
}

OrderItemEntity _makeItem({
  String? id,
  String? ticketId,
  String productName = 'Adana Kebap',
  double quantity = 1,
  int unitPrice = 2500,
  int subtotal = 2500,
  List<OrderItemModifierEntity> modifiers = const [],
}) {
  final itemId = id ?? IdGenerator.generateId();
  return OrderItemEntity(
    id: itemId,
    tenantId: _tenantId,
    ticketId: ticketId ?? 'ticket-placeholder',
    productId: 'prod-${itemId.substring(0, 6)}',
    productName: productName,
    quantity: quantity,
    unitPrice: unitPrice,
    subtotal: subtotal,
    taxGroup: 'food',
    modifiers: modifiers,
  );
}

OrderItemModifierEntity _makeModifier({
  String? id,
  String? orderItemId,
  String name = 'Extra Cheese',
  int priceDelta = 200,
}) {
  final modId = id ?? IdGenerator.generateId();
  return OrderItemModifierEntity(
    id: modId,
    orderItemId: orderItemId ?? 'item-placeholder',
    modifierId: 'mod-${modId.substring(0, 6)}',
    modifierName: name,
    priceDelta: priceDelta,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('OrderRepositoryImpl — Ticket CRUD', () {
    late AppDatabase db;
    late OrderRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase.createInMemory();
      repo = _makeRepo(db);
    });

    tearDown(() async => db.close());

    // -----------------------------------------------------------------------
    // createTicket
    // -----------------------------------------------------------------------

    test('createTicket persists a ticket with no items', () async {
      final ticket = _makeTicket();
      final created = await repo.createTicket(ticket);

      expect(created.id, equals(ticket.id));
      expect(created.tenantId, equals(_tenantId));
      expect(created.orderType, equals(OrderType.dineIn));
      expect(created.status, equals(TicketStatus.draft));
      expect(created.items, isEmpty);
    });

    test('createTicket persists a ticket with two items', () async {
      final ticketId = IdGenerator.generateId();
      final items = [
        _makeItem(ticketId: ticketId, productName: 'Adana Kebap', unitPrice: 2500, subtotal: 2500),
        _makeItem(ticketId: ticketId, productName: 'Ayran', unitPrice: 500, subtotal: 500),
      ];
      final ticket = _makeTicket(id: ticketId, items: items);
      final created = await repo.createTicket(ticket);

      expect(created.items.length, equals(2));
      expect(created.items.map((i) => i.productName),
          containsAll(['Adana Kebap', 'Ayran']));
    });

    test('createTicket persists items with modifiers', () async {
      final ticketId = IdGenerator.generateId();
      final itemId = IdGenerator.generateId();
      final modifier = _makeModifier(
        orderItemId: itemId,
        name: 'Extra Cheese',
        priceDelta: 300,
      );
      final item = _makeItem(
        id: itemId,
        ticketId: ticketId,
        productName: 'Pizza',
        unitPrice: 1800,
        subtotal: 2100,
        modifiers: [modifier],
      );
      final ticket = _makeTicket(id: ticketId, items: [item]);
      final created = await repo.createTicket(ticket);

      expect(created.items.length, equals(1));
      expect(created.items.first.modifiers.length, equals(1));
      expect(created.items.first.modifiers.first.modifierName, equals('Extra Cheese'));
      expect(created.items.first.modifiers.first.priceDelta, equals(300));
    });

    // -----------------------------------------------------------------------
    // getTicketById
    // -----------------------------------------------------------------------

    test('getTicketById returns null for missing ticket', () async {
      final result = await repo.getTicketById('nonexistent-id');
      expect(result, isNull);
    });

    test('getTicketById returns persisted ticket', () async {
      final ticket = _makeTicket();
      await repo.createTicket(ticket);

      final fetched = await repo.getTicketById(ticket.id);
      expect(fetched, isNotNull);
      expect(fetched!.id, equals(ticket.id));
      expect(fetched.orderType, equals(OrderType.dineIn));
    });

    // -----------------------------------------------------------------------
    // getOpenTickets
    // -----------------------------------------------------------------------

    test('getOpenTickets excludes completed and cancelled tickets', () async {
      final t1 = await repo.createTicket(_makeTicket(status: TicketStatus.draft));
      final t2 = await repo.createTicket(_makeTicket(status: TicketStatus.sent));
      final t3 = await repo.createTicket(_makeTicket(status: TicketStatus.completed));
      final t4 = await repo.createTicket(_makeTicket(status: TicketStatus.cancelled));

      final open = await repo.getOpenTickets(_tenantId);
      final openIds = open.map((t) => t.id).toList();

      expect(openIds, contains(t1.id));
      expect(openIds, contains(t2.id));
      expect(openIds, isNot(contains(t3.id)));
      expect(openIds, isNot(contains(t4.id)));
    });

    test('getOpenTickets returns tickets ordered by most recent first', () async {
      final t1 = await repo.createTicket(_makeTicket());
      await Future.delayed(const Duration(milliseconds: 5));
      final t2 = await repo.createTicket(_makeTicket());

      final open = await repo.getOpenTickets(_tenantId);

      // Both should be present; second (more recent) should be first.
      expect(open.first.id, equals(t2.id));
      expect(open.last.id, equals(t1.id));
    });

    // -----------------------------------------------------------------------
    // updateTicketStatus
    // -----------------------------------------------------------------------

    test('updateTicketStatus transitions draft → sent', () async {
      final ticket = await repo.createTicket(_makeTicket());
      await repo.updateTicketStatus(ticket.id, TicketStatus.sent);

      final updated = await repo.getTicketById(ticket.id);
      expect(updated!.status, equals(TicketStatus.sent));
    });

    test('updateTicketStatus sets closedAt when completing', () async {
      final ticket = await repo.createTicket(_makeTicket());
      await repo.updateTicketStatus(ticket.id, TicketStatus.completed);

      // Verify via direct DB query.
      final row = await (db.select(db.tickets)
            ..where((t) => t.id.equals(ticket.id)))
          .getSingle();
      expect(row.closedAt, isNotNull);
    });

    test('updateTicketStatus transitions through full lifecycle', () async {
      final ticket = await repo.createTicket(_makeTicket());

      for (final status in [
        TicketStatus.open,
        TicketStatus.sent,
        TicketStatus.inProgress,
        TicketStatus.ready,
        TicketStatus.served,
        TicketStatus.completed,
      ]) {
        await repo.updateTicketStatus(ticket.id, status);
        final updated = await repo.getTicketById(ticket.id);
        expect(updated!.status, equals(status),
            reason: 'Expected status $status after transition');
      }
    });
  });

  // =========================================================================
  // Item management
  // =========================================================================

  group('OrderRepositoryImpl — Item Management', () {
    late AppDatabase db;
    late OrderRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase.createInMemory();
      repo = _makeRepo(db);
    });

    tearDown(() async => db.close());

    test('addItemToTicket adds an item and recalculates totals', () async {
      final ticket = await repo.createTicket(_makeTicket());
      final item = _makeItem(
        ticketId: ticket.id,
        productName: 'Adana Kebap',
        unitPrice: 2500,
        subtotal: 2500,
      );

      await repo.addItemToTicket(ticket.id, item);

      final updated = await repo.getTicketById(ticket.id);
      expect(updated!.items.length, equals(1));
      expect(updated.items.first.productName, equals('Adana Kebap'));
    });

    test('addItemToTicket adds item with modifier', () async {
      final ticket = await repo.createTicket(_makeTicket());
      final itemId = IdGenerator.generateId();
      final modifier = _makeModifier(
        orderItemId: itemId,
        name: 'Spicy',
        priceDelta: 100,
      );
      final item = _makeItem(
        id: itemId,
        ticketId: ticket.id,
        productName: 'Burger',
        unitPrice: 1800,
        subtotal: 1900,
        modifiers: [modifier],
      );

      await repo.addItemToTicket(ticket.id, item);

      final updated = await repo.getTicketById(ticket.id);
      expect(updated!.items.first.modifiers.length, equals(1));
      expect(updated.items.first.modifiers.first.modifierName, equals('Spicy'));
    });

    test('removeItemFromTicket soft-deletes the item', () async {
      final ticketId = IdGenerator.generateId();
      final item = _makeItem(ticketId: ticketId, productName: 'Pizza');
      final ticket = _makeTicket(id: ticketId, items: [item]);
      await repo.createTicket(ticket);

      await repo.removeItemFromTicket(item.id);

      final updated = await repo.getTicketById(ticketId);
      expect(updated!.items, isEmpty);
    });

    test('removeItemFromTicket with nonexistent id is a no-op', () async {
      // Should not throw.
      await expectLater(
        repo.removeItemFromTicket('nonexistent-item-id'),
        completes,
      );
    });

    test('updateItemQuantity updates item and recalculates totals', () async {
      final ticketId = IdGenerator.generateId();
      final item = _makeItem(
        ticketId: ticketId,
        productName: 'Tea',
        unitPrice: 400,
        subtotal: 400,
      );
      final ticket = _makeTicket(id: ticketId, items: [item]);
      await repo.createTicket(ticket);

      await repo.updateItemQuantity(item.id, 3);

      final updated = await repo.getTicketById(ticketId);
      expect(updated!.items.first.quantity, equals(3));
    });
  });

  // =========================================================================
  // Total recalculation
  // =========================================================================

  group('OrderRepositoryImpl — Total Calculation', () {
    late AppDatabase db;
    late OrderRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase.createInMemory();
      repo = _makeRepo(db);
    });

    tearDown(() async => db.close());

    test('calculateTicketTotals sums item subtotals', () async {
      final ticketId = IdGenerator.generateId();
      final items = [
        _makeItem(ticketId: ticketId, productName: 'Item A', unitPrice: 1000, subtotal: 1000),
        _makeItem(ticketId: ticketId, productName: 'Item B', unitPrice: 1500, subtotal: 1500),
      ];
      final ticket = _makeTicket(id: ticketId, items: items);
      await repo.createTicket(ticket);

      await repo.calculateTicketTotals(ticketId);

      final row = await (db.select(db.tickets)
            ..where((t) => t.id.equals(ticketId)))
          .getSingle();
      expect(row.subtotal, equals(2500));
    });

    test('calculateTicketTotals handles empty item list', () async {
      final ticket = await repo.createTicket(_makeTicket());
      await repo.calculateTicketTotals(ticket.id);

      final row = await (db.select(db.tickets)
            ..where((t) => t.id.equals(ticket.id)))
          .getSingle();
      expect(row.subtotal, equals(0));
      expect(row.total, equals(0));
    });
  });

  // =========================================================================
  // Table-scoped queries
  // =========================================================================

  group('OrderRepositoryImpl — Table Queries', () {
    late AppDatabase db;
    late OrderRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase.createInMemory();
      repo = _makeRepo(db);
    });

    tearDown(() async => db.close());

    test('getTicketsByTable returns open tickets for the given table', () async {
      const tableId = 'table-001';

      // Create a ticket assigned to the table via the entity's tableId field.
      final ticket = TicketEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        orderNumber: '0001',
        orderType: OrderType.dineIn,
        tableId: tableId,
        status: TicketStatus.draft,
        openedAt: DateTime(2026, 3, 20, 11, 0),
        deviceId: _deviceId,
      );
      await repo.createTicket(ticket);

      final tickets = await repo.getTicketsByTable(tableId);
      expect(tickets.any((t) => t.id == ticket.id), isTrue);
    });

    test('getTicketsByTable excludes tickets from other tables', () async {
      const tableId = 'table-002';
      const otherTableId = 'table-003';

      final t1 = TicketEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        orderNumber: '0002',
        orderType: OrderType.dineIn,
        tableId: tableId,
        status: TicketStatus.draft,
        openedAt: DateTime(2026, 3, 20, 12, 0),
        deviceId: _deviceId,
      );
      final t2 = TicketEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        orderNumber: '0003',
        orderType: OrderType.dineIn,
        tableId: otherTableId,
        status: TicketStatus.draft,
        openedAt: DateTime(2026, 3, 20, 12, 0),
        deviceId: _deviceId,
      );
      await repo.createTicket(t1);
      await repo.createTicket(t2);

      final tickets = await repo.getTicketsByTable(tableId);
      expect(tickets.any((t) => t.id == t1.id), isTrue);
      expect(tickets.any((t) => t.id == t2.id), isFalse);
    });

    test('getTicketsByTable excludes completed tickets', () async {
      const tableId = 'table-004';
      final ticket = TicketEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        orderNumber: '0004',
        orderType: OrderType.dineIn,
        tableId: tableId,
        status: TicketStatus.completed,
        openedAt: DateTime(2026, 3, 20, 13, 0),
        deviceId: _deviceId,
      );
      await repo.createTicket(ticket);
      // Explicitly mark as completed.
      await repo.updateTicketStatus(ticket.id, TicketStatus.completed);

      final tickets = await repo.getTicketsByTable(tableId);
      expect(tickets.any((t) => t.id == ticket.id), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // watchTicketById — reactive stream powering KDS→waiter badge sync.
  //
  // Subscriptions are not awaited on cancel: the underlying generator is
  // suspended in `await for (_ in tableUpdates)` and Drift's broadcast stream
  // does not fully release until the database closes. Unawaited cancel lets
  // the test complete; tearDown's db.close() performs the final cleanup.
  // -------------------------------------------------------------------------

  group('OrderRepositoryImpl — watchTicketById', () {
    late AppDatabase db;
    late OrderRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase.createInMemory();
      repo = _makeRepo(db);
    });

    tearDown(() async => db.close());

    test('emits initial state on subscribe then re-emits on item status flip',
        () async {
      final ticketId = IdGenerator.generateId();
      final itemId = IdGenerator.generateId();
      final item = _makeItem(
        id: itemId,
        ticketId: ticketId,
        productName: 'Köfte',
        unitPrice: 2000,
        subtotal: 2000,
      );
      final ticket = _makeTicket(id: ticketId, items: [item]);
      await repo.createTicket(ticket);

      final emitted = <TicketEntity?>[];
      final sub = repo.watchTicketById(ticketId).listen(emitted.add);
      // The sync closure is load-bearing: cancel() on this async* generator
      // suspends inside Drift's tableUpdates await-for and never resolves, so
      // a tearoff would make addTearDown await a never-completing future.
      // db.close() in the group tearDown performs the real cleanup.
      addTearDown(() { // ignore: unnecessary_lambdas
        sub.cancel();
      });

      // Let the initial yield propagate.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(emitted, hasLength(1),
          reason: 'stream must emit current state on subscribe');
      expect(emitted.first?.items.first.status, OrderItemStatus.ordered);

      // KDS-side flip: mark the item ready.
      await repo.updateItemStatus(itemId, OrderItemStatus.ready);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emitted.length, greaterThanOrEqualTo(2),
          reason: 'item status flip must re-trigger an emission');
      expect(emitted.last?.items.first.status, OrderItemStatus.ready,
          reason: 'watcher must surface the new ready state');
    });

    test('emits null for a ticket that does not exist', () async {
      final emitted = <TicketEntity?>[];
      final sub =
          repo.watchTicketById('ghost-ticket').listen(emitted.add);
      // The sync closure is load-bearing: cancel() on this async* generator
      // suspends inside Drift's tableUpdates await-for and never resolves, so
      // a tearoff would make addTearDown await a never-completing future.
      // db.close() in the group tearDown performs the real cleanup.
      addTearDown(() { // ignore: unnecessary_lambdas
        sub.cancel();
      });

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emitted, hasLength(1));
      expect(emitted.first, isNull,
          reason: 'missing ticket resolves to a null emission, not an error');
    });

    test('re-emits on ticket-level status change (e.g. bill requested)',
        () async {
      final ticket = await repo.createTicket(_makeTicket());

      final emitted = <TicketEntity?>[];
      final sub = repo.watchTicketById(ticket.id).listen(emitted.add);
      // The sync closure is load-bearing: cancel() on this async* generator
      // suspends inside Drift's tableUpdates await-for and never resolves, so
      // a tearoff would make addTearDown await a never-completing future.
      // db.close() in the group tearDown performs the real cleanup.
      addTearDown(() { // ignore: unnecessary_lambdas
        sub.cancel();
      });

      await Future<void>.delayed(const Duration(milliseconds: 20));

      await repo.updateTicketStatus(ticket.id, TicketStatus.billRequested);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emitted.length, greaterThanOrEqualTo(2));
      expect(emitted.last?.status, TicketStatus.billRequested);
    });
  });
}
