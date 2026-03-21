/// Unit tests for TicketEntity.
///
/// Covers adding/removing items with total recalculation, modifiers,
/// empty ticket, order type changes, item count, discount types,
/// and status helpers.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Create a fresh empty draft ticket for testing.
TicketEntity emptyTicket({
  OrderType orderType = OrderType.dineIn,
  DiscountType discountType = DiscountType.none,
  int discountValue = 0,
}) {
  return TicketEntity(
    id: 'ticket-1',
    tenantId: 'tenant-1',
    orderNumber: '0001',
    orderType: orderType,
    status: TicketStatus.draft,
    openedAt: DateTime(2026, 1, 15, 12, 0),
    deviceId: 'DEV-01',
    discountType: discountType,
    discountValue: discountValue,
  );
}

/// Create an order item with the given parameters.
OrderItemEntity makeItem({
  String id = 'item-1',
  String productName = 'Adana Kebap',
  double quantity = 1,
  int unitPrice = 2500,
  int subtotal = 2500,
  int taxAmount = 0,
  List<OrderItemModifierEntity> modifiers = const [],
  bool sentToKitchen = false,
}) {
  return OrderItemEntity(
    id: id,
    tenantId: 'tenant-1',
    ticketId: 'ticket-1',
    productId: 'prod-$id',
    productName: productName,
    quantity: quantity,
    unitPrice: unitPrice,
    subtotal: subtotal,
    taxAmount: taxAmount,
    modifiers: modifiers,
    sentToKitchen: sentToKitchen,
  );
}

/// Create a modifier entity.
OrderItemModifierEntity makeModifier({
  String id = 'mod-1',
  String name = 'Extra Cheese',
  int priceDelta = 200,
}) {
  return OrderItemModifierEntity(
    id: id,
    orderItemId: 'item-1',
    modifierId: 'modifier-$id',
    modifierName: name,
    priceDelta: priceDelta,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // Add item
  // =========================================================================

  group('addItem', () {
    test('adding an item to empty ticket updates subtotal and total', () {
      final ticket = emptyTicket();
      expect(ticket.items, isEmpty);
      expect(ticket.subtotal, 0);
      expect(ticket.total, 0);

      final item = makeItem(subtotal: 2500);
      final updated = ticket.addItem(item);

      expect(updated.items.length, 1);
      expect(updated.subtotal, 2500);
      expect(updated.total, 2500);
    });

    test('adding multiple items accumulates subtotal', () {
      var ticket = emptyTicket();

      ticket = ticket.addItem(makeItem(
        id: 'item-1',
        productName: 'Kebap',
        subtotal: 2500,
      ));
      ticket = ticket.addItem(makeItem(
        id: 'item-2',
        productName: 'Salata',
        subtotal: 1200,
      ));
      ticket = ticket.addItem(makeItem(
        id: 'item-3',
        productName: 'Ayran',
        subtotal: 500,
      ));

      expect(ticket.items.length, 3);
      expect(ticket.subtotal, 4200);
      expect(ticket.total, 4200);
    });

    test('adding item with tax updates taxAmount and total', () {
      // Swiss MWST: prices are tax-inclusive (Bruttopreise).
      // subtotal = gross (tax already inside), taxAmount = extracted MwSt.
      // total = subtotal (gross), NOT subtotal + taxAmount (would double-count).
      final ticket = emptyTicket();
      final item = makeItem(subtotal: 2000, taxAmount: 150);
      final updated = ticket.addItem(item);

      expect(updated.subtotal, 2000);
      expect(updated.taxAmount, 150);
      // total = gross − discount = 2000 − 0 = 2000 (tax-inclusive)
      expect(updated.total, 2000);
    });

    test('adding item preserves existing items', () {
      var ticket = emptyTicket();
      final item1 = makeItem(id: 'item-1', subtotal: 1000);
      final item2 = makeItem(id: 'item-2', subtotal: 2000);

      ticket = ticket.addItem(item1);
      ticket = ticket.addItem(item2);

      expect(ticket.items.length, 2);
      expect(ticket.items[0].id, 'item-1');
      expect(ticket.items[1].id, 'item-2');
    });
  });

  // =========================================================================
  // Remove item
  // =========================================================================

  group('removeItem', () {
    test('removing an item recalculates total', () {
      var ticket = emptyTicket();
      ticket = ticket.addItem(makeItem(id: 'item-1', subtotal: 2500));
      ticket = ticket.addItem(makeItem(id: 'item-2', subtotal: 1200));

      expect(ticket.subtotal, 3700);

      final updated = ticket.removeItem('item-1');
      expect(updated.items.length, 1);
      expect(updated.subtotal, 1200);
      expect(updated.total, 1200);
    });

    test('removing last item produces zero total', () {
      var ticket = emptyTicket();
      ticket = ticket.addItem(makeItem(id: 'item-1', subtotal: 2500));

      final updated = ticket.removeItem('item-1');
      expect(updated.items, isEmpty);
      expect(updated.subtotal, 0);
      expect(updated.total, 0);
    });

    test('removing non-existent item is a no-op', () {
      var ticket = emptyTicket();
      ticket = ticket.addItem(makeItem(id: 'item-1', subtotal: 2500));

      final updated = ticket.removeItem('non-existent');
      expect(updated.items.length, 1);
      expect(updated.subtotal, 2500);
    });

    test('removing item recalculates tax total', () {
      var ticket = emptyTicket();
      ticket = ticket.addItem(
          makeItem(id: 'item-1', subtotal: 2000, taxAmount: 150));
      ticket = ticket.addItem(
          makeItem(id: 'item-2', subtotal: 1000, taxAmount: 80));

      expect(ticket.taxAmount, 230);

      final updated = ticket.removeItem('item-1');
      expect(updated.taxAmount, 80);
      // tax-inclusive: total = subtotal (gross), not subtotal + tax
      expect(updated.total, 1000);
    });
  });

  // =========================================================================
  // Item with modifiers
  // =========================================================================

  group('items with modifiers', () {
    test('modifier price is included in item subtotal', () {
      final modifiers = [
        makeModifier(id: 'mod-1', name: 'Extra Cheese', priceDelta: 200),
        makeModifier(id: 'mod-2', name: 'Bacon', priceDelta: 300),
      ];

      // unitPrice 1500 + modifiers 200+300 = 2000 for qty 1
      final item = makeItem(
        id: 'item-1',
        unitPrice: 1500,
        subtotal: 2000,
        modifiers: modifiers,
      );

      final ticket = emptyTicket().addItem(item);
      expect(ticket.subtotal, 2000);
      expect(ticket.total, 2000);
      expect(ticket.items.first.modifiers.length, 2);
    });

    test('modifier calculateSubtotal matches expected', () {
      final item = OrderItemEntity(
        id: 'item-calc',
        tenantId: 'tenant-1',
        ticketId: 'ticket-1',
        productId: 'prod-1',
        productName: 'Burger',
        quantity: 2,
        unitPrice: 1500,
        subtotal: 0, // will recalculate
        modifiers: [
          makeModifier(priceDelta: 200),
          makeModifier(id: 'mod-2', priceDelta: 100),
        ],
      );

      // (1500 + 200 + 100) * 2 = 3600
      expect(item.calculateSubtotal(), 3600);
    });

    test('item with no modifiers: calculateSubtotal uses unitPrice * qty',
        () {
      final item = OrderItemEntity(
        id: 'item-no-mod',
        tenantId: 'tenant-1',
        ticketId: 'ticket-1',
        productId: 'prod-1',
        productName: 'Salad',
        quantity: 3,
        unitPrice: 800,
        subtotal: 0,
      );

      expect(item.calculateSubtotal(), 2400);
    });
  });

  // =========================================================================
  // Empty ticket
  // =========================================================================

  group('empty ticket', () {
    test('empty ticket has zero subtotal, total, and itemCount', () {
      final ticket = emptyTicket();
      expect(ticket.items, isEmpty);
      expect(ticket.subtotal, 0);
      expect(ticket.total, 0);
      expect(ticket.itemCount, 0);
    });

    test('empty ticket has draft status', () {
      final ticket = emptyTicket();
      expect(ticket.status, TicketStatus.draft);
    });
  });

  // =========================================================================
  // Order type
  // =========================================================================

  group('order type changes', () {
    test('copyWith changes orderType', () {
      final ticket = emptyTicket(orderType: OrderType.dineIn);
      expect(ticket.orderType, OrderType.dineIn);

      final updated = ticket.copyWith(orderType: OrderType.takeaway);
      expect(updated.orderType, OrderType.takeaway);
    });

    test('copyWith to delivery', () {
      final ticket = emptyTicket();
      final updated = ticket.copyWith(orderType: OrderType.delivery);
      expect(updated.orderType, OrderType.delivery);
    });

    test('order type change preserves items and totals', () {
      var ticket = emptyTicket();
      ticket = ticket.addItem(makeItem(subtotal: 2500));

      final updated = ticket.copyWith(orderType: OrderType.takeaway);
      expect(updated.orderType, OrderType.takeaway);
      expect(updated.items.length, 1);
      expect(updated.subtotal, 2500);
    });
  });

  // =========================================================================
  // Item count
  // =========================================================================

  group('itemCount', () {
    test('counts sum of quantities across all items', () {
      var ticket = emptyTicket();
      ticket = ticket.addItem(makeItem(
        id: 'item-1',
        quantity: 2,
        subtotal: 5000,
      ));
      ticket = ticket.addItem(makeItem(
        id: 'item-2',
        quantity: 3,
        subtotal: 2400,
      ));

      // 2 + 3 = 5
      expect(ticket.itemCount, 5);
    });

    test('single item with quantity 1', () {
      var ticket = emptyTicket();
      ticket = ticket.addItem(makeItem(quantity: 1, subtotal: 1000));
      expect(ticket.itemCount, 1);
    });
  });

  // =========================================================================
  // Discount types
  // =========================================================================

  group('discount types', () {
    test('no discount: total = subtotal (tax-inclusive, tax is inside gross)', () {
      // Swiss: subtotal is gross (tax already included). total = subtotal.
      final ticket = emptyTicket(discountType: DiscountType.none);
      final updated = ticket.addItem(makeItem(subtotal: 2000, taxAmount: 100));

      expect(updated.discountAmount, 0);
      expect(updated.total, 2000);
    });

    test('fixed discount: subtracts discountValue from total', () {
      final ticket = emptyTicket(
        discountType: DiscountType.fixed,
        discountValue: 500,
      );

      final updated = ticket.addItem(makeItem(subtotal: 3000, taxAmount: 0));

      expect(updated.discountAmount, 500);
      expect(updated.total, 2500);
    });

    test('percentage discount: calculates from subtotal', () {
      final ticket = emptyTicket(
        discountType: DiscountType.percentage,
        discountValue: 10, // 10%
      );

      final updated = ticket.addItem(makeItem(subtotal: 5000, taxAmount: 0));

      // 10% of 5000 = 500
      expect(updated.discountAmount, 500);
      expect(updated.total, 4500);
    });

    test('discount recalculates when items change', () {
      var ticket = emptyTicket(
        discountType: DiscountType.percentage,
        discountValue: 20, // 20%
      );

      ticket = ticket.addItem(makeItem(id: 'i1', subtotal: 1000));
      expect(ticket.discountAmount, 200); // 20% of 1000
      expect(ticket.total, 800);

      ticket = ticket.addItem(makeItem(id: 'i2', subtotal: 1000));
      expect(ticket.discountAmount, 400); // 20% of 2000
      expect(ticket.total, 1600);

      ticket = ticket.removeItem('i1');
      expect(ticket.discountAmount, 200); // 20% of 1000
      expect(ticket.total, 800);
    });

    test('total cannot go below zero with large discount', () {
      final ticket = emptyTicket(
        discountType: DiscountType.fixed,
        discountValue: 5000,
      );

      final updated = ticket.addItem(makeItem(subtotal: 1000));

      // 1000 - 5000 would be -4000, clamped to 0.
      expect(updated.total, 0);
    });
  });

  // =========================================================================
  // Status helpers
  // =========================================================================

  group('status helpers', () {
    test('isOpen for draft, open, sent, inProgress', () {
      for (final status in [
        TicketStatus.draft,
        TicketStatus.open,
        TicketStatus.sent,
        TicketStatus.inProgress,
      ]) {
        final ticket = emptyTicket().copyWith(status: status);
        expect(ticket.isOpen, true, reason: '$status should be open');
      }
    });

    test('isOpen is false for ready, served, completed, cancelled, voided', () {
      for (final status in [
        TicketStatus.ready,
        TicketStatus.served,
        TicketStatus.billRequested,
        TicketStatus.completed,
        TicketStatus.cancelled,
        TicketStatus.voided,
      ]) {
        final ticket = emptyTicket().copyWith(status: status);
        expect(ticket.isOpen, false, reason: '$status should not be open');
      }
    });

    test('isPaid only for completed', () {
      final completed =
          emptyTicket().copyWith(status: TicketStatus.completed);
      expect(completed.isPaid, true);

      final draft = emptyTicket().copyWith(status: TicketStatus.draft);
      expect(draft.isPaid, false);
    });
  });

  // =========================================================================
  // calculateTotals (idempotent recalculation)
  // =========================================================================

  group('calculateTotals', () {
    test('recalculates from existing items without adding or removing', () {
      // Simulate a ticket where subtotal was manually set wrong.
      final ticket = TicketEntity(
        id: 'ticket-2',
        tenantId: 'tenant-1',
        orderNumber: '0002',
        orderType: OrderType.dineIn,
        status: TicketStatus.draft,
        openedAt: DateTime(2026, 1, 15),
        deviceId: 'DEV-01',
        items: [
          makeItem(id: 'i1', subtotal: 1000),
          makeItem(id: 'i2', subtotal: 2000),
        ],
        subtotal: 999, // intentionally wrong
        total: 999,
      );

      final recalculated = ticket.calculateTotals();
      expect(recalculated.subtotal, 3000);
      expect(recalculated.total, 3000);
    });
  });

  // =========================================================================
  // copyWith
  // =========================================================================

  group('copyWith', () {
    test('changes only specified fields', () {
      final ticket = emptyTicket();
      final updated = ticket.copyWith(
        customerName: () => 'John',
        guestCount: 4,
        notes: () => 'Window seat',
      );

      expect(updated.customerName, 'John');
      expect(updated.guestCount, 4);
      expect(updated.notes, 'Window seat');
      // Unchanged fields.
      expect(updated.id, ticket.id);
      expect(updated.orderType, ticket.orderType);
    });

    test('nullable fields can be set to null', () {
      final ticket = emptyTicket().copyWith(
        customerName: () => 'John',
        tableId: () => 'table-1',
      );

      expect(ticket.customerName, 'John');

      final cleared = ticket.copyWith(
        customerName: () => null,
        tableId: () => null,
      );

      expect(cleared.customerName, isNull);
      expect(cleared.tableId, isNull);
    });
  });

  // =========================================================================
  // Equality
  // =========================================================================

  group('equality', () {
    test('tickets with same fields are equal', () {
      final a = emptyTicket();
      final b = emptyTicket();
      expect(a, equals(b));
    });

    test('tickets with different ids are not equal', () {
      final a = emptyTicket();
      final b = emptyTicket().copyWith(id: 'ticket-2');
      expect(a == b, false);
    });
  });
}
