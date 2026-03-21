/// Kiosk-specific in-memory cart line item.
///
/// Represents one product the customer has added to their kiosk order.
/// Prices are always in cents (Rappen). The cart is held in Riverpod
/// state and only persisted to the database when the customer confirms
/// payment — at that point [KioskOrderService.submitOrder] converts
/// these items into [OrderItemEntity] rows on a [TicketEntity].
library;

import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';

/// A single line in the kiosk cart.
class KioskCartItem {
  /// Unique local key for this line (used to identify it in the cart list).
  final String id;

  /// The product being ordered.
  final ProductEntity product;

  /// How many units the customer wants (always a whole number for kiosks).
  final int quantity;

  /// Selected modifiers (snapshotted name + priceDelta).
  final List<OrderItemModifierEntity> modifiers;

  /// Optional free-text special instructions.
  final String? notes;

  const KioskCartItem({
    required this.id,
    required this.product,
    required this.quantity,
    this.modifiers = const [],
    this.notes,
  });

  // -------------------------------------------------------------------------
  // Price helpers
  // -------------------------------------------------------------------------

  /// Unit price including modifier deltas, in cents.
  int get unitPrice =>
      product.price + modifiers.fold<int>(0, (s, m) => s + m.priceDelta);

  /// Line subtotal in cents (unitPrice × quantity).
  int get subtotal => unitPrice * quantity;

  // -------------------------------------------------------------------------
  // Mutation helpers
  // -------------------------------------------------------------------------

  KioskCartItem copyWith({
    String? id,
    ProductEntity? product,
    int? quantity,
    List<OrderItemModifierEntity>? modifiers,
    String? Function()? notes,
  }) {
    return KioskCartItem(
      id: id ?? this.id,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      modifiers: modifiers ?? this.modifiers,
      notes: notes != null ? notes() : this.notes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KioskCartItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'KioskCartItem(id: $id, product: ${product.name}, qty: $quantity, '
      'subtotal: $subtotal)';
}
