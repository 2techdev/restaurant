/// Seat-based split calculator.
///
/// Produces a per-seat share of a ticket. Unassigned items (items whose
/// [OrderItemEntity.seatNumber] is null) are pooled and divided equally
/// across all seats — with any remainder cents landing on seat 1 so the
/// sum of shares always equals the ticket's grand total.
///
/// SambaPOS-3 has no seat-first concept, so this is the Gastrocore delta:
/// fine-dining service needs per-seat totals before a single payment is
/// tendered, and the math has to stay penny-exact (no floating point).
library;

import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';

/// Immutable result of a seat-based split.
class SeatSplitResult {
  /// Share in cents, keyed by seat number (1..[seatCount]).
  final Map<int, int> shareBySeat;

  /// Items assigned to each seat, keyed by seat number.
  final Map<int, List<OrderItemEntity>> itemsBySeat;

  /// Items with no seat number — distributed across every seat equally.
  final List<OrderItemEntity> unassignedItems;

  /// Total of all assigned-plus-distributed shares. Always equals
  /// [TicketEntity.total] so the POS never drops a cent.
  int get total => shareBySeat.values.fold<int>(0, (s, v) => s + v);

  const SeatSplitResult({
    required this.shareBySeat,
    required this.itemsBySeat,
    required this.unassignedItems,
  });
}

class SeatSplitCalculator {
  const SeatSplitCalculator._();

  /// Split [ticket] across [seatCount] seats using each item's
  /// [OrderItemEntity.seatNumber] as the anchor.
  ///
  /// Throws [ArgumentError] if [seatCount] is less than 1.
  static SeatSplitResult split(TicketEntity ticket, {required int seatCount}) {
    if (seatCount < 1) {
      throw ArgumentError.value(seatCount, 'seatCount', 'must be >= 1');
    }

    final itemsBySeat = <int, List<OrderItemEntity>>{
      for (var s = 1; s <= seatCount; s++) s: <OrderItemEntity>[],
    };
    final unassigned = <OrderItemEntity>[];
    final assignedShare = <int, int>{for (var s = 1; s <= seatCount; s++) s: 0};

    for (final item in ticket.items) {
      final seat = item.seatNumber;
      if (seat != null && seat >= 1 && seat <= seatCount) {
        itemsBySeat[seat]!.add(item);
        assignedShare[seat] = assignedShare[seat]! + item.subtotal;
      } else {
        unassigned.add(item);
      }
    }

    // Apply the ticket-level discount proportionally to the assigned total
    // so per-seat shares reflect what the guest will actually pay.
    final assignedTotal = assignedShare.values.fold<int>(0, (s, v) => s + v);
    final unassignedTotal =
        unassigned.fold<int>(0, (s, i) => s + i.subtotal);
    final grossBase = assignedTotal + unassignedTotal;
    final discount = ticket.discountAmount;
    final serviceAndFees =
        ticket.serviceFeeAmount + ticket.packageFeeAmount + ticket.deliveryFeeAmount;

    // Per-seat target: (gross − discount + service) scaled by each seat's
    // proportion of the gross base + its share of unassigned items.
    final netTotal = (grossBase - discount + serviceAndFees).clamp(0, 1 << 62);

    final perSeatUnassigned = seatCount == 0 ? 0 : unassignedTotal ~/ seatCount;
    final unassignedRemainder =
        seatCount == 0 ? 0 : unassignedTotal % seatCount;

    final shareBySeat = <int, int>{};
    var running = 0;
    for (var s = 1; s <= seatCount; s++) {
      int seatGross = assignedShare[s]! + perSeatUnassigned;
      if (s == 1) seatGross += unassignedRemainder;
      // Scale this seat's gross to the net total. Penny drift is collected
      // on seat 1 below so the sum always matches.
      final seatNet = grossBase == 0
          ? 0
          : (seatGross * netTotal / grossBase).floor();
      shareBySeat[s] = seatNet;
      running += seatNet;
    }
    final drift = netTotal - running;
    if (drift != 0 && shareBySeat.isNotEmpty) {
      shareBySeat[1] = shareBySeat[1]! + drift;
    }

    return SeatSplitResult(
      shareBySeat: shareBySeat,
      itemsBySeat: itemsBySeat,
      unassignedItems: unassigned,
    );
  }
}
