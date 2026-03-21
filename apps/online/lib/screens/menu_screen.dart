/// Menu screen — Just Eat inspired layout.
/// Desktop: sticky category pills + section scroll + persistent cart sidebar.
/// Mobile: full-width sections + floating cart bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gastrocore_online/core/theme/app_theme.dart';
import 'package:gastrocore_online/core/utils/money.dart';
import 'package:gastrocore_online/domain/cart.dart';
import 'package:gastrocore_online/domain/models/menu_models.dart';
import 'package:gastrocore_online/providers/cart_provider.dart';
import 'package:gastrocore_online/providers/menu_provider.dart';
import 'package:gastrocore_online/widgets/language_selector.dart';
import 'package:gastrocore_online/widgets/product_card.dart';

// ---------------------------------------------------------------------------
// Responsive breakpoints
// ---------------------------------------------------------------------------
const double _kSidebarBreakpoint = 900.0;

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({
    super.key,
    required this.restaurantId,
    this.tableFromQr,
  });

  final String restaurantId;
  final int? tableFromQr;

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  String? _activeCategoryId;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _categoryKeys = {};

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCategory(String categoryId) {
    setState(() => _activeCategoryId = categoryId);
    final key = _categoryKeys[categoryId];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(menuProvider(widget.restaurantId));
    final cart = ref.watch(cartProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= _kSidebarBreakpoint;

    return Scaffold(
      backgroundColor: OnlineColors.bgPage,
      body: Column(
        children: [
          // Charcoal top nav
          _TopNav(
            restaurantId: widget.restaurantId,
            restaurantName: menuAsync.valueOrNull?.restaurant.name,
            cart: cart,
            isDesktop: isDesktop,
          ),

          Expanded(
            child: menuAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: OnlineColors.primary),
              ),
              error: (e, _) => _buildError(context, e),
              data: (menu) => _buildLayout(context, menu, cart, isDesktop),
            ),
          ),
        ],
      ),

      // Mobile cart bar
      bottomNavigationBar: isDesktop
          ? null
          : _MobileCartBar(restaurantId: widget.restaurantId, cart: cart),
    );
  }

  Widget _buildError(BuildContext context, Object e) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 56, color: OnlineColors.textDim),
          const SizedBox(height: 16),
          Text(
            'Menü konnte nicht geladen werden',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: OnlineColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () =>
                ref.read(menuProvider(widget.restaurantId).notifier).refresh(),
            child: const Text('Erneut versuchen'),
          ),
        ],
      ),
    );
  }

  Widget _buildLayout(
    BuildContext context,
    OnlineMenu menu,
    Cart cart,
    bool isDesktop,
  ) {
    // Ensure keys exist for all categories
    for (final cat in menu.categories) {
      _categoryKeys.putIfAbsent(cat.id, () => GlobalKey());
    }

    final menuContent = _MenuContent(
      menu: menu,
      searchQuery: _searchQuery,
      searchController: _searchController,
      activeCategoryId: _activeCategoryId,
      categoryKeys: _categoryKeys,
      scrollController: _scrollController,
      onCategoryTap: _scrollToCategory,
      onSearchChanged: (v) => setState(() => _searchQuery = v),
      restaurantId: widget.restaurantId,
    );

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: menuContent),
          _CartSidebar(
            restaurantId: widget.restaurantId,
            cart: cart,
          ),
        ],
      );
    }

    return menuContent;
  }
}

// ---------------------------------------------------------------------------
// Top navigation bar
// ---------------------------------------------------------------------------

class _TopNav extends StatelessWidget {
  const _TopNav({
    required this.restaurantId,
    required this.restaurantName,
    required this.cart,
    required this.isDesktop,
  });

  final String restaurantId;
  final String? restaurantName;
  final Cart cart;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: OnlineColors.charcoal,
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Back button
            GestureDetector(
              onTap: () => context.go('/$restaurantId'),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Restaurant name
            Expanded(
              child: Text(
                restaurantName ?? 'Menu',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Language selector
            const LanguageSelector(),

            // Cart icon (desktop only) — sidebar handles cart
            if (!isDesktop && !cart.isEmpty) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => context.go('/$restaurantId/cart'),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: OnlineColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.shopping_cart_outlined,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${cart.itemCount}',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: OnlineColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Menu content (scrollable area with category sections)
// ---------------------------------------------------------------------------

class _MenuContent extends StatelessWidget {
  const _MenuContent({
    required this.menu,
    required this.searchQuery,
    required this.searchController,
    required this.activeCategoryId,
    required this.categoryKeys,
    required this.scrollController,
    required this.onCategoryTap,
    required this.onSearchChanged,
    required this.restaurantId,
  });

  final OnlineMenu menu;
  final String searchQuery;
  final TextEditingController searchController;
  final String? activeCategoryId;
  final Map<String, GlobalKey> categoryKeys;
  final ScrollController scrollController;
  final void Function(String) onCategoryTap;
  final void Function(String) onSearchChanged;
  final String restaurantId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Container(
          color: OnlineColors.bgCard,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Gerichte suchen…',
              hintStyle: GoogleFonts.inter(
                color: OnlineColors.textDim,
                fontSize: 14,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: OnlineColors.textDim,
                size: 20,
              ),
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      color: OnlineColors.textDim,
                      onPressed: () => onSearchChanged(''),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              isDense: true,
            ),
          ),
        ),

        // Category pills — sticky
        if (menu.categories.isNotEmpty && searchQuery.isEmpty)
          _CategoryPillsBar(
            categories: menu.categories,
            activeCategoryId: activeCategoryId,
            onTap: onCategoryTap,
          ),

        // Product list
        Expanded(
          child: searchQuery.isNotEmpty
              ? _SearchResults(
                  products: menu.products
                      .where((p) => p.isAvailable)
                      .where((p) =>
                          p.name
                              .toLowerCase()
                              .contains(searchQuery.toLowerCase()) ||
                          (p.description?.toLowerCase() ?? '')
                              .contains(searchQuery.toLowerCase()))
                      .toList(),
                  restaurantId: restaurantId,
                )
              : _SectionedMenu(
                  menu: menu,
                  categoryKeys: categoryKeys,
                  scrollController: scrollController,
                  restaurantId: restaurantId,
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Category pills bar
// ---------------------------------------------------------------------------

class _CategoryPillsBar extends StatelessWidget {
  const _CategoryPillsBar({
    required this.categories,
    required this.activeCategoryId,
    required this.onTap,
  });

  final List<OnlineCategory> categories;
  final String? activeCategoryId;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: OnlineColors.bgCard,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: categories.length,
              itemBuilder: (context, i) {
                final cat = categories[i];
                final isActive = activeCategoryId == cat.id ||
                    (activeCategoryId == null && i == 0);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _CategoryPill(
                    label: cat.name,
                    isActive: isActive,
                    onTap: () => onTap(cat.id),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: OnlineColors.divider),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color:
              isActive ? OnlineColors.pillActiveBg : OnlineColors.pillInactiveBg,
          borderRadius: BorderRadius.circular(20),
          border: isActive
              ? Border.all(
                  color: OnlineColors.primary.withValues(alpha: 0.4),
                )
              : Border.all(color: Colors.transparent),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isActive ? OnlineColors.primary : OnlineColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sectioned menu (grouped by category)
// ---------------------------------------------------------------------------

class _SectionedMenu extends StatelessWidget {
  const _SectionedMenu({
    required this.menu,
    required this.categoryKeys,
    required this.scrollController,
    required this.restaurantId,
  });

  final OnlineMenu menu;
  final Map<String, GlobalKey> categoryKeys;
  final ScrollController scrollController;
  final String restaurantId;

  @override
  Widget build(BuildContext context) {
    // Group products by category
    final Map<String, List<OnlineProduct>> byCategory = {};
    for (final cat in menu.categories) {
      byCategory[cat.id] = menu.products
          .where((p) => p.categoryId == cat.id && p.isAvailable)
          .toList();
    }

    return SingleChildScrollView(
      controller: scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final cat in menu.categories)
            if (byCategory[cat.id]?.isNotEmpty ?? false) ...[
              // Category header
              Container(
                key: categoryKeys[cat.id],
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Text(
                  cat.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: OnlineColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ),

              // Products
              for (final product in byCategory[cat.id]!)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ProductCard(
                    product: product,
                    onTap: () => context.go(
                      '/$restaurantId/menu/product/${product.id}',
                    ),
                  ),
                ),
            ],

          const SizedBox(height: 120),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search results (flat list)
// ---------------------------------------------------------------------------

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.products,
    required this.restaurantId,
  });

  final List<OnlineProduct> products;
  final String restaurantId;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 48, color: OnlineColors.textDim),
            const SizedBox(height: 12),
            Text(
              'Keine Gerichte gefunden',
              style: GoogleFonts.inter(
                fontSize: 15,
                color: OnlineColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: products.length,
      itemBuilder: (ctx, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ProductCard(
          product: products[i],
          onTap: () =>
              ctx.go('/$restaurantId/menu/product/${products[i].id}'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop cart sidebar
// ---------------------------------------------------------------------------

class _CartSidebar extends ConsumerWidget {
  const _CartSidebar({required this.restaurantId, required this.cart});
  final String restaurantId;
  final Cart cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 360,
      decoration: const BoxDecoration(
        color: OnlineColors.bgCard,
        border: Border(
          left: BorderSide(color: OnlineColors.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text(
              'Ihre Bestellung',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: OnlineColors.textPrimary,
              ),
            ),
          ),
          const Divider(height: 1),

          // Cart items or empty state
          Expanded(
            child: cart.isEmpty
                ? _SidebarEmptyState()
                : _SidebarItemList(cart: cart, ref: ref),
          ),

          // Totals + checkout button
          if (!cart.isEmpty) _SidebarCheckout(cart: cart, restaurantId: restaurantId),
        ],
      ),
    );
  }
}

class _SidebarEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: OnlineColors.pillInactiveBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 32,
                color: OnlineColors.textDim,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Ihr Warenkorb ist leer',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: OnlineColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Fügen Sie Gerichte aus der Speisekarte hinzu',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: OnlineColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItemList extends StatelessWidget {
  const _SidebarItemList({required this.cart, required this.ref});
  final Cart cart;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: cart.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final item = cart.items[i];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Qty badge
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: OnlineColors.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${item.quantity}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Name + modifiers
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.product.name,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: OnlineColors.textPrimary,
                    ),
                  ),
                  if (item.selectedModifiers.isNotEmpty)
                    Text(
                      item.selectedModifiers.map((m) => m.name).join(', '),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: OnlineColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),

            // Price + remove
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Money(item.lineTotal).format('CHF'),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: OnlineColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () =>
                      ref.read(cartProvider.notifier).removeItem(item.id),
                  child: const Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 16,
                    color: OnlineColors.textDim,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SidebarCheckout extends StatelessWidget {
  const _SidebarCheckout({
    required this.cart,
    required this.restaurantId,
  });

  final Cart cart;
  final String restaurantId;

  @override
  Widget build(BuildContext context) {
    final vatLabel =
        cart.vatRate == SwissVat.standard ? '8.1' : '2.6';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: OnlineColors.divider)),
      ),
      child: Column(
        children: [
          // Subtotal row
          _TotalRow(
            label: 'Zwischensumme',
            value: Money(cart.subtotalCents).format('CHF'),
          ),
          const SizedBox(height: 4),
          _TotalRow(
            label: 'MwSt. ($vatLabel%)',
            value: Money(cart.vatCents).format('CHF'),
            dim: true,
          ),
          if (cart.roundingCents != 0) ...[
            const SizedBox(height: 4),
            _TotalRow(
              label: 'Rundung',
              value: '${cart.roundingCents < 0 ? '-' : '+'}${Money(cart.roundingCents.abs()).format('CHF')}',
              dim: true,
            ),
          ],
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          _TotalRow(
            label: 'Gesamt',
            value: Money(cart.totalRounded).format('CHF'),
            bold: true,
          ),
          const SizedBox(height: 14),

          // Checkout button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/$restaurantId/cart'),
              style: ElevatedButton.styleFrom(
                backgroundColor: OnlineColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kRadiusLarge),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Zur Kasse',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${cart.itemCount}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.dim = false,
  });

  final String label;
  final String value;
  final bool bold;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final color = dim ? OnlineColors.textSecondary : OnlineColors.textPrimary;
    final weight = bold ? FontWeight.w700 : FontWeight.w400;
    final size = bold ? 15.0 : 13.0;

    return Row(
      children: [
        Text(label,
            style:
                GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color)),
        const Spacer(),
        Text(value,
            style: GoogleFonts.inter(
                fontSize: size, fontWeight: weight, color: color)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile cart bottom bar
// ---------------------------------------------------------------------------

class _MobileCartBar extends StatelessWidget {
  const _MobileCartBar({required this.restaurantId, required this.cart});
  final String restaurantId;
  final Cart cart;

  @override
  Widget build(BuildContext context) {
    if (cart.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: OnlineColors.bgCard,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: () => context.go('/$restaurantId/cart'),
        style: ElevatedButton.styleFrom(
          backgroundColor: OnlineColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusLarge),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          elevation: 0,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${cart.itemCount}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Warenkorb ansehen',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              Money(cart.subtotalCents).format('CHF'),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
