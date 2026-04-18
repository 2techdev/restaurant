/// Unit tests for [KitchenRepositoryImpl].
///
/// Uses an in-memory Drift database ([AppDatabase.createInMemory()]) so no
/// file I/O or mocking is required. Tests cover:
///   - createTicketFromOrder: ticket + item rows written correctly
///   - watchActiveTickets: only pending/preparing tickets are emitted
///   - completeTicket: status → 'served', ticket leaves active stream
///   - completedTodayCount: counts only today's served tickets
///   - modifier text snapshot: comma-separated modifier names stored verbatim
///   - table name resolution: looks up table name from restaurant_tables
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/kitchen/data/repositories/kitchen_repository_impl.dart';
import 'package:gastrocore_pos/features/kitchen/domain/entities/kitchen_ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

AppDatabase _openInMemory() => AppDatabase(NativeDatabase.memory());

TicketEntity _ticket({
  String id = 'ticket-1',
  String tenantId = 'tenant-1',
  String orderNumber = '0001',
  String? tableId,
}) {
  return TicketEntity(
    id: id,
    tenantId: tenantId,
    orderNumber: orderNumber,
    orderType: OrderType.dineIn,
    status: TicketStatus.sent,
    channel: OrderChannel.pos,
    openedAt: DateTime.now(),
    tableId: tableId,
    deviceId: 'DEV-01',
  );
}

OrderItemEntity _item({
  String id = 'item-1',
  String ticketId = 'ticket-1',
  String productName = 'Burger',
  double quantity = 2,
  List<OrderItemModifierEntity> modifiers = const [],
  String? notes,
}) {
  return OrderItemEntity(
    id: id,
    tenantId: 'tenant-1',
    ticketId: ticketId,
    productId: 'prod-1',
    productName: productName,
    quantity: quantity,
    unitPrice: 1500,
    subtotal: (1500 * quantity).round(),
    modifiers: modifiers,
    notes: notes,
  );
}

OrderItemModifierEntity _modifier(String name) {
  return OrderItemModifierEntity(
    id: 'mod-${name.hashCode}',
    orderItemId: 'item-1',
    modifierId: 'moddef-1',
    modifierName: name,
    priceDelta: 0,
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Inserts a bare [Ticket] row so [completeTicket] / [recallTicket] can
/// update its status. The status defaults to 'sent_to_kitchen'.
Future<void> _seedTicketRow(
  AppDatabase db, {
  String id = 'ticket-1',
  String tenantId = 'tenant-1',
  String status = 'sent_to_kitchen',
}) async {
  final now = DateTime.now();
  // In Drift's insert() constructor: required (non-default) columns are raw
  // values; columns with defaults take Value<T> (absent = use default).
  await db.into(db.tickets).insert(
        TicketsCompanion.insert(
          id: id,
          tenantId: tenantId,
          orderNumber: 1,
          status: Value(status),
          channel: const Value('pos'),
          openedAt: now,
          createdAt: now,
          updatedAt: now,
          deviceId: 'DEV-01',
        ),
      );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;
  late KitchenRepositoryImpl repo;

  setUp(() {
    db = _openInMemory();
    repo = KitchenRepositoryImpl(db);
  });

  tearDown(() async {
    await db.close();
  });

  // -------------------------------------------------------------------------
  group('createTicketFromOrder', () {
    test('writes one KitchenTicket row with correct fields', () async {
      final ticket = _ticket(tenantId: 'tenant-1', orderNumber: '0042');
      final items = [_item(id: 'item-1', productName: 'Pizza')];

      await repo.createTicketFromOrder(
        ticket: ticket,
        items: items,
        waiterName: 'Marco',
      );

      final rows = await db.select(db.kitchenTickets).get();
      expect(rows, hasLength(1));
      expect(rows.first.tenantId, 'tenant-1');
      expect(rows.first.ticketId, 'ticket-1');
      expect(rows.first.waiterName, 'Marco');
      expect(rows.first.orderNumber, 42);
      expect(rows.first.status, 'pending');
      expect(rows.first.printerGroup, 'kitchen');
    });

    test('writes one KitchenTicketItem row per order item', () async {
      final ticket = _ticket();
      final items = [
        _item(id: 'item-1', productName: 'Burger', quantity: 2),
        _item(id: 'item-2', productName: 'Fries', quantity: 1),
      ];

      await repo.createTicketFromOrder(ticket: ticket, items: items);

      final itemRows = await db.select(db.kitchenTicketItems).get();
      expect(itemRows, hasLength(2));
      final names = itemRows.map((r) => r.productName).toSet();
      expect(names, containsAll(['Burger', 'Fries']));
    });

    test('snapshots modifier names as comma-separated text', () async {
      final ticket = _ticket();
      final item = _item(
        modifiers: [_modifier('Medium Rare'), _modifier('No Onion')],
      );

      await repo.createTicketFromOrder(ticket: ticket, items: [item]);

      final itemRow =
          await db.select(db.kitchenTicketItems).getSingle();
      expect(itemRow.modifiersText, 'Medium Rare, No Onion');
    });

    test('stores null modifiersText when item has no modifiers', () async {
      final ticket = _ticket();
      final item = _item(modifiers: []);

      await repo.createTicketFromOrder(ticket: ticket, items: [item]);

      final itemRow =
          await db.select(db.kitchenTicketItems).getSingle();
      expect(itemRow.modifiersText, isNull);
    });

    test('stores item notes', () async {
      final ticket = _ticket();
      final item = _item(notes: 'No salt please');

      await repo.createTicketFromOrder(ticket: ticket, items: [item]);

      final itemRow =
          await db.select(db.kitchenTicketItems).getSingle();
      expect(itemRow.notes, 'No salt please');
    });

    test('does nothing when items list is empty', () async {
      await repo.createTicketFromOrder(
        ticket: _ticket(),
        items: const [],
      );

      final rows = await db.select(db.kitchenTickets).get();
      expect(rows, isEmpty);
    });

    test(
        'routes ticket to the shared station when all items share a '
        'printerGroup', () async {
      final now = DateTime.now();
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'cat-1',
              tenantId: 'tenant-1',
              name: 'Grill',
              createdAt: now,
              updatedAt: now,
            ),
          );
      // Two products both routed to the grill station.
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'prod-1',
              tenantId: 'tenant-1',
              categoryId: 'cat-1',
              name: 'Ribeye',
              price: 3200,
              createdAt: now,
              updatedAt: now,
              printerGroup: const Value('grill'),
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'prod-2',
              tenantId: 'tenant-1',
              categoryId: 'cat-1',
              name: 'Bratwurst',
              price: 1400,
              createdAt: now,
              updatedAt: now,
              printerGroup: const Value('grill'),
            ),
          );

      final ticket = _ticket();
      await repo.createTicketFromOrder(
        ticket: ticket,
        items: [
          _item(id: 'i1'),
          _item(id: 'i2').copyWith(productId: 'prod-2'),
        ],
      );

      final kt = await db.select(db.kitchenTickets).getSingle();
      expect(kt.printerGroup, 'grill');
    });

    test(
        'falls back to kitchen when items span multiple stations',
        () async {
      final now = DateTime.now();
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'cat-1',
              tenantId: 'tenant-1',
              name: 'Mixed',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'prod-1',
              tenantId: 'tenant-1',
              categoryId: 'cat-1',
              name: 'Salad',
              price: 1200,
              createdAt: now,
              updatedAt: now,
              printerGroup: const Value('cold'),
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'prod-2',
              tenantId: 'tenant-1',
              categoryId: 'cat-1',
              name: 'Steak',
              price: 3200,
              createdAt: now,
              updatedAt: now,
              printerGroup: const Value('grill'),
            ),
          );

      final ticket = _ticket();
      await repo.createTicketFromOrder(
        ticket: ticket,
        items: [
          _item(id: 'i1'),
          _item(id: 'i2').copyWith(productId: 'prod-2'),
        ],
      );

      final kt = await db.select(db.kitchenTickets).getSingle();
      expect(kt.printerGroup, 'kitchen');
    });

    test('resolves table name from restaurant_tables', () async {
      // Seed a tenant and a table row first.
      await db.into(db.tenants).insert(
            TenantsCompanion.insert(
              id: 'tenant-1',
              name: 'Test Restaurant',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      await db.into(db.floors).insert(
            FloorsCompanion.insert(
              id: 'floor-1',
              tenantId: 'tenant-1',
              name: 'Ground Floor',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      await db.into(db.restaurantTables).insert(
            RestaurantTablesCompanion.insert(
              id: 'table-1',
              tenantId: 'tenant-1',
              floorId: 'floor-1',
              name: 'T-07',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      final ticket = _ticket(tableId: 'table-1');
      await repo.createTicketFromOrder(
        ticket: ticket,
        items: [_item()],
      );

      final ktRow = await db.select(db.kitchenTickets).getSingle();
      expect(ktRow.kitchenTableName, 'T-07');
    });
  });

  // -------------------------------------------------------------------------
  group('watchActiveTickets', () {
    test('emits only pending and preparing tickets', () async {
      final ticket = _ticket();

      // pending ticket
      await repo.createTicketFromOrder(ticket: ticket, items: [_item()]);

      final result = await repo.watchActiveTickets('tenant-1').first;
      expect(result, hasLength(1));
      expect(result.first.status, KitchenTicketStatus.pending);
    });

    test('emits empty list when no active tickets', () async {
      final result = await repo.watchActiveTickets('tenant-1').first;
      expect(result, isEmpty);
    });

    test('maps items correctly in stream', () async {
      final ticket = _ticket();
      final items = [
        _item(id: 'item-1', productName: 'Steak', quantity: 1),
        _item(id: 'item-2', productName: 'Salad', quantity: 2),
      ];

      await repo.createTicketFromOrder(ticket: ticket, items: items);

      final result = await repo.watchActiveTickets('tenant-1').first;
      expect(result.first.items, hasLength(2));
      final names =
          result.first.items.map((i) => i.productName).toSet();
      expect(names, containsAll(['Steak', 'Salad']));
    });

    test('excludes completed (served) tickets', () async {
      await repo.createTicketFromOrder(
          ticket: _ticket(), items: [_item()]);

      // Fetch the kitchen ticket id.
      final ktRow = await db.select(db.kitchenTickets).getSingle();
      await repo.completeTicket(ktRow.id);

      final result = await repo.watchActiveTickets('tenant-1').first;
      expect(result, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('completeTicket', () {
    test('sets status to served and records completedAt', () async {
      await repo.createTicketFromOrder(
          ticket: _ticket(), items: [_item()]);

      final ktRow = await db.select(db.kitchenTickets).getSingle();
      await repo.completeTicket(ktRow.id);

      final updated = await db.select(db.kitchenTickets).getSingle();
      expect(updated.status, 'served');
      expect(updated.completedAt, isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  group('completeTicket — parent ticket status', () {
    test('sets parent ticket to fully_served when all kitchen tickets served',
        () async {
      await _seedTicketRow(db);
      await repo.createTicketFromOrder(
          ticket: _ticket(), items: [_item()]);

      final ktRow = await db.select(db.kitchenTickets).getSingle();
      await repo.completeTicket(ktRow.id);

      final ticketRow = await db.select(db.tickets).getSingle();
      expect(ticketRow.status, 'fully_served');
    });

    test(
        'sets parent ticket to partially_served when other kitchen tickets remain',
        () async {
      await _seedTicketRow(db);
      // Create two kitchen tickets for the same parent ticket.
      await repo.createTicketFromOrder(
          ticket: _ticket(), items: [_item(id: 'item-1')]);
      // Simulate a second kitchen ticket (bar station) for the same ticketId.
      final now = DateTime.now();
      await db.into(db.kitchenTickets).insert(
            KitchenTicketsCompanion.insert(
              id: 'kt-bar-1',
              tenantId: 'tenant-1',
              ticketId: 'ticket-1',
              orderNumber: 1,
              printerGroup: const Value('bar'),
              status: const Value('pending'),
              sentAt: now,
              createdAt: now,
            ),
          );

      // Complete only the first kitchen ticket (kitchen station).
      final ktRows = await db.select(db.kitchenTickets).get();
      final kitchenKt =
          ktRows.firstWhere((r) => r.printerGroup == 'kitchen');
      await repo.completeTicket(kitchenKt.id);

      final ticketRow = await db.select(db.tickets).getSingle();
      expect(ticketRow.status, 'partially_served');
    });

    test('does not downgrade a ticket already past fully_served', () async {
      await _seedTicketRow(db, status: 'fully_paid');
      await repo.createTicketFromOrder(
          ticket: _ticket(), items: [_item()]);

      final ktRow = await db.select(db.kitchenTickets).getSingle();
      await repo.completeTicket(ktRow.id);

      // Status must stay 'fully_paid' — not regressed by KDS bump.
      final ticketRow = await db.select(db.tickets).getSingle();
      expect(ticketRow.status, 'fully_paid');
    });
  });

  // -------------------------------------------------------------------------
  group('recallTicket', () {
    test('sets status back to preparing and clears completedAt', () async {
      await _seedTicketRow(db);
      await repo.createTicketFromOrder(
          ticket: _ticket(), items: [_item()]);

      final ktRow = await db.select(db.kitchenTickets).getSingle();
      await repo.completeTicket(ktRow.id);
      await repo.recallTicket(ktRow.id);

      final recalled = await db.select(db.kitchenTickets).getSingle();
      expect(recalled.status, 'preparing');
      expect(recalled.completedAt, isNull);
    });

    test('reverts parent ticket from fully_served to sent_to_kitchen',
        () async {
      await _seedTicketRow(db);
      await repo.createTicketFromOrder(
          ticket: _ticket(), items: [_item()]);

      final ktRow = await db.select(db.kitchenTickets).getSingle();
      await repo.completeTicket(ktRow.id); // → fully_served
      await repo.recallTicket(ktRow.id); // → sent_to_kitchen

      final ticketRow = await db.select(db.tickets).getSingle();
      expect(ticketRow.status, 'sent_to_kitchen');
    });

    test('reverts parent ticket from partially_served to sent_to_kitchen',
        () async {
      await _seedTicketRow(db, status: 'partially_served');
      await repo.createTicketFromOrder(
          ticket: _ticket(), items: [_item()]);

      final ktRow = await db.select(db.kitchenTickets).getSingle();
      await repo.recallTicket(ktRow.id);

      final ticketRow = await db.select(db.tickets).getSingle();
      expect(ticketRow.status, 'sent_to_kitchen');
    });
  });

  // -------------------------------------------------------------------------
  group('watchActiveTickets — tenantId scoping', () {
    test('does not return tickets from a different tenant', () async {
      // Create a kitchen ticket for tenant-2.
      final now = DateTime.now();
      await db.into(db.kitchenTickets).insert(
            KitchenTicketsCompanion.insert(
              id: 'kt-other',
              tenantId: 'tenant-2',
              ticketId: 'ticket-x',
              orderNumber: 99,
              status: const Value('pending'),
              sentAt: now,
              createdAt: now,
            ),
          );

      // Watch as tenant-1 — should see nothing.
      final result = await repo.watchActiveTickets('tenant-1').first;
      expect(result, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('watchCompletedTodayCount', () {
    test('counts served tickets completed today', () async {
      await repo.createTicketFromOrder(
          ticket: _ticket(), items: [_item()]);

      final ktRow = await db.select(db.kitchenTickets).getSingle();
      await repo.completeTicket(ktRow.id);

      final count =
          await repo.watchCompletedTodayCount('tenant-1').first;
      expect(count, 1);
    });

    test('returns 0 when no tickets completed today', () async {
      final count =
          await repo.watchCompletedTodayCount('tenant-1').first;
      expect(count, 0);
    });

    test('counts multiple completed tickets', () async {
      for (var i = 1; i <= 3; i++) {
        await repo.createTicketFromOrder(
          ticket: _ticket(id: 'ticket-$i', orderNumber: '000$i'),
          items: [_item(id: 'item-$i', ticketId: 'ticket-$i')],
        );
      }

      final ktRows = await db.select(db.kitchenTickets).get();
      for (final row in ktRows) {
        await repo.completeTicket(row.id);
      }

      final count =
          await repo.watchCompletedTodayCount('tenant-1').first;
      expect(count, 3);
    });
  });
}
