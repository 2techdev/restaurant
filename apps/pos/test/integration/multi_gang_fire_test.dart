/// Regression guard for the multi-gang fire bug.
///
/// Report: after firing Gang 1 to the kitchen, items added for Gang 2
/// never reached the DB, so firing Gang 2 produced no kitchen ticket and
/// the Gang 2 card on the order panel stayed empty.
///
/// Root cause lived in the POS notifier (`addItem` never persisted once
/// the ticket left 'draft'), but the repository layer already supported
/// the correct behaviour. This test exercises the repository path that
/// the fixed notifier now uses: items added after the ticket status
/// advances still land in the DB and each gang ends up with its own
/// OrderGangState row, fired / served independently.
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/gang/data/gang_repository.dart';
import 'package:gastrocore_pos/features/gang/domain/entities/gang_template_entity.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/tables/data/repositories/table_repository_impl.dart';

const _tenantId = 'pilot-tenant';
const _waiterId = 'waiter-1';
const _deviceId = 'pos-01';

void main() {
  group('Multi-gang sequential fire — Gang 1 fire then Gang 2 items', () {
    late AppDatabase db;
    late TableRepositoryImpl tableRepo;
    late OrderRepositoryImpl orderRepo;
    late GangRepository gangRepo;

    setUp(() async {
      db = AppDatabase.createInMemory();
      tableRepo = TableRepositoryImpl(db);
      orderRepo = OrderRepositoryImpl(db);
      gangRepo = GangRepository(db);
      await gangRepo.seedDefaultGangs(_tenantId);
    });

    tearDown(() async => db.close());

    test(
        'items added after Gang 1 fire still persist and Gang 2 fires '
        'independently', () async {
      final floor = await tableRepo.createFloor(
        tenantId: _tenantId,
        name: 'Hauptsaal',
        displayOrder: 1,
      );
      final table = await tableRepo.createTable(
        tenantId: _tenantId,
        floorId: floor.id,
        name: 'T3',
        capacity: 4,
      );

      // Open ticket (persisted immediately — mirrors POS createTicket flow).
      final ticketId = IdGenerator.generateId();
      await orderRepo.createTicket(TicketEntity(
        id: ticketId,
        tenantId: _tenantId,
        orderNumber: '0003',
        orderType: OrderType.dineIn,
        tableId: table.id,
        waiterId: _waiterId,
        guestCount: 2,
        openedAt: DateTime(2026, 4, 20, 19, 0),
        deviceId: _deviceId,
      ));

      // --- Gang 1 pass: add Vorspeise items, fire. ---
      await orderRepo.addItemToTicket(ticketId, OrderItemEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        productId: 'prod-salad',
        productName: 'Salat',
        quantity: 1,
        unitPrice: 1500,
        subtotal: 1500,
        taxGroup: 'food',
        course: 1,
        gangId: 'gang-1',
      ));
      await orderRepo.addItemToTicket(ticketId, OrderItemEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        productId: 'prod-soup',
        productName: 'Suppe',
        quantity: 1,
        unitPrice: 1000,
        subtotal: 1000,
        taxGroup: 'food',
        course: 1,
        gangId: 'gang-1',
      ));

      // Mark Gang 1 items sent and advance ticket status — this is what
      // the notifier's fireGang(1) does after persisting the draft.
      final afterG1Items = (await orderRepo.getTicketById(ticketId))!;
      final gang1Items =
          afterG1Items.items.where((i) => i.course == 1).toList();
      expect(gang1Items, hasLength(2));
      for (final item in gang1Items) {
        await orderRepo.updateItemStatus(item.id, OrderItemStatus.sent);
      }
      await orderRepo.updateTicketStatus(ticketId, TicketStatus.sent);

      await gangRepo.ensureGangState(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        gangTemplateId: 'gang-1',
      );
      await gangRepo.fireGang(ticketId, 'gang-1');

      // Sanity: after firing Gang 1, the ticket is no longer a draft.
      final postG1Ticket = (await orderRepo.getTicketById(ticketId))!;
      expect(postG1Ticket.status, TicketStatus.sent,
          reason: 'Ticket must leave draft before we can reproduce the bug');

      // --- Gang 2 pass: add Hauptgang items AFTER the ticket is sent. ---
      // Pre-fix: the notifier never persisted these, so the Gang 2 card
      // rendered empty and fireGang(2) was a no-op. We persist them via
      // the same path the fixed notifier now takes.
      await orderRepo.addItemToTicket(ticketId, OrderItemEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        productId: 'prod-rind',
        productName: 'Rinderfilet',
        quantity: 1,
        unitPrice: 4000,
        subtotal: 4000,
        taxGroup: 'food',
        course: 2,
        gangId: 'gang-2',
      ));
      await orderRepo.addItemToTicket(ticketId, OrderItemEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        productId: 'prod-pasta',
        productName: 'Pasta',
        quantity: 1,
        unitPrice: 2800,
        subtotal: 2800,
        taxGroup: 'food',
        course: 2,
        gangId: 'gang-2',
      ));

      // Gang 2 items must round-trip through the DB.
      final afterG2Add = (await orderRepo.getTicketById(ticketId))!;
      final gang2Items =
          afterG2Add.items.where((i) => i.course == 2).toList();
      expect(gang2Items, hasLength(2),
          reason: 'Gang 2 items added after Gang 1 fire must persist');
      expect(afterG2Add.items, hasLength(4),
          reason: 'All four items must be on the ticket');
      expect(afterG2Add.subtotal, 9300,
          reason: 'Totals must include Gang 2 items');

      // Gang 2 items should still be unsent (pre-fire) even though the
      // ticket status is 'sent' from Gang 1's fire.
      for (final item in gang2Items) {
        expect(item.sentToKitchen, isFalse,
            reason: 'Newly added Gang 2 items must be unsent initially');
      }

      // --- Fire Gang 2. ---
      for (final item in gang2Items) {
        await orderRepo.updateItemStatus(item.id, OrderItemStatus.sent);
      }
      await gangRepo.ensureGangState(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        gangTemplateId: 'gang-2',
      );
      await gangRepo.fireGang(ticketId, 'gang-2');

      // --- Assert both gangs have independent lifecycle rows. ---
      final allStates = await gangRepo.getOrderGangStates(ticketId);
      expect(allStates, hasLength(2),
          reason: 'Each gang must have its own OrderGangState row');

      final g1 = await gangRepo.getOrderGangState(ticketId, 'gang-1');
      final g2 = await gangRepo.getOrderGangState(ticketId, 'gang-2');
      expect(g1!.status, GangOrderStatus.fired);
      expect(g1.firedAt, isNotNull);
      expect(g2!.status, GangOrderStatus.fired);
      expect(g2.firedAt, isNotNull);
      expect(g1.id, isNot(equals(g2.id)),
          reason: 'The two gangs must be separate rows, not aliased');

      // --- Serve Gang 1 first: Gang 2 must stay fired. ---
      await gangRepo.markGangServed(ticketId, 'gang-1');
      final g1Served = await gangRepo.getOrderGangState(ticketId, 'gang-1');
      final g2StillFired = await gangRepo.getOrderGangState(ticketId, 'gang-2');
      expect(g1Served!.status, GangOrderStatus.served);
      expect(g1Served.servedAt, isNotNull);
      expect(g2StillFired!.status, GangOrderStatus.fired,
          reason: 'Serving Gang 1 must not cascade into Gang 2');
      expect(g2StillFired.servedAt, isNull);

      // --- Serve Gang 2: both now served. ---
      await gangRepo.markGangServed(ticketId, 'gang-2');
      final g2Served = await gangRepo.getOrderGangState(ticketId, 'gang-2');
      expect(g2Served!.status, GangOrderStatus.served);
      expect(g2Served.servedAt, isNotNull);
    });

    test('adding a third gang after both Gang 1 and Gang 2 fire still persists',
        () async {
      final floor = await tableRepo.createFloor(
        tenantId: _tenantId,
        name: 'Hauptsaal',
        displayOrder: 1,
      );
      final table = await tableRepo.createTable(
        tenantId: _tenantId,
        floorId: floor.id,
        name: 'T4',
        capacity: 2,
      );

      final ticketId = IdGenerator.generateId();
      await orderRepo.createTicket(TicketEntity(
        id: ticketId,
        tenantId: _tenantId,
        orderNumber: '0004',
        orderType: OrderType.dineIn,
        tableId: table.id,
        waiterId: _waiterId,
        guestCount: 1,
        openedAt: DateTime(2026, 4, 20, 19, 30),
        deviceId: _deviceId,
      ));

      // Fire Gang 1.
      await orderRepo.addItemToTicket(ticketId, OrderItemEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        productId: 'p1',
        productName: 'Bruschetta',
        quantity: 1,
        unitPrice: 1200,
        subtotal: 1200,
        taxGroup: 'food',
        course: 1,
        gangId: 'gang-1',
      ));
      await orderRepo.updateTicketStatus(ticketId, TicketStatus.sent);
      await gangRepo.ensureGangState(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        gangTemplateId: 'gang-1',
      );
      await gangRepo.fireGang(ticketId, 'gang-1');

      // Fire Gang 2.
      await orderRepo.addItemToTicket(ticketId, OrderItemEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        productId: 'p2',
        productName: 'Schnitzel',
        quantity: 1,
        unitPrice: 3200,
        subtotal: 3200,
        taxGroup: 'food',
        course: 2,
        gangId: 'gang-2',
      ));
      await gangRepo.ensureGangState(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        gangTemplateId: 'gang-2',
      );
      await gangRepo.fireGang(ticketId, 'gang-2');

      // Now add a Gang 3 dessert — the ticket has been past 'draft' for a
      // while. Must still land in the DB.
      await orderRepo.addItemToTicket(ticketId, OrderItemEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        productId: 'p3',
        productName: 'Tiramisu',
        quantity: 1,
        unitPrice: 900,
        subtotal: 900,
        taxGroup: 'food',
        course: 3,
        gangId: 'gang-3',
      ));

      final ticket = (await orderRepo.getTicketById(ticketId))!;
      final gang3Items = ticket.items.where((i) => i.course == 3).toList();
      expect(gang3Items, hasLength(1),
          reason: 'Gang 3 item must persist even after two prior fires');
      expect(ticket.items, hasLength(3));
      expect(ticket.subtotal, 5300);

      // Fire Gang 3 and confirm we now have three distinct lifecycle rows.
      await gangRepo.ensureGangState(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        gangTemplateId: 'gang-3',
      );
      await gangRepo.fireGang(ticketId, 'gang-3');

      final states = await gangRepo.getOrderGangStates(ticketId);
      expect(states, hasLength(3));
      final statuses = {for (final s in states) s.gangTemplateId: s.status};
      expect(statuses['gang-1'], GangOrderStatus.fired);
      expect(statuses['gang-2'], GangOrderStatus.fired);
      expect(statuses['gang-3'], GangOrderStatus.fired);
    });
  });
}
