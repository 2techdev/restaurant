/// End-to-end test for the table lifecycle: tap-to-order → fire gang →
/// serve gang → take payment → table frees itself.
///
/// Exercises the two auto-wired seams added for the Swiss pilot:
///   1. OrderRepositoryImpl.createTicket links the table (currentOrderId
///      + status='occupied') inside the same transaction.
///   2. PaymentRepositoryImpl.processPayment clears the table
///      (currentOrderId=null, status='available', flags='') once the bill
///      is fully paid.
///
/// Also drives the gang_repository fire / serve lifecycle so the whole
/// "Gang 1/2/3 → Mutfak → Servis" path is covered by a regression guard.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/gang/data/gang_repository.dart';
import 'package:gastrocore_pos/features/gang/domain/entities/gang_template_entity.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/payments/data/repositories/payment_repository_impl.dart';
import 'package:gastrocore_pos/features/payments/domain/entities/payment_entity.dart';
import 'package:gastrocore_pos/features/tables/data/repositories/table_repository_impl.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';

const _tenantId = 'pilot-tenant';
const _waiterId = 'waiter-1';
const _deviceId = 'pos-01';

void main() {
  group('Table lifecycle E2E — order → fire → serve → pay → free', () {
    late AppDatabase db;
    late TableRepositoryImpl tableRepo;
    late OrderRepositoryImpl orderRepo;
    late PaymentRepositoryImpl paymentRepo;
    late GangRepository gangRepo;

    setUp(() async {
      db = AppDatabase.createInMemory();
      tableRepo = TableRepositoryImpl(db);
      orderRepo = OrderRepositoryImpl(db);
      paymentRepo = PaymentRepositoryImpl(db);
      gangRepo = GangRepository(db);

      await gangRepo.seedDefaultGangs(_tenantId);
    });

    tearDown(() async => db.close());

    test('createTicket auto-links the table and processPayment auto-frees it',
        () async {
      // 1. Floor + table — clean state.
      final floor = await tableRepo.createFloor(
        tenantId: _tenantId,
        name: 'Hauptsaal',
        displayOrder: 1,
      );
      final table = await tableRepo.createTable(
        tenantId: _tenantId,
        floorId: floor.id,
        name: 'T1',
        capacity: 4,
      );
      expect(table.status, TableStatus.available);
      expect(table.currentOrderId, isNull);

      // 2. Create a ticket bound to the table. We do NOT call
      //    linkOrderToTable explicitly — createTicket should flip the
      //    table to occupied as part of its own transaction.
      final ticketId = IdGenerator.generateId();
      await orderRepo.createTicket(TicketEntity(
        id: ticketId,
        tenantId: _tenantId,
        orderNumber: '0001',
        orderType: OrderType.dineIn,
        tableId: table.id,
        waiterId: _waiterId,
        guestCount: 2,
        openedAt: DateTime(2026, 4, 20, 19, 0),
        deviceId: _deviceId,
      ));

      final occupied = (await tableRepo.getTablesByFloor(floor.id))
          .firstWhere((t) => t.id == table.id);
      expect(occupied.status, TableStatus.occupied,
          reason: 'createTicket must auto-occupy the dine-in table');
      expect(occupied.currentOrderId, ticketId,
          reason: 'createTicket must link currentOrderId');

      // 3. Add two items on Gang 1 + one on Gang 2.
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

      final ticketAfterItems = (await orderRepo.getTicketById(ticketId))!;
      expect(ticketAfterItems.items.length, 3);
      expect(ticketAfterItems.subtotal, 6500);

      // 4. Fire Gang 1 — state transitions pending → fired.
      await gangRepo.ensureGangState(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        gangTemplateId: 'gang-1',
      );
      await gangRepo.fireGang(ticketId, 'gang-1');

      var g1 = await gangRepo.getOrderGangState(ticketId, 'gang-1');
      expect(g1!.status, GangOrderStatus.fired);
      expect(g1.firedAt, isNotNull);

      // 5. Deliver (serve) Gang 1.
      await gangRepo.markGangServed(ticketId, 'gang-1');
      g1 = await gangRepo.getOrderGangState(ticketId, 'gang-1');
      expect(g1!.status, GangOrderStatus.served);
      expect(g1.servedAt, isNotNull);

      // 6. Fire + serve Gang 2 too so both courses are delivered before
      //    the cashier takes payment.
      await gangRepo.ensureGangState(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        gangTemplateId: 'gang-2',
      );
      await gangRepo.fireGang(ticketId, 'gang-2');
      await gangRepo.markGangServed(ticketId, 'gang-2');

      // 7. Take payment in one shot via the processPayment orchestrator —
      //    this should create the bill, record the payment, complete the
      //    ticket, and free the table inside a single transaction.
      await paymentRepo.processPayment(
        ticketId: ticketId,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.cash,
        amount: ticketAfterItems.total,
        tenderedAmount: ticketAfterItems.total,
        receivedBy: _waiterId,
      );

      // Ticket completed.
      final paidTicket = (await orderRepo.getTicketById(ticketId))!;
      expect(paidTicket.status, TicketStatus.completed);
      expect(paidTicket.closedAt, isNotNull);

      // Table freed.
      final freed = (await tableRepo.getTablesByFloor(floor.id))
          .firstWhere((t) => t.id == table.id);
      expect(freed.status, TableStatus.available,
          reason: 'processPayment must auto-free the table on full pay');
      expect(freed.currentOrderId, isNull,
          reason: 'processPayment must clear currentOrderId');
      expect(freed.flags, isEmpty,
          reason: 'processPayment must drop all table flags');

      // Bill + payments settled.
      final bills = await paymentRepo.getBillsByTicket(ticketId);
      expect(bills, hasLength(1));
      expect(bills.single.status, BillStatus.fullyPaid);
      expect(bills.single.payments, hasLength(1));
    });

    test('partial payment leaves the table occupied', () async {
      final floor = await tableRepo.createFloor(
        tenantId: _tenantId,
        name: 'Hauptsaal',
        displayOrder: 1,
      );
      final table = await tableRepo.createTable(
        tenantId: _tenantId,
        floorId: floor.id,
        name: 'T2',
        capacity: 2,
      );

      final ticketId = IdGenerator.generateId();
      await orderRepo.createTicket(TicketEntity(
        id: ticketId,
        tenantId: _tenantId,
        orderNumber: '0002',
        orderType: OrderType.dineIn,
        tableId: table.id,
        waiterId: _waiterId,
        guestCount: 1,
        openedAt: DateTime(2026, 4, 20, 20, 0),
        deviceId: _deviceId,
      ));
      await orderRepo.addItemToTicket(ticketId, OrderItemEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        productId: 'prod-x',
        productName: 'Menu X',
        quantity: 1,
        unitPrice: 5000,
        subtotal: 5000,
        taxGroup: 'food',
        course: 1,
        gangId: 'gang-1',
      ));

      final ticket = (await orderRepo.getTicketById(ticketId))!;

      // Pay half the total — bill should land in partially_paid, table
      // must stay occupied.
      await paymentRepo.processPayment(
        ticketId: ticketId,
        tenantId: _tenantId,
        paymentMethod: PaymentMethod.cash,
        amount: (ticket.total / 2).round(),
        tenderedAmount: (ticket.total / 2).round(),
        receivedBy: _waiterId,
      );

      final bills = await paymentRepo.getBillsByTicket(ticketId);
      expect(bills.single.status, BillStatus.partiallyPaid);

      final stillOccupied = (await tableRepo.getTablesByFloor(floor.id))
          .firstWhere((t) => t.id == table.id);
      expect(stillOccupied.status, TableStatus.occupied,
          reason: 'Partial payment must not free the table');
      expect(stillOccupied.currentOrderId, ticketId);
    });
  });
}
