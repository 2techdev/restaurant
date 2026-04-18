/// Unit tests for [SeatSplitCalculator].
///
/// Invariants pinned here:
///  - The sum of all seat shares must equal the ticket's net total. No
///    penny drifts: every fractional remainder must land on seat 1.
///  - Unassigned items are distributed equally across seats; any remainder
///    cents attach to seat 1.
///  - Discounts and service charge are applied proportionally, not flat.
///
/// Run with:
///   flutter test test/features/payments/seat_split_calculator_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/payments/domain/services/seat_split_calculator.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

OrderItemEntity _item({
  required String id,
  required int subtotal,
  int? seatNumber,
}) {
  return OrderItemEntity(
    id: id,
    tenantId: 'T1',
    ticketId: 'TKT1',
    productId: 'P-$id',
    productName: 'Item $id',
    quantity: 1,
    unitPrice: subtotal,
    subtotal: subtotal,
    seatNumber: seatNumber,
  );
}

TicketEntity _ticket(
  List<OrderItemEntity> items, {
  int discountAmount = 0,
  int serviceFeeAmount = 0,
}) {
  final subtotal = items.fold<int>(0, (s, i) => s + i.subtotal);
  return TicketEntity(
    id: 'TKT1',
    tenantId: 'T1',
    orderNumber: '0001',
    orderType: OrderType.dineIn,
    items: items,
    subtotal: subtotal,
    discountAmount: discountAmount,
    serviceFeeAmount: serviceFeeAmount,
    total: subtotal - discountAmount + serviceFeeAmount,
    openedAt: DateTime(2026, 4, 17),
    deviceId: 'DEV1',
  );
}

void main() {
  group('SeatSplitCalculator.split — invariant: sum equals net total', () {
    test('simple two-seat split with clean assignment', () {
      final ticket = _ticket([
        _item(id: 'a', subtotal: 3000, seatNumber: 1),
        _item(id: 'b', subtotal: 2000, seatNumber: 2),
      ]);

      final result = SeatSplitCalculator.split(ticket, seatCount: 2);

      expect(result.shareBySeat[1], 3000);
      expect(result.shareBySeat[2], 2000);
      expect(result.total, 5000);
      expect(result.unassignedItems, isEmpty);
    });

    test('unassigned items split equally across seats', () {
      final ticket = _ticket([
        _item(id: 'shared', subtotal: 3000), // no seat
      ]);

      final result = SeatSplitCalculator.split(ticket, seatCount: 3);

      expect(result.shareBySeat[1], 1000);
      expect(result.shareBySeat[2], 1000);
      expect(result.shareBySeat[3], 1000);
      expect(result.unassignedItems.length, 1);
    });

    test('penny remainder lands on seat 1 so sum never drifts', () {
      final ticket = _ticket([
        _item(id: 'shared', subtotal: 1001), // 1001 ÷ 3 = 333 rem 2
      ]);

      final result = SeatSplitCalculator.split(ticket, seatCount: 3);

      // Seat 1 absorbs the remainder 2 cents on top of 333.
      expect(result.shareBySeat[1], 335);
      expect(result.shareBySeat[2], 333);
      expect(result.shareBySeat[3], 333);
      expect(result.total, 1001);
    });

    test('mix of assigned and unassigned keeps exact total', () {
      final ticket = _ticket([
        _item(id: 'a', subtotal: 4000, seatNumber: 1),
        _item(id: 'b', subtotal: 2500, seatNumber: 2),
        _item(id: 'shared', subtotal: 1500),
      ]);

      final result = SeatSplitCalculator.split(ticket, seatCount: 2);

      // Seat 1: 4000 + (1500/2 + rem 0) = 4750; Seat 2: 2500 + 750 = 3250.
      expect(result.shareBySeat[1], 4750);
      expect(result.shareBySeat[2], 3250);
      expect(result.total, 8000);
    });
  });

  group('SeatSplitCalculator.split — discount + service charge', () {
    test('fixed discount is applied proportionally', () {
      final ticket = _ticket([
        _item(id: 'a', subtotal: 6000, seatNumber: 1),
        _item(id: 'b', subtotal: 4000, seatNumber: 2),
      ], discountAmount: 1000);

      final result = SeatSplitCalculator.split(ticket, seatCount: 2);

      // Net total = 9000. Seat 1 share proportional to 6000/10000 = 60% → 5400.
      expect(result.shareBySeat[1], 5400);
      expect(result.shareBySeat[2], 3600);
      expect(result.total, 9000);
    });

    test('service charge is included in each seat share', () {
      final ticket = _ticket([
        _item(id: 'a', subtotal: 10000, seatNumber: 1),
        _item(id: 'b', subtotal: 10000, seatNumber: 2),
      ], serviceFeeAmount: 2000);

      final result = SeatSplitCalculator.split(ticket, seatCount: 2);

      // Gross base = 20000, +2000 service, no discount → 22000 total, equal split.
      expect(result.shareBySeat[1], 11000);
      expect(result.shareBySeat[2], 11000);
      expect(result.total, 22000);
    });
  });

  group('SeatSplitCalculator.split — edge cases', () {
    test('throws ArgumentError on seatCount < 1', () {
      final ticket = _ticket([_item(id: 'a', subtotal: 1000)]);
      expect(() => SeatSplitCalculator.split(ticket, seatCount: 0),
          throwsArgumentError);
    });

    test('empty ticket returns zero shares without dividing by zero', () {
      final ticket = _ticket([]);
      final result = SeatSplitCalculator.split(ticket, seatCount: 4);
      expect(result.shareBySeat.values, everyElement(0));
      expect(result.total, 0);
    });

    test('item assigned to out-of-range seat falls back to unassigned', () {
      final ticket = _ticket([
        _item(id: 'a', subtotal: 2000, seatNumber: 7), // beyond seatCount=2
      ]);
      final result = SeatSplitCalculator.split(ticket, seatCount: 2);
      expect(result.unassignedItems.length, 1);
      expect(result.shareBySeat[1], 1000);
      expect(result.shareBySeat[2], 1000);
    });
  });
}
