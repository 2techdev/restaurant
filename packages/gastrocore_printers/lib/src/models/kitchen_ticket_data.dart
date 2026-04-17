/// Print-ready DTO for a kitchen / bar ticket.
///
/// Items are grouped by [gang] (course). Allergy flags bubble up to a
/// bold/inverted line below the item.
library;

import 'package:gastrocore_models/gastrocore_models.dart';

class KitchenTicketItem {
  final String name;
  final int quantity; // integer — you don't order 1.5 steaks
  final List<String> modifierLines;
  final String? note;
  final List<String> allergens; // ["nuts", "dairy"] — printed red/bold

  const KitchenTicketItem({
    required this.name,
    required this.quantity,
    this.modifierLines = const [],
    this.note,
    this.allergens = const [],
  });

  factory KitchenTicketItem.fromOrderItem(OrderItemEntity item,
          {List<String> allergens = const []}) =>
      KitchenTicketItem(
        name: item.productName,
        quantity: item.quantity.ceil(),
        modifierLines:
            item.modifiers.map((m) => '+ ${m.modifierName}').toList(),
        note: item.notes,
        allergens: allergens,
      );
}

/// One gang (course) block on the ticket.
class KitchenTicketGang {
  final int courseNumber; // 1 = starter, 2 = main, ...
  final String label; // "Vorspeise", "Hauptgang", "Dessert"
  final List<KitchenTicketItem> items;

  const KitchenTicketGang({
    required this.courseNumber,
    required this.label,
    required this.items,
  });
}

class KitchenTicketData {
  final String ticketNumber;
  final String? tableLabel; // "Tisch 12"
  final int guestCount;
  final String? waiterName;
  final DateTime firedAt;

  /// True = only items that are new since the last fire. False = full ticket
  /// (useful for the "re-fire" button).
  final bool isFireDelta;

  final List<KitchenTicketGang> gangs;

  /// Free-form note from the waiter — "Allergy: nuts" or "VIP at table".
  final String? headerNote;

  const KitchenTicketData({
    required this.ticketNumber,
    this.tableLabel,
    this.guestCount = 1,
    this.waiterName,
    required this.firedAt,
    this.isFireDelta = true,
    required this.gangs,
    this.headerNote,
  });
}
