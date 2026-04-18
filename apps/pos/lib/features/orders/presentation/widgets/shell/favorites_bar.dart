// TODO(v2): Move to RestaurantSettings.favorites (JSON column) when the cloud
// backoffice lands. For pilot the list is persisted locally via
// SharedPreferences; Settings → "Hızlı Erişim Butonları" is the CRUD surface.
//
/// Favorites quick bar — a horizontal strip above the product grid with
/// "function-assignable" shortcut buttons.
///
/// Two action types are supported:
///   * [FavoriteAction.addProduct] — tap adds the matched product to the cart
///   * [FavoriteAction.openCategory] — tap switches the product grid to the
///     matched category (writes [selectedCategoryProvider]).
///
/// Targets are matched by **name** (case-insensitive contains fallback) so
/// the same seed list keeps working across the per-install UUIDs generated
/// by the demo data seeder. Restaurant owners can add / rename / reorder /
/// delete buttons from Settings — the bar itself is read-only.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';

// ---------------------------------------------------------------------------
// FavoriteButton data model — action + target + label (+ optional colour)
// ---------------------------------------------------------------------------

enum FavoriteAction { addProduct, openCategory }

@immutable
class FavoriteButton {
  const FavoriteButton({
    required this.id,
    required this.action,
    required this.target,
    required this.label,
    required this.sortOrder,
    this.color,
  });

  /// Stable local identifier (monotonically increasing string).
  final String id;

  /// What tapping the button does.
  final FavoriteAction action;

  /// Name-based lookup key (case-insensitive contains). Future: real UUID.
  final String target;

  /// Rendered label. Uppercased at render time.
  final String label;

  /// Ascending sort order — lower first.
  final int sortOrder;

  /// Optional colour override. `null` uses the semantic default
  /// (green for product, orange for category).
  final Color? color;

  FavoriteButton copyWith({
    FavoriteAction? action,
    String? target,
    String? label,
    int? sortOrder,
    Color? color,
    bool clearColor = false,
  }) {
    return FavoriteButton(
      id: id,
      action: action ?? this.action,
      target: target ?? this.target,
      label: label ?? this.label,
      sortOrder: sortOrder ?? this.sortOrder,
      color: clearColor ? null : (color ?? this.color),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action.name,
        'target': target,
        'label': label,
        'sort_order': sortOrder,
        if (color != null) 'color': color!.toARGB32(),
      };

  static FavoriteButton fromJson(Map<String, dynamic> json) {
    final actionStr = json['action'] as String? ?? 'addProduct';
    final action = FavoriteAction.values.firstWhere(
      (a) => a.name == actionStr,
      orElse: () => FavoriteAction.addProduct,
    );
    final colorArgb = json['color'] as int?;
    return FavoriteButton(
      id: json['id'] as String? ?? '',
      action: action,
      target: json['target'] as String? ?? '',
      label: json['label'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 0,
      color: colorArgb == null ? null : Color(colorArgb),
    );
  }
}

/// Default seed shown on first launch. Matches the pilot demo catalogue.
const List<FavoriteButton> kDefaultFavorites = <FavoriteButton>[
  FavoriteButton(
    id: 'seed-1',
    action: FavoriteAction.addProduct,
    target: 'Coca-Cola Zero',
    label: 'Cola Zero',
    sortOrder: 0,
  ),
  FavoriteButton(
    id: 'seed-2',
    action: FavoriteAction.addProduct,
    target: 'Mineralwasser',
    label: 'Su',
    sortOrder: 1,
  ),
  FavoriteButton(
    id: 'seed-3',
    action: FavoriteAction.openCategory,
    target: 'Getränke',
    label: 'İçecekler',
    sortOrder: 2,
  ),
  FavoriteButton(
    id: 'seed-4',
    action: FavoriteAction.openCategory,
    target: 'Desserts',
    label: 'Tatlılar',
    sortOrder: 3,
  ),
];

// ---------------------------------------------------------------------------
// Persistence — SharedPreferences JSON array under `pos_favorites_v1`.
// ---------------------------------------------------------------------------

const String _prefsKey = 'pos_favorites_v1';

class FavoritesNotifier extends StateNotifier<List<FavoriteButton>> {
  FavoritesNotifier() : super(const []) {
    _load();
  }

  bool _loaded = false;
  int _idSeed = 1000;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      state = List<FavoriteButton>.from(kDefaultFavorites);
      _loaded = true;
      await _persist();
      return;
    }
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => FavoriteButton.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      state = list;
    } catch (_) {
      state = List<FavoriteButton>.from(kDefaultFavorites);
      await _persist();
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(state.map((b) => b.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
  }

  String _nextId() {
    _idSeed++;
    return 'fav-${DateTime.now().millisecondsSinceEpoch}-$_idSeed';
  }

  Future<void> add({
    required FavoriteAction action,
    required String target,
    required String label,
    Color? color,
  }) async {
    if (!_loaded) await _load();
    final next = FavoriteButton(
      id: _nextId(),
      action: action,
      target: target,
      label: label,
      sortOrder: state.isEmpty
          ? 0
          : state.map((b) => b.sortOrder).reduce((a, b) => a > b ? a : b) + 1,
      color: color,
    );
    state = [...state, next];
    await _persist();
  }

  Future<void> update(
    String id, {
    FavoriteAction? action,
    String? target,
    String? label,
    Color? color,
    bool clearColor = false,
  }) async {
    state = [
      for (final b in state)
        if (b.id == id)
          b.copyWith(
            action: action,
            target: target,
            label: label,
            color: color,
            clearColor: clearColor,
          )
        else
          b,
    ];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((b) => b.id != id).toList();
    await _persist();
  }

  Future<void> reorder(List<String> orderedIds) async {
    final byId = {for (final b in state) b.id: b};
    final reordered = <FavoriteButton>[];
    for (var i = 0; i < orderedIds.length; i++) {
      final existing = byId[orderedIds[i]];
      if (existing == null) continue;
      reordered.add(existing.copyWith(sortOrder: i));
    }
    state = reordered;
    await _persist();
  }
}

/// Global favorites list — rendered by [FavoritesBar], edited via Settings.
final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<FavoriteButton>>((ref) {
  return FavoritesNotifier();
});

// ---------------------------------------------------------------------------
// Providers — all-active products (category-independent) for favorites lookup
// ---------------------------------------------------------------------------

/// Returns *all* active products for the current tenant, unfiltered by
/// [selectedCategoryProvider]. The POS [productsProvider] applies the
/// category filter; the favorites bar needs the raw list so it can resolve
/// targets regardless of what's currently on screen.
final allActiveProductsProvider =
    FutureProvider<List<ProductEntity>>((ref) async {
  final repo = ref.watch(menuRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getAllProducts(tenantId);
});

// ---------------------------------------------------------------------------
// FavoritesBar widget
// ---------------------------------------------------------------------------

class FavoritesBar extends ConsumerWidget {
  const FavoritesBar({
    super.key,
    required this.onAddProduct,
  });

  /// Called when a [FavoriteAction.addProduct] button is tapped and the
  /// matching product is found. Wired to the same ticket-add flow as
  /// [ProductGrid].
  final void Function(ProductEntity product) onAddProduct;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final productsAsync = ref.watch(allActiveProductsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    final products = productsAsync.valueOrNull ?? const <ProductEntity>[];
    final categories =
        categoriesAsync.valueOrNull ?? const <CategoryEntity>[];

    return Container(
      color: GcColors.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space16,
        vertical: AppTokens.space8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            width: 64,
            child: Center(
              child: Text(
                'HIZLI',
                style: TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: GcColors.onSurfaceVariant,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.space12),
          if (favorites.isEmpty)
            const Expanded(child: SizedBox.shrink())
          else
            for (var i = 0; i < favorites.length; i++) ...[
              if (i > 0) const SizedBox(width: AppTokens.space8),
              Expanded(
                child: _FavoriteTile(
                  button: favorites[i],
                  onTap: () => _dispatch(
                    ref: ref,
                    button: favorites[i],
                    products: products,
                    categories: categories,
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }

  void _dispatch({
    required WidgetRef ref,
    required FavoriteButton button,
    required List<ProductEntity> products,
    required List<CategoryEntity> categories,
  }) {
    switch (button.action) {
      case FavoriteAction.addProduct:
        final match = _matchProductByName(products, button.target);
        if (match == null) return; // silently skip if seed missing
        onAddProduct(match);
      case FavoriteAction.openCategory:
        final match = _matchCategoryByName(categories, button.target);
        if (match == null) return;
        ref.read(selectedCategoryProvider.notifier).state = match;
    }
  }

  ProductEntity? _matchProductByName(
    List<ProductEntity> products,
    String target,
  ) {
    final needle = target.toLowerCase().trim();
    for (final p in products) {
      if (p.name.toLowerCase() == needle) return p;
    }
    for (final p in products) {
      if (p.name.toLowerCase().contains(needle)) return p;
    }
    return null;
  }

  String? _matchCategoryByName(
    List<CategoryEntity> categories,
    String target,
  ) {
    final needle = target.toLowerCase().trim();
    for (final c in categories) {
      if (c.name.toLowerCase() == needle) return c.id;
    }
    for (final c in categories) {
      if (c.name.toLowerCase().contains(needle)) return c.id;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// _FavoriteTile — one button. Green for products, orange for categories.
// ---------------------------------------------------------------------------

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({required this.button, required this.onTap});

  final FavoriteButton button;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = button.color ??
        (button.action == FavoriteAction.addProduct
            ? GcColors.catGreen
            : GcColors.catOrange);

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        splashColor: button.action == FavoriteAction.addProduct
            ? GcColors.catDarkGreen
            : GcColors.catYellow,
        highlightColor: button.action == FavoriteAction.addProduct
            ? GcColors.catDarkGreen
            : GcColors.catYellow,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: kInsetHighlight, width: 2),
            ),
          ),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.space12),
            alignment: Alignment.center,
            child: Text(
              button.label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'WorkSans',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
