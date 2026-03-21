/// Riverpod providers for the GastroCore Kiosk feature.
///
/// State hierarchy:
///   [kioskSessionProvider]     — the full mutable session (cart + order type)
///   [kioskCartItemsProvider]   — derived: just the cart items list
///   [kioskOrderTypeProvider]   — derived: dine-in or takeaway
///   [kioskCartTotalProvider]   — derived: gross subtotal in cents
///   [kioskOrderServiceProvider] — KioskOrderService singleton
///   [kioskCategoriesProvider]  — categories for the menu browser
///   [kioskSelectedCategoryProvider] — which category is on-screen
///   [kioskProductsProvider]    — products in the selected category
///   [kioskAllProductsProvider] — all products (for productId lookup)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/kitchen/presentation/providers/kitchen_provider.dart';
import 'package:gastrocore_pos/features/kiosk/domain/kiosk_cart_item.dart';
import 'package:gastrocore_pos/features/kiosk/services/kiosk_order_service.dart';
import 'package:gastrocore_pos/features/menu/data/repositories/menu_repository_impl.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';

// ---------------------------------------------------------------------------
// KioskSessionState
// ---------------------------------------------------------------------------

/// Full kiosk session state: cart contents + dine-in/takeaway selection.
class KioskSessionState {
  final List<KioskCartItem> items;
  final OrderType orderType;

  /// Set after a successful order submission; null otherwise.
  final String? confirmedOrderNumber;

  const KioskSessionState({
    this.items = const [],
    this.orderType = OrderType.dineIn,
    this.confirmedOrderNumber,
  });

  KioskSessionState copyWith({
    List<KioskCartItem>? items,
    OrderType? orderType,
    String? Function()? confirmedOrderNumber,
  }) {
    return KioskSessionState(
      items: items ?? this.items,
      orderType: orderType ?? this.orderType,
      confirmedOrderNumber: confirmedOrderNumber != null
          ? confirmedOrderNumber()
          : this.confirmedOrderNumber,
    );
  }

  // Derived totals ──────────────────────────────────────────────────────────

  int get subtotal => items.fold<int>(0, (s, i) => s + i.subtotal);

  int get itemCount => items.fold<int>(0, (s, i) => s + i.quantity);

  bool get isEmpty => items.isEmpty;
}

// ---------------------------------------------------------------------------
// KioskSessionNotifier
// ---------------------------------------------------------------------------

class KioskSessionNotifier extends StateNotifier<KioskSessionState> {
  KioskSessionNotifier() : super(const KioskSessionState());

  // Cart mutations ──────────────────────────────────────────────────────────

  /// Add [product] with optional modifiers. If the same product+modifiers
  /// combination already exists, increment its quantity instead.
  void addItem(
    ProductEntity product, {
    int quantity = 1,
    List modifiers = const [],
    String? notes,
  }) {
    final existing = state.items.indexWhere(
      (i) =>
          i.product.id == product.id &&
          _modifierKey(i.modifiers) == _modifierKey(modifiers) &&
          i.notes == notes,
    );

    if (existing >= 0) {
      final updated = List<KioskCartItem>.from(state.items);
      updated[existing] = updated[existing].copyWith(
        quantity: updated[existing].quantity + quantity,
      );
      state = state.copyWith(items: updated);
    } else {
      final item = KioskCartItem(
        id: IdGenerator.generateId(),
        product: product,
        quantity: quantity,
        modifiers: List.from(modifiers),
        notes: notes,
      );
      state = state.copyWith(items: [...state.items, item]);
    }
  }

  /// Set the quantity of a cart item. If [quantity] ≤ 0 the item is removed.
  void setQuantity(String itemId, int quantity) {
    if (quantity <= 0) {
      removeItem(itemId);
      return;
    }
    final updated = state.items
        .map((i) => i.id == itemId ? i.copyWith(quantity: quantity) : i)
        .toList();
    state = state.copyWith(items: updated);
  }

  /// Remove a cart item by its [itemId].
  void removeItem(String itemId) {
    state = state.copyWith(
      items: state.items.where((i) => i.id != itemId).toList(),
    );
  }

  /// Clear all items from the cart.
  void clearCart() {
    state = state.copyWith(items: []);
  }

  // Order type ───────────────────────────────────────────────────────────────

  void setOrderType(OrderType orderType) {
    state = state.copyWith(orderType: orderType);
  }

  // Confirmation ─────────────────────────────────────────────────────────────

  void setConfirmedOrder(String orderNumber) {
    state = state.copyWith(
      confirmedOrderNumber: () => orderNumber,
    );
  }

  // Full reset ───────────────────────────────────────────────────────────────

  /// Return to a clean state (called on inactivity timeout or after
  /// confirmation screen auto-dismisses).
  void reset() {
    state = const KioskSessionState();
  }

  // Helpers ──────────────────────────────────────────────────────────────────

  static String _modifierKey(List modifiers) {
    final ids = modifiers.map((m) => m.modifierId as String).toList()..sort();
    return ids.join(',');
  }
}

// ---------------------------------------------------------------------------
// Session provider
// ---------------------------------------------------------------------------

final kioskSessionProvider =
    StateNotifierProvider<KioskSessionNotifier, KioskSessionState>(
  (ref) => KioskSessionNotifier(),
);

// Convenience derived providers ──────────────────────────────────────────────

final kioskCartItemsProvider = Provider<List<KioskCartItem>>(
  (ref) => ref.watch(kioskSessionProvider).items,
);

final kioskOrderTypeProvider = Provider<OrderType>(
  (ref) => ref.watch(kioskSessionProvider).orderType,
);

final kioskCartTotalProvider = Provider<int>(
  (ref) => ref.watch(kioskSessionProvider).subtotal,
);

// ---------------------------------------------------------------------------
// Kiosk locale (independent from POS AppSettings)
// ---------------------------------------------------------------------------

/// The locale for the current kiosk customer session.
///
/// Using a dedicated [StateProvider] rather than [localeProvider] so that
/// language selection on the kiosk does not affect POS/staff app settings.
/// Defaults to German (primary Swiss language).
final kioskLocaleProvider = StateProvider<Locale>(
  (ref) => const Locale('de'),
);

// ---------------------------------------------------------------------------
// KioskOrderService provider
// ---------------------------------------------------------------------------

final kioskOrderServiceProvider = Provider<KioskOrderService>((ref) {
  final db = ref.watch(databaseProvider);
  return KioskOrderService(
    orderRepo: OrderRepositoryImpl(db),
    kitchenRepo: ref.watch(kitchenRepositoryProvider),
  );
});

// ---------------------------------------------------------------------------
// Menu providers
// ---------------------------------------------------------------------------

final _kioskMenuRepoProvider = Provider<MenuRepositoryImpl>((ref) {
  return MenuRepositoryImpl(ref.watch(databaseProvider));
});

/// All active categories.
final kioskCategoriesProvider = FutureProvider<List<CategoryEntity>>((ref) {
  final repo = ref.watch(_kioskMenuRepoProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getAllCategories(tenantId);
});

/// Currently browsed category (null = show all / featured).
final kioskSelectedCategoryProvider =
    StateProvider<CategoryEntity?>((ref) => null);

/// Products for the selected category.
final kioskProductsProvider = FutureProvider<List<ProductEntity>>((ref) async {
  final category = ref.watch(kioskSelectedCategoryProvider);
  if (category == null) return const [];
  final repo = ref.watch(_kioskMenuRepoProvider);
  return repo.getProductsByCategory(category.id);
});

/// Single product by ID — used by [KioskProductDetailScreen].
final kioskProductByIdProvider =
    FutureProvider.family<ProductEntity?, String>((ref, productId) async {
  final repo = ref.watch(_kioskMenuRepoProvider);
  return repo.getProductById(productId);
});

/// All products — used for the product-detail screen lookup by ID.
final kioskAllProductsProvider =
    FutureProvider<List<ProductEntity>>((ref) async {
  final repo = ref.watch(_kioskMenuRepoProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getAllProducts(tenantId);
});
