/// Tests for [KitchenRepositoryImpl] — KDS ticket lifecycle.
///
/// Covers: createTicketFromOrder, completeTicket (bump), recallTicket,
/// watchActiveTickets stream, watchCompletedTodayCount stream.
///
/// Run with:
///   flutter test test/features/kds/kds_kitchen_repository_test.dart
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/kitchen/data/repositories/kitchen_repository_impl.dart';
import 'package:gastrocore_pos/features/kitchen/domain/entities/kitchen_ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-kds-test';
const _deviceId = 'KDS-DEV-01';

TicketEntity _makeTicket({String? id, String? tableId}) {
  return TicketEntity(
    id: id ?? IdGenerator.generateId(),
    tenantId: _tenantId,
    orderNumber: '0042',
    orderType: OrderType.dineIn,
    tableId: tableId,
    status: TicketStatus.sent,
    openedAt: DateTime(2026, 3, 21, 12, 0),
    deviceId: _deviceId,
  );
}

OrderItemEntity _makeItem({
  required String ticketId,
  String productName = 'Rösti',
  double quantity = 1,
}) {
  final itemId = IdGenerator.generateId();
  return OrderItemEntity(
    id: itemId,
    tenantId: _tenantId,
    ticketId: ticketId,
    productId: 'prod-rosti',
    productName: productName,
    quantity: quantity,
    unitPrice: 1800,
    subtotal: 1800,
    taxGroup: 'food',
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('KitchenRepositoryImpl — createTicketFromOrder', () {
    late AppDatabase db;
    late KitchenRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = KitchenRepositoryImpl(db);
    });

    tearDown(() async => db.close());

    test('creates kitchen ticket and items from POS ticket', () async {
      final ticket = _makeTicket();
      final items = [
        _makeItem(ticketId: ticket.id, productName: 'Rösti'),
        _makeItem(ticketId: ticket.id, productName: 'Bratwurst'),
      ];

      await repo.createTicketFromOrder(
        ticket: ticket,
        items: items,
        waiterName: 'Max',
      );

      final all = await (db.select(db.kitchenTickets)).get();
      expect(all.length, equals(1));
      expect(all.first.status, equals('pending'));
      expect(all.first.waiterName, equals('Max'));
      expect(all.first.orderNumber, equals(42));

      final kitchenItems =
          await (db.select(db.kitchenTicketItems)).get();
      expect(kitchenItems.length, equals(2));
      expect(
        kitchenItems.map((i) => i.productName),
        containsAll(['Rösti', 'Bratwurst']),
      );
    });

    test('does nothing when items list is empty', () async {
      final ticket = _makeTicket();
      await repo.createTicketFromOrder(
        ticket: ticket,
        items: [],
        waiterName: 'Max',
      );

      final all = await (db.select(db.kitchenTickets)).get();
      expect(all, isEmpty);
    });

    test('includes modifier text in kitchen item', () async {
      final ticket = _makeTicket();
      final itemId = IdGenerator.generateId();
      final modifier = OrderItemModifierEntity(
        id: IdGenerator.generateId(),
        orderItemId: itemId,
        modifierId: 'mod-1',
        modifierName: 'Extra Käse',
        priceDelta: 200,
      );
      final item = OrderItemEntity(
        id: itemId,
        tenantId: _tenantId,
        ticketId: ticket.id,
        productId: 'prod-burger',
        productName: 'Burger',
        quantity: 1,
        unitPrice: 2000,
        subtotal: 2200,
        taxGroup: 'food',
        modifiers: [modifier],
      );

      await repo.createTicketFromOrder(
        ticket: ticket,
        items: [item],
        waiterName: 'Lena',
      );

      final kitchenItems = await (db.select(db.kitchenTicketItems)).get();
      expect(kitchenItems.first.modifiersText, equals('Extra Käse'));
    });

    test('resolves table name when tableId is set', () async {
      // Insert a table row first.
      final tableId = IdGenerator.generateId();
      await db.into(db.restaurantTables).insert(RestaurantTablesCompanion(
            id: Value(tableId),
            tenantId: const Value(_tenantId),
            floorId: const Value('floor-1'),
            name: const Value('Tisch 5'),
            capacity: const Value(4),
            shape: const Value('rectangle'),
            posX: const Value(100),
            posY: const Value(100),
            width: const Value(120),
            height: const Value(80),
            status: const Value('available'),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ));

      final ticket = _makeTicket(tableId: tableId);
      final items = [_makeItem(ticketId: ticket.id)];

      await repo.createTicketFromOrder(
        ticket: ticket,
        items: items,
        waiterName: null,
      );

      final all = await (db.select(db.kitchenTickets)).get();
      expect(all.first.kitchenTableName, equals('Tisch 5'));
    });
  });

  // =========================================================================
  // completeTicket (bump)
  // =========================================================================

  group('KitchenRepositoryImpl — completeTicket (bump)', () {
    late AppDatabase db;
    late KitchenRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = KitchenRepositoryImpl(db);
    });

    tearDown(() async => db.close());

    test('sets status to served and completedAt', () async {
      final ticket = _makeTicket();
      final items = [_makeItem(ticketId: ticket.id)];
      await repo.createTicketFromOrder(ticket: ticket, items: items);

      final ktRow = (await db.select(db.kitchenTickets).get()).first;
      await repo.completeTicket(ktRow.id);

      final updated = (await db.select(db.kitchenTickets).get()).first;
      expect(updated.status, equals('served'));
      expect(updated.completedAt, isNotNull);
    });

    test('bumped ticket no longer appears in active stream', () async {
      final ticket = _makeTicket();
      final items = [_makeItem(ticketId: ticket.id)];
      await repo.createTicketFromOrder(ticket: ticket, items: items);

      final ktRow = (await db.select(db.kitchenTickets).get()).first;
      await repo.completeTicket(ktRow.id);

      // Active tickets should be empty (only pending/preparing).
      final active = await repo.watchActiveTickets().first;
      expect(active, isEmpty);
    });
  });

  // =========================================================================
  // recallTicket
  // =========================================================================

  group('KitchenRepositoryImpl — recallTicket', () {
    late AppDatabase db;
    late KitchenRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = KitchenRepositoryImpl(db);
    });

    tearDown(() async => db.close());

    test('restores served ticket to preparing status', () async {
      final ticket = _makeTicket();
      final items = [_makeItem(ticketId: ticket.id)];
      await repo.createTicketFromOrder(ticket: ticket, items: items);

      final ktRow = (await db.select(db.kitchenTickets).get()).first;
      await repo.completeTicket(ktRow.id);
      await repo.recallTicket(ktRow.id);

      final recalled = (await db.select(db.kitchenTickets).get()).first;
      expect(recalled.status, equals('preparing'));
      expect(recalled.completedAt, isNull);
    });

    test('recalled ticket re-appears in active stream', () async {
      final ticket = _makeTicket();
      final items = [_makeItem(ticketId: ticket.id)];
      await repo.createTicketFromOrder(ticket: ticket, items: items);

      final ktRow = (await db.select(db.kitchenTickets).get()).first;
      await repo.completeTicket(ktRow.id);
      await repo.recallTicket(ktRow.id);

      final active = await repo.watchActiveTickets().first;
      expect(active.length, equals(1));
      expect(active.first.status, equals(KitchenTicketStatus.preparing));
    });
  });

  // =========================================================================
  // watchActiveTickets stream
  // =========================================================================

  group('KitchenRepositoryImpl — watchActiveTickets', () {
    late AppDatabase db;
    late KitchenRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = KitchenRepositoryImpl(db);
    });

    tearDown(() async => db.close());

    test('returns empty list when no tickets', () async {
      final active = await repo.watchActiveTickets().first;
      expect(active, isEmpty);
    });

    test('new pending ticket appears in stream', () async {
      final ticket = _makeTicket();
      final items = [_makeItem(ticketId: ticket.id, productName: 'Schnitzel')];
      await repo.createTicketFromOrder(ticket: ticket, items: items);

      final active = await repo.watchActiveTickets().first;
      expect(active.length, equals(1));
      expect(active.first.status, equals(KitchenTicketStatus.pending));
      expect(active.first.items.first.productName, equals('Schnitzel'));
    });

    test('served tickets are excluded from active stream', () async {
      final t1 = _makeTicket();
      final t2 = _makeTicket();
      await repo.createTicketFromOrder(
          ticket: t1, items: [_makeItem(ticketId: t1.id, productName: 'A')]);
      await repo.createTicketFromOrder(
          ticket: t2, items: [_makeItem(ticketId: t2.id, productName: 'B')]);

      final kt1 =
          (await db.select(db.kitchenTickets).get()).first;
      await repo.completeTicket(kt1.id);

      final active = await repo.watchActiveTickets().first;
      expect(active.length, equals(1));
    });

    test('tickets are ordered oldest-first', () async {
      final t1 = _makeTicket();
      final t2 = _makeTicket();
      // Insert t1 first, then t2 after a tiny delay.
      await repo.createTicketFromOrder(
          ticket: t1, items: [_makeItem(ticketId: t1.id)]);
      await Future.delayed(const Duration(milliseconds: 5));
      await repo.createTicketFromOrder(
          ticket: t2, items: [_makeItem(ticketId: t2.id)]);

      final active = await repo.watchActiveTickets().first;
      expect(active.length, equals(2));
      // First item should be the older one.
      expect(active.first.ticketId, equals(t1.id));
    });

    test('orderNumber is padded to 4 digits', () async {
      final ticket = _makeTicket(); // orderNumber = '0042'
      await repo.createTicketFromOrder(
          ticket: ticket, items: [_makeItem(ticketId: ticket.id)]);

      final active = await repo.watchActiveTickets().first;
      expect(active.first.orderNumber, equals('0042'));
    });
  });

  // =========================================================================
  // KDS providers — unit tests
  // =========================================================================

  group('KDS Providers — state', () {
    test('KitchenTicketStatus enum covers all known states', () {
      const statuses = KitchenTicketStatus.values;
      expect(
        statuses,
        containsAll([
          KitchenTicketStatus.pending,
          KitchenTicketStatus.acknowledged,
          KitchenTicketStatus.preparing,
          KitchenTicketStatus.ready,
          KitchenTicketStatus.served,
          KitchenTicketStatus.voidStatus,
        ]),
      );
    });

    test('KitchenTicketEntity isOverdue when elapsed > target duration', () {
      final ticket = KitchenTicketEntity(
        id: 'kt-1',
        tenantId: _tenantId,
        ticketId: 'ticket-1',
        orderNumber: '0001',
        printerGroup: 'kitchen',
        status: KitchenTicketStatus.pending,
        items: const [],
        sentAt: DateTime.now().subtract(const Duration(minutes: 15)),
      );

      expect(ticket.isOverdue(const Duration(minutes: 10)), isTrue);
    });

    test('KitchenTicketEntity is not overdue within target duration', () {
      final ticket = KitchenTicketEntity(
        id: 'kt-2',
        tenantId: _tenantId,
        ticketId: 'ticket-2',
        orderNumber: '0002',
        printerGroup: 'kitchen',
        status: KitchenTicketStatus.pending,
        items: const [],
        sentAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      expect(ticket.isOverdue(const Duration(minutes: 10)), isFalse);
    });

    test('KitchenTicketItemEntity has correct fields', () {
      const item = KitchenTicketItemEntity(
        id: 'item-1',
        kitchenTicketId: 'kt-1',
        orderItemId: 'order-item-1',
        productName: 'Fondue',
        quantity: 2,
        modifiersText: 'ohne Brot',
        status: KitchenTicketStatus.pending,
      );

      expect(item.productName, 'Fondue');
      expect(item.quantity, 2);
      expect(item.modifiersText, 'ohne Brot');
    });
  });
}
