/// Menu screen — categories sidebar/tabs, product grid, search bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gastrocore_online/core/theme/app_theme.dart';
import 'package:gastrocore_online/domain/models/menu_models.dart';
import 'package:gastrocore_online/l10n/app_localizations.dart';
import 'package:gastrocore_online/providers/menu_provider.dart';
import 'package:gastrocore_online/widgets/cart_fab.dart';
import 'package:gastrocore_online/widgets/language_selector.dart';
import 'package:gastrocore_online/widgets/product_card.dart';

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

class _MenuScreenState extends ConsumerState<MenuScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedCategoryId;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final menuAsync = ref.watch(menuProvider(widget.restaurantId));

    return Scaffold(
      backgroundColor: OnlineColors.bgPage,
      appBar: _buildAppBar(context, l10n, menuAsync.valueOrNull),
      body: menuAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: OnlineColors.primary),
        ),
        error: (e, _) => _buildError(context, l10n),
        data: (menu) => _buildBody(context, l10n, menu),
      ),
      floatingActionButton: CartFab(restaurantId: widget.restaurantId),
    );
  }

  AppBar _buildAppBar(
    BuildContext context,
    AppLocalizations l10n,
    OnlineMenu? menu,
  ) {
    return AppBar(
      backgroundColor: OnlineColors.bgCard,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        onPressed: () => context.go('/${widget.restaurantId}'),
      ),
      title: Text(
        menu?.restaurant.name ?? 'Menu',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 8),
          child: LanguageSelector(onLight: true),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 56, color: OnlineColors.textDim),
          const SizedBox(height: 16),
          Text(l10n.errorLoadingMenu,
              textAlign: TextAlign.center,
              style: const TextStyle(color: OnlineColors.textSecondary)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () =>
                ref.read(menuProvider(widget.restaurantId).notifier).refresh(),
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    OnlineMenu menu,
  ) {
    final categories = menu.categories;

    // Filter products
    List<OnlineProduct> filteredProducts = menu.products
        .where((p) => p.isAvailable)
        .where((p) {
          if (_selectedCategoryId != null) {
            return p.categoryId == _selectedCategoryId;
          }
          return true;
        })
        .where((p) {
          if (_searchQuery.isEmpty) return true;
          return p.name
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ||
              (p.description?.toLowerCase() ?? '')
                  .contains(_searchQuery.toLowerCase());
        })
        .toList();

    return Column(
      children: [
        // Search bar
        Container(
          color: OnlineColors.bgCard,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: l10n.searchPlaceholder,
              prefixIcon:
                  const Icon(Icons.search, color: OnlineColors.textDim),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              isDense: true,
            ),
          ),
        ),

        // Category chips
        if (categories.isNotEmpty)
          Container(
            color: OnlineColors.bgCard,
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: categories.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _CategoryChip(
                      label: l10n.allCategories,
                      selected: _selectedCategoryId == null,
                      onTap: () =>
                          setState(() => _selectedCategoryId = null),
                    );
                  }
                  final cat = categories[i - 1];
                  return _CategoryChip(
                    label: cat.name,
                    selected: _selectedCategoryId == cat.id,
                    onTap: () =>
                        setState(() => _selectedCategoryId = cat.id),
                  );
                },
              ),
            ),
          ),

        const Divider(height: 1),

        // Product grid
        Expanded(
          child: filteredProducts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.search_off,
                          size: 48, color: OnlineColors.textDim),
                      const SizedBox(height: 12),
                      Text(
                        'No items found',
                        style: const TextStyle(
                            color: OnlineColors.textSecondary),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  gridDelegate:
                      SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 340,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: filteredProducts.length,
                  itemBuilder: (context, i) {
                    final product = filteredProducts[i];
                    return ProductCard(
                      product: product,
                      onTap: () => context.go(
                        '/${widget.restaurantId}/menu/product/${product.id}',
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Category chip
// ---------------------------------------------------------------------------

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? OnlineColors.primary
              : OnlineColors.chipBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : OnlineColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
