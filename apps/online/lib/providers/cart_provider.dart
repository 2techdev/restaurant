/// Cart state provider.
/// Holds a [Cart] and exposes mutation helpers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_online/domain/cart.dart';
import 'package:gastrocore_online/domain/models/menu_models.dart';
import 'package:gastrocore_online/domain/models/order_models.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

final cartProvider = StateNotifierProvider<CartNotifier, Cart>((ref) {
  return CartNotifier();
});

class CartNotifier extends StateNotifier<Cart> {
  CartNotifier() : super(const Cart());

  void addProduct(
    OnlineProduct product, {
    int quantity = 1,
    List<OnlineModifier> selectedModifiers = const [],
    String? notes,
  }) {
    final item = CartItem(
      id: _uuid.v4(),
      product: product,
      quantity: quantity,
      selectedModifiers: selectedModifiers,
      notes: notes,
    );
    state = state.addItem(item);
  }

  void removeItem(String cartItemId) {
    state = state.removeItem(cartItemId);
  }

  void updateQuantity(String cartItemId, int quantity) {
    state = state.updateQuantity(cartItemId, quantity);
  }

  void setOrderType(OrderType type) {
    state = state.copyWith(orderType: type);
  }

  void setTableNumber(int? number) {
    if (number == null) {
      state = state.copyWith(clearTableNumber: true);
    } else {
      state = state.copyWith(tableNumber: number);
    }
  }

  void setNotes(String? notes) {
    if (notes == null || notes.isEmpty) {
      state = state.copyWith(clearNotes: true);
    } else {
      state = state.copyWith(notes: notes);
    }
  }

  void clear() {
    state = const Cart();
  }
}
