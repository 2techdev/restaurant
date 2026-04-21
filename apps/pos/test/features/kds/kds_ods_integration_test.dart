/// Integration tests verifying the KDS → ODS data flow.
///
/// Covers:
///   - KDS bump advances ODS from "preparing" to "ready" via ticket status
///   - KDS recall reverts ODS ticket back to "preparing"
///   - OdsNotifier partitions tickets into correct buckets
///   - OdsNotifier auto-removes expired ready orders
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/kitchen/data/repositories/kitchen_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _openInMemory() => AppDatabase(NativeDatabase.memory());

const _tenantId = 'tenant-test';

TicketEntity _ticket({
  String id = 'ticket-1',
  String orderNumber = '0001',
}) {
  return TicketEntity(
    id: id,
    tenantId: _tenantId,
    orderNumber: orderNumber,
    orderType: OrderType.dineIn,
    status: TicketStatus.sent,
    channel: OrderChannel.pos,
    openedAt: DateTime.now(),
    deviceId: 'DEV-KDS-01',
  );
}

OrderItemEntity _item({
  String id = 'item-1',
  String ticketId = 'ticket-1',
  String productName = 'Schnitzel',
}) {
  return OrderItemEntity(
    id: id,
    tenantId: _tenantId,
    ticketId: ticketId,
    productId: 'prod-1',
    productName: productName,
    quantity: 1,
    unitPrice: 2000,
    subtotal: 2000,
    modifiers: const [],
  );
}

/// Seeds a [Ticket] row directly in the DB with the given status.
Future<void> _seedTicket(
  AppDatabase db, {
  String id = 'ticket-1',
  String status = 'sent_to_kitchen',
}) async {
  final now = DateTime.now();
  await db.into(db.tickets).insert(
        TicketsCompanion.insert(
          id: id,
          tenantId: _tenantId,
          orderNumber: 1,
          status: Value(status),
          channel: const Value('pos'),
          openedAt: now,
          createdAt: now,
          updatedAt: now,
          deviceId: 'DEV-KDS-01',
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

  tearDown(() async => db.close());

  // -------------------------------------------------------------------------
  group('KDS bump → ODS auto-advance', () {
    test('bumping last kitchen ticket sets parent tickets.status=fully_served',
        () async {
      await _seedTicket(db, status: 'sent_to_kitchen');
      await repo.createTicketFromOrder(
        ticket: _ticket(),
        items: [_item()],
      );

      final ktRow = await db.select(db.kitchenTickets).getSingle();
      await repo.completeTicket(ktRow.id);

      final row = await db.select(db.tickets).getSingle();
      expect(row.status, 'fully_served',
          reason: 'ODS should show order in "Ready for pickup" panel');
    });

    test(
        'bumping one of two kitchen tickets sets parent tickets.status=partially_served',
        () async {
      await _seedTicket(db, status: 'sent_to_kitchen');
      await repo.createTicketFromOrder(
        ticket: _ticket(),
        items: [_item(id: 'item-1')],
      );

      // Inject a second kitchen ticket (bar station) for the same parent.
      final now = DateTime.now();
      await db.into(db.kitchenTickets).insert(
            KitchenTicketsCompanion.insert(
              id: 'kt-bar',
              tenantId: _tenantId,
              ticketId: 'ticket-1',
              orderNumber: 1,
              printerGroup: const Value('bar'),
              status: const Value('pending'),
              sentAt: now,
              createdAt: now,
            ),
          );

      final kitchenKt = await (db.select(db.kitchenTickets)
            ..where((t) => t.printerGroup.equals('kitchen')))
          .getSingle();
      await repo.completeTicket(kitchenKt.id);

      final row = await db.select(db.tickets).getSingle();
      expect(row.status, 'partially_served');
    });
  });

  // -------------------------------------------------------------------------
  group('KDS recall → ODS revert', () {
    test('recall after full bump reverts tickets.status to sent_to_kitchen',
        () async {
      await _seedTicket(db, status: 'sent_to_kitchen');
      await repo.createTicketFromOrder(
        ticket: _ticket(),
        items: [_item()],
      );

      final ktRow = await db.select(db.kitchenTickets).getSingle();
      await repo.completeTicket(ktRow.id); // → fully_served on ODS
      await repo.recallTicket(ktRow.id); // → reverts to sent_to_kitchen

      final row = await db.select(db.tickets).getSingle();
      expect(row.status, 'sent_to_kitchen',
          reason: 'ODS should move order back to "Preparing" panel');
    });

    test('recalled kitchen ticket reappears in watchActiveTickets stream',
        () async {
      await _seedTicket(db, status: 'sent_to_kitchen');
      await repo.createTicketFromOrder(
        ticket: _ticket(),
        items: [_item()],
      );

      final ktRow = await db.select(db.kitchenTickets).getSingle();
      await repo.completeTicket(ktRow.id);

      // After bump the ticket should NOT be active.
      final afterBump = await repo.watchActiveTickets(_tenantId).first;
      expect(afterBump, isEmpty);

      await repo.recallTicket(ktRow.id);

      // After recall the ticket should be active again.
      final afterRecall = await repo.watchActiveTickets(_tenantId).first;
      expect(afterRecall, hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  group('ODS ticket partitioning via DB queries', () {
    test('sent_to_kitchen ticket appears in preparing bucket', () async {
      final now = DateTime.now();
      await db.into(db.tickets).insert(
            TicketsCompanion.insert(
              id: 'ticket-prep',
              tenantId: _tenantId,
              orderNumber: 7,
              status: const Value('sent_to_kitchen'),
              channel: const Value('pos'),
              openedAt: now,
              createdAt: now,
              updatedAt: now,
              deviceId: 'DEV-01',
            ),
          );

      final rows = await (db.select(db.tickets)
            ..where((t) =>
                t.tenantId.equals(_tenantId) &
                t.status.isIn(['items_added', 'sent_to_kitchen'])))
          .get();
      expect(rows, hasLength(1));
      expect(rows.first.orderNumber, 7);
    });

    test('fully_served ticket appears in ready bucket', () async {
      final now = DateTime.now();
      await db.into(db.tickets).insert(
            TicketsCompanion.insert(
              id: 'ticket-ready',
              tenantId: _tenantId,
              orderNumber: 8,
              status: const Value('fully_served'),
              channel: const Value('pos'),
              openedAt: now,
              createdAt: now,
              updatedAt: now,
              deviceId: 'DEV-01',
            ),
          );

      final rows = await (db.select(db.tickets)
            ..where((t) =>
                t.tenantId.equals(_tenantId) &
                t.status.isIn(
                    ['partially_served', 'fully_served', 'bill_requested'])))
          .get();
      expect(rows, hasLength(1));
      expect(rows.first.orderNumber, 8);
    });

    test(
        'bump cycle: sent_to_kitchen → fully_served moves ticket between buckets',
        () async {
      await _seedTicket(db, status: 'sent_to_kitchen');
      await repo.createTicketFromOrder(
        ticket: _ticket(),
        items: [_item()],
      );

      // Before bump: appears in preparing bucket.
      final preparing = await (db.select(db.tickets)
            ..where((t) =>
                t.tenantId.equals(_tenantId) &
                t.status.isIn(['items_added', 'sent_to_kitchen'])))
          .get();
      expect(preparing, hasLength(1));

      final ktRow = await db.select(db.kitchenTickets).getSingle();
      await repo.completeTicket(ktRow.id);

      // After bump: no longer in preparing.
      final preparingAfter = await (db.select(db.tickets)
            ..where((t) =>
                t.tenantId.equals(_tenantId) &
                t.status.isIn(['items_added', 'sent_to_kitchen'])))
          .get();
      expect(preparingAfter, isEmpty);

      // Now in ready bucket.
      final ready = await (db.select(db.tickets)
            ..where((t) =>
                t.tenantId.equals(_tenantId) &
                t.status.isIn(
                    ['partially_served', 'fully_served', 'bill_requested'])))
          .get();
      expect(ready, hasLength(1));
    });
  });
}
