/// Fine-dining end-to-end integration test.
///
/// Drives the POS repositories + the SambaPOS calculation pipeline
/// directly against an in-memory AppDatabase — no widgets involved.
/// Walks the full fine-dining flow expected at the pilot:
///
///   1. Open table, set cover count, assign waiter
///   2. Add order items across two Gangs (Vorspeise + Hauptgang)
///   3. Apply a modifier (positive priceDelta)
///   4. Fire Gang 1 to the kitchen
///   5. Add an extra item to Gang 2 after Gang 1 fired
///   6. Request the bill (sets TableFlag.billRequested)
///   7. Run the calculation pipeline: discount + service + Swiss MwSt +
///      5-Rappen rounding
///   8. Accept split payment: cash + card + TWINT
///   9. Close the ticket, clear the table, confirm invariants
///
/// This test is the pilot smoke-suite: if it fails, the build does not
/// ship. It exists to catch regressions across the repo/service seam
/// where the UI can't easily prove correctness.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/gang/data/gang_repository.dart';
import 'package:gastrocore_pos/features/gang/domain/entities/gang_template_entity.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/calculations/calculation_pipeline.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/payments/data/repositories/payment_repository_impl.dart';
import 'package:gastrocore_pos/features/payments/domain/entities/payment_entity.dart';
import 'package:gastrocore_pos/features/tables/data/repositories/table_repository_impl.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';

const _tenantId = 'pilot-tenant';
const _waiterId = 'waiter-1';
const _waiterName = 'Anna';
const _deviceId = 'pos-01';

void main() {
  group('Fine-dining E2E — full flow', () {
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

      // Seed default Gangs for this tenant (Vorspeise / Hauptgang / …).
      await gangRepo.seedDefaultGangs(_tenantId);
    });

    tearDown(() async => db.close());

    test('waiter serves a 2-gang dinner, takes split payment, closes table',
        () async {
      // ------------------------------------------------------------------
      // 1. Open the floor + table. Fine-dining stores use a named zone.
      // ------------------------------------------------------------------
      final floor = await tableRepo.createFloor(
        tenantId: _tenantId,
        name: 'Hauptsaal',
        displayOrder: 1,
      );
      final table = await tableRepo.createTable(
        tenantId: _tenantId,
        floorId: floor.id,
        name: 'T5',
        capacity: 4,
      );

      expect(table.status, TableStatus.available);
      expect(table.flags, isEmpty);

      // ------------------------------------------------------------------
      // 2. Create a ticket for this table — 2 covers, waiter = Anna.
      // ------------------------------------------------------------------
      final ticketId = IdGenerator.generateId();
      final openedAt = DateTime(2026, 4, 18, 19, 30);
      final draft = TicketEntity(
        id: ticketId,
        tenantId: _tenantId,
        orderNumber: '0001',
        orderType: OrderType.dineIn,
        tableId: table.id,
        waiterId: _waiterId,
        cashierName: _waiterName,
        guestCount: 2,
        openedAt: openedAt,
        deviceId: _deviceId,
      );
      await orderRepo.createTicket(draft);
      await tableRepo.linkOrderToTable(table.id, ticketId);

      // Table is now marked occupied.
      final tablesAfterLink = await tableRepo.getTablesByFloor(floor.id);
      final occupied = tablesAfterLink.firstWhere((t) => t.id == table.id);
      expect(occupied.status, TableStatus.occupied);

      // Gang states (pending) for Vorspeise + Hauptgang.
      await gangRepo.ensureGangState(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        gangTemplateId: 'gang-1',
      );
      await gangRepo.ensureGangState(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        gangTemplateId: 'gang-2',
      );

      // ------------------------------------------------------------------
      // 3. Add items: one Vorspeise with a modifier, one Hauptgang.
      // ------------------------------------------------------------------
      final vorspeiseId = IdGenerator.generateId();
      final modifierId = IdGenerator.generateId();
      final vorspeise = OrderItemEntity(
        id: vorspeiseId,
        tenantId: _tenantId,
        ticketId: ticketId,
        productId: 'prod-salat',
        productName: 'Caesar Salat',
        quantity: 1,
        unitPrice: 1800, // 18.00 CHF
        subtotal: 2000, // salad + extra parm
        taxGroup: 'food',
        gangId: 'gang-1',
        modifiers: [
          OrderItemModifierEntity(
            id: modifierId,
            orderItemId: vorspeiseId,
            modifierId: 'mod-parm',
            modifierName: '+ Extra Parmesan',
            priceDelta: 200, // +2.00
            quantity: 1,
          ),
        ],
      );
      final hauptgang = OrderItemEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        productId: 'prod-rind',
        productName: 'Rinderfilet',
        quantity: 1,
        unitPrice: 4800,
        subtotal: 4800,
        taxGroup: 'food',
        gangId: 'gang-2',
      );
      await orderRepo.addItemToTicket(ticketId, vorspeise);
      await orderRepo.addItemToTicket(ticketId, hauptgang);

      // Subtotal after addItemToTicket's internal recalc: 2000 + 4800 = 6800.
      final afterItems = (await orderRepo.getTicketById(ticketId))!;
      expect(afterItems.items.length, 2);
      expect(afterItems.items.firstWhere((i) => i.id == vorspeiseId)
          .modifiers.single.modifierName, '+ Extra Parmesan');

      // ------------------------------------------------------------------
      // 4. Fire Gang 1 — Vorspeise marked sent.
      // ------------------------------------------------------------------
      await gangRepo.fireGang(ticketId, 'gang-1');
      final gang1State = await gangRepo.getOrderGangState(ticketId, 'gang-1');
      expect(gang1State!.status, GangOrderStatus.fired);
      expect(gang1State.firedAt, isNotNull);

      // ------------------------------------------------------------------
      // 5. Operator adds a dessert to Gang 2 (or a 2nd gang) after the
      //    first gang's already in the kitchen. This is the most common
      //    point of breakage: ticket must still accept items.
      // ------------------------------------------------------------------
      final extra = OrderItemEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        productId: 'prod-dessert',
        productName: 'Tiramisu',
        quantity: 1,
        unitPrice: 1200,
        subtotal: 1200,
        taxGroup: 'food',
        gangId: 'gang-2',
      );
      await orderRepo.addItemToTicket(ticketId, extra);

      final afterExtra = (await orderRepo.getTicketById(ticketId))!;
      expect(afterExtra.items.length, 3);
      expect(afterExtra.subtotal, 8000); // 2000 + 4800 + 1200

      // ------------------------------------------------------------------
      // 6. Guest asks for the bill — TableFlag.billRequested goes on the
      //    tile so the runner/host can see it from the floor plan.
      // ------------------------------------------------------------------
      await tableRepo.setTableFlag(
        tableId: table.id,
        flag: TableFlag.billRequested,
        enabled: true,
      );
      await orderRepo.updateTicketStatus(
        ticketId,
        TicketStatus.billRequested,
      );

      final tableWithFlag = (await tableRepo.getTablesByFloor(floor.id))
          .firstWhere((t) => t.id == table.id);
      expect(tableWithFlag.flags, contains(TableFlag.billRequested));
      expect(tableWithFlag.status, TableStatus.occupied,
          reason: 'Flags are orthogonal — primary status unchanged');

      // ------------------------------------------------------------------
      // 7. Run the SambaPOS calculation pipeline against the ticket's
      //    Swiss MwSt bucket. Subtotal is tax-inclusive under A (8.1 %).
      // ------------------------------------------------------------------
      final currentTicket = (await orderRepo.getTicketById(ticketId))!;
      final pipeline = runCalculationPipeline(PipelineInput(
        subtotalByMwst: {'A': currentTicket.subtotal},
        discountAmount: 500, // -5.00 CHF loyalty voucher
        serviceAmount: 950, // +9.50 service (common fine-dining add-on)
        applyRounding: true,
      ));

      // Grand total before rounding: 8000 - 500 + 950 = 8450.
      // 8450 is already a multiple of 5 ⇒ no rounding step emitted.
      expect(pipeline.grandTotal, 8450);
      expect(pipeline.taxByCode['A'], greaterThan(0),
          reason: 'Swiss A-bucket tax must be extracted from the gross');

      // ------------------------------------------------------------------
      // 8. Split payment: cash + card + TWINT. BillEntity first, then
      //    three PaymentEntity rows settling it.
      // ------------------------------------------------------------------
      final bill = await paymentRepo.createBill(BillEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        ticketId: ticketId,
        billNumber: 'B-0001',
        subtotal: currentTicket.subtotal,
        taxAmount: pipeline.taxByCode['A'] ?? 0,
        discountAmount: 500,
        total: pipeline.grandTotal,
      ));

      // 8450 split three ways: 4000 cash + 3000 card + 1450 TWINT = 8450.
      final paidAt = openedAt.add(const Duration(hours: 2));
      await paymentRepo.createPayment(PaymentEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        billId: bill.id,
        ticketId: ticketId,
        paymentMethod: PaymentMethod.cash,
        amount: 4000,
        tenderedAmount: 4000,
        receivedBy: _waiterId,
        paidAt: paidAt,
      ));
      await paymentRepo.createPayment(PaymentEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        billId: bill.id,
        ticketId: ticketId,
        paymentMethod: PaymentMethod.creditCard,
        amount: 3000,
        receivedBy: _waiterId,
        paidAt: paidAt,
      ));
      // TWINT rides on PaymentMethod.other with the channel tagged in
      // `reference` — only `reference` is actually persisted by the
      // payments schema today (externalChannel is in-memory only).
      await paymentRepo.createPayment(PaymentEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        billId: bill.id,
        ticketId: ticketId,
        paymentMethod: PaymentMethod.other,
        amount: 1450,
        reference: 'TWINT',
        receivedBy: _waiterId,
        paidAt: paidAt,
      ));

      // Payments applied must exactly cover the bill.
      final payments = await paymentRepo.getPaymentsByBill(bill.id);
      final totalPaid = payments.fold<int>(0, (s, p) => s + p.amount);
      expect(totalPaid, pipeline.grandTotal);
      expect(payments.map((p) => p.paymentMethod).toSet(), {
        PaymentMethod.cash,
        PaymentMethod.creditCard,
        PaymentMethod.other,
      });
      expect(
        payments.firstWhere((p) => p.paymentMethod == PaymentMethod.other)
            .reference,
        'TWINT',
      );

      // ------------------------------------------------------------------
      // 9. Close the ticket and return the table to available. Flags must
      //    clear as part of clearTable so billRequested doesn't linger
      //    onto the next guest.
      // ------------------------------------------------------------------
      await orderRepo.updateTicketStatus(ticketId, TicketStatus.completed);
      await tableRepo.clearTable(table.id);

      final finalTicket = (await orderRepo.getTicketById(ticketId))!;
      expect(finalTicket.status, TicketStatus.completed);

      final clearedTable = (await tableRepo.getTablesByFloor(floor.id))
          .firstWhere((t) => t.id == table.id);
      expect(clearedTable.status, TableStatus.available);
      expect(clearedTable.flags, isEmpty,
          reason: 'clearTable must drop billRequested too');
    });
  });
}
