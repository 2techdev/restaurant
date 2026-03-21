/// Shopping cart domain model for online ordering.
/// Prices are always integers (Rappen). VAT is calculated on the total.
library;

import 'package:gastrocore_online/core/utils/money.dart';
import 'package:gastrocore_online/domain/models/menu_models.dart';
import 'package:gastrocore_online/domain/models/order_models.dart';

// ---------------------------------------------------------------------------
// Cart item
// ---------------------------------------------------------------------------

class CartItem {
  final String id; // local UUID for cart identity
  final OnlineProduct product;
  final int quantity;
  final List<OnlineModifier> selectedModifiers;
  final String? notes;

  const CartItem({
    required this.id,
    required this.product,
    required this.quantity,
    this.selectedModifiers = const [],
    this.notes,
  });

  /// Unit price including modifier deltas, in Rappen.
  int get unitPrice {
    final modSum =
        selectedModifiers.fold(0, (sum, m) => sum + m.priceDelta);
    return product.price + modSum;
  }

  /// Line total in Rappen.
  int get lineTotal => unitPrice * quantity;

  CartItem copyWith({
    int? quantity,
    List<OnlineModifier>? selectedModifiers,
    String? notes,
  }) =>
      CartItem(
        id: id,
        product: product,
        quantity: quantity ?? this.quantity,
        selectedModifiers: selectedModifiers ?? this.selectedModifiers,
        notes: notes ?? this.notes,
      );
}

// ---------------------------------------------------------------------------
// Cart
// ---------------------------------------------------------------------------

class Cart {
  final List<CartItem> items;
  final OrderType? orderType;
  final int? tableNumber;
  final String? notes;

  const Cart({
    this.items = const [],
    this.orderType,
    this.tableNumber,
    this.notes,
  });

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  int get itemCount =>
      items.fold(0, (sum, item) => sum + item.quantity);

  /// Subtotal (ex VAT) in Rappen.
  int get subtotalCents =>
      items.fold(0, (sum, item) => sum + item.lineTotal);

  /// VAT rate based on order type.
  double get vatRate {
    if (orderType == OrderType.dineIn) return SwissVat.standard;
    if (orderType == OrderType.takeaway) return SwissVat.reduced;
    return SwissVat.standard; // default to standard if not yet chosen
  }

  /// VAT amount in Rappen (extracted from gross price).
  /// Products are stored at gross (tax-inclusive) prices per Swiss practice.
  int get vatCents =>
      Money(subtotalCents).extractTax(vatRate).cents;

  /// Net (ex-VAT) amount in Rappen.
  int get netCents => subtotalCents - vatCents;

  /// Total before 5-Rappen rounding.
  int get totalBeforeRounding => subtotalCents;

  /// Total after 5-Rappen rounding (for cash display).
  int get totalRounded =>
      Money(subtotalCents).roundTo5Rappen().cents;

  /// Rounding difference in Rappen (may be negative, zero, or positive).
  int get roundingCents => totalRounded - totalBeforeRounding;

  Cart copyWith({
    List<CartItem>? items,
    OrderType? orderType,
    int? tableNumber,
    String? notes,
    bool clearTableNumber = false,
    bool clearNotes = false,
  }) =>
      Cart(
        items: items ?? this.items,
        orderType: orderType ?? this.orderType,
        tableNumber:
            clearTableNumber ? null : (tableNumber ?? this.tableNumber),
        notes: clearNotes ? null : (notes ?? this.notes),
      );

  // ---------------------------------------------------------------------------
  // Mutation helpers (return new Cart)
  // ---------------------------------------------------------------------------

  Cart addItem(CartItem item) {
    // Check if same product+modifiers already in cart → increment quantity
    final existingIdx = items.indexWhere((i) =>
        i.product.id == item.product.id &&
        _modifierSetEquals(i.selectedModifiers, item.selectedModifiers));

    if (existingIdx >= 0) {
      final updated = List<CartItem>.from(items);
      updated[existingIdx] = updated[existingIdx].copyWith(
        quantity: updated[existingIdx].quantity + item.quantity,
      );
      return copyWith(items: updated);
    }
    return copyWith(items: [...items, item]);
  }

  Cart removeItem(String cartItemId) => copyWith(
        items: items.where((i) => i.id != cartItemId).toList(),
      );

  Cart updateQuantity(String cartItemId, int quantity) {
    if (quantity <= 0) return removeItem(cartItemId);
    final updated = items.map((i) {
      return i.id == cartItemId ? i.copyWith(quantity: quantity) : i;
    }).toList();
    return copyWith(items: updated);
  }

  Cart clear() => const Cart();

  // ---------------------------------------------------------------------------
  // Serialise to JSON for API submission
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toOrderPayload({
    required String restaurantId,
    String? customerName,
  }) =>
      {
        'restaurant_id': restaurantId,
        'order_type': orderType?.apiValue ?? 'dine_in',
        'table_number': tableNumber,
        'customer_name': customerName,
        'notes': notes,
        'channel': 'qr',
        'items': items
            .map((i) => {
                  'product_id': i.product.id,
                  'product_name': i.product.name,
                  'quantity': i.quantity,
                  'unit_price': i.unitPrice,
                  'notes': i.notes,
                  'modifiers': i.selectedModifiers
                      .map((m) => {
                            'modifier_id': m.id,
                            'modifier_name': m.name,
                            'price_delta': m.priceDelta,
                          })
                      .toList(),
                })
            .toList(),
      };
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

bool _modifierSetEquals(
    List<OnlineModifier> a, List<OnlineModifier> b) {
  if (a.length != b.length) return false;
  final aIds = a.map((m) => m.id).toSet();
  final bIds = b.map((m) => m.id).toSet();
  return aIds.difference(bIds).isEmpty;
}
