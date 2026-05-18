/// Menu / Order-taking tab content - OrderPin-inspired design.
///
/// Three-column layout: left text-based category sidebar, center product grid
/// with quantity badges, right order panel with Ordering/Ordered tabs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/combo_picker_dialog.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/modifier_dialog.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/menu_settings_dialog.dart';
import 'package:gastrocore_pos/features/gang/presentation/providers/gang_provider.dart';

// ---------------------------------------------------------------------------
// Design Tokens
// ---------------------------------------------------------------------------

abstract final class _Tok {
  static const Color surfaceBase = Color(0xFF111319);
  static const Color surfaceLow = Color(0xFF1A1D27);
  static const Color surfaceMedium = Color(0xFF222633);
  static const Color surfaceHigh = Color(0xFF2A2F3D);
  static const Color textPrimary = Color(0xFFF0F0F5);
  static const Color textSecondary = Color(0xFF8E8E9A);
  static const Color textDim = Color(0xFF5A5A6A);
  static const Color accentBlue = Color(0xFF528DFF);
  static const Color accentBlueLight = Color(0xFFAFC6FF);
  static const Color badgeRed = Color(0xFFEF4444);
}

// ---------------------------------------------------------------------------
// Menu Order Tab
// ---------------------------------------------------------------------------

class MenuOrderTab extends ConsumerStatefulWidget {
  const MenuOrderTab({super.key});

  @override
  ConsumerState<MenuOrderTab> createState() => _MenuOrderTabState();
}

class _MenuOrderTabState extends ConsumerState<MenuOrderTab>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();

  bool _showPictures = true;
  bool _useBigButtons = false;
  bool _showPrice = true;
  String _sortMode = 'default';
  bool _searchExpanded = false;

  /// 0 = Ordering, 1 = Ordered
  int _orderPanelTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureTicket();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _ensureTicket() async {
    final ticket = ref.read(currentTicketProvider);
    if (ticket == null) {
      final user = ref.read(currentUserProvider);
      await ref.read(currentTicketProvider.notifier).createNewTicket(
            deviceId: 'DEV-POS-01',
            waiterId: user?.id,
          );
    }
  }

  // -------------------------------------------------------------------------
  // Formatting helpers
  // -------------------------------------------------------------------------

  String _formatCHF(int cents) {
    final isNeg = cents < 0;
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return '${isNeg ? '-' : ''}CHF $whole.$frac';
  }

  List<ProductEntity> _sortProducts(List<ProductEntity> products) {
    final sorted = List<ProductEntity>.from(products);
    switch (_sortMode) {
      case 'alphabetical':
        sorted.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'sales':
        sorted.sort((a, b) => b.price.compareTo(a.price));
        break;
      case 'default':
      default:
        sorted.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
        break;
    }
    return sorted;
  }

  String _orderTypeLabel(OrderType? type) {
    switch (type) {
      case OrderType.dineIn:
        return 'Dine In';
      case OrderType.takeaway:
        return 'Takeaway';
      case OrderType.delivery:
        return 'Delivery';
      case OrderType.online:
        return 'Online';
      case null:
        return 'Dine In';
    }
  }

  IconData _orderTypeIcon(OrderType? type) {
    switch (type) {
      case OrderType.dineIn:
        return Icons.restaurant;
      case OrderType.takeaway:
        return Icons.shopping_bag_outlined;
      case OrderType.delivery:
        return Icons.delivery_dining;
      case OrderType.online:
        return Icons.language;
      case null:
        return Icons.restaurant;
    }
  }

  /// Build a map of productId -> total quantity in the ordering tab
  /// (items NOT yet sent to kitchen).
  Map<String, int> _buildCartQuantities(List<OrderItemEntity> items) {
    final map = <String, int>{};
    for (final item in items) {
      if (!item.sentToKitchen) {
        map[item.productId] = (map[item.productId] ?? 0) + item.quantity.ceil();
      }
    }
    return map;
  }

  // -------------------------------------------------------------------------
  // Product tap handler
  // -------------------------------------------------------------------------

  /// Resolve the category-level default Gang ID for a product.
  String? _categoryGangId(String categoryId) {
    final categories = ref.read(categoriesProvider).valueOrNull ?? [];
    final cat = categories.where((c) => c.id == categoryId).firstOrNull;
    return cat?.defaultGangId;
  }

  Future<void> _onProductTapped(ProductEntity product) async {
    final categoryGangId = _categoryGangId(product.categoryId);

    // Combo / set menu — open the component picker. The picker itself
    // handles adding the parent + each chosen component to the ticket.
    if (product.isCombo) {
      await showComboPickerDialog(context, comboProduct: product);
      return;
    }

    if (product.modifierGroups.isNotEmpty) {
      final modifierGroups = ModifierGroupData.fromProductEntity(product);

      final result = await showModifierDialog(
        context: context,
        productName: product.name,
        productPrice: product.price,
        modifierGroups: modifierGroups,
      );

      if (result != null) {
        final orderModifiers = <OrderItemModifierEntity>[
          for (final sel in result.flattened())
            OrderItemModifierEntity(
              id: IdGenerator.generateId(),
              orderItemId: '',
              modifierId: sel.option.id,
              modifierName: sel.displayName,
              priceDelta: sel.option.priceDelta,
              quantity: sel.quantity,
              note: sel.note,
            ),
        ];

        ref.read(currentTicketProvider.notifier).addItem(
              product,
              quantity: result.quantity.toDouble(),
              selectedModifiers: orderModifiers,
              notes: result.notes.isNotEmpty ? result.notes : null,
              categoryGangId: categoryGangId,
            );
      }
    } else {
      ref.read(currentTicketProvider.notifier).addItem(
            product,
            categoryGangId: categoryGangId,
          );
    }
  }

  // -------------------------------------------------------------------------
  // Settings dialog
  // -------------------------------------------------------------------------

  Future<void> _openSettingsDialog() async {
    final result = await showMenuSettingsDialog(
      context: context,
      currentSettings: MenuDisplaySettings(
        showPictures: _showPictures,
        useBigButtons: _useBigButtons,
        showPrice: _showPrice,
        sortMode: _sortMode,
      ),
    );

    if (result != null) {
      setState(() {
        _showPictures = result.showPictures;
        _useBigButtons = result.useBigButtons;
        _showPrice = result.showPrice;
        _sortMode = result.sortMode;
      });
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildCategorySidebar(),
        Expanded(child: _buildProductArea()),
        _buildOrderPanel(),
      ],
    );
  }

  // =========================================================================
  // CATEGORY SIDEBAR - text labels, no icons, left accent bar
  // =========================================================================

  Widget _buildCategorySidebar() {
    final categoriesAsync = ref.watch(categoriesProvider);
    final selectedId = ref.watch(selectedCategoryProvider);

    return Container(
      width: 130,
      color: _Tok.surfaceBase,
      child: categoriesAsync.when(
        loading: () => const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _Tok.accentBlue,
            ),
          ),
        ),
        error: (_, __) => const Center(
          child: Icon(Icons.error_outline, size: 20, color: _Tok.textDim),
        ),
        data: (categories) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              _CategoryItem(
                key: const Key('category_all'),
                label: 'All',
                isActive: selectedId == null,
                onTap: () =>
                    ref.read(selectedCategoryProvider.notifier).state = null,
              ),
              const _CategoryDivider(),
              ...List.generate(categories.length, (i) {
                final cat = categories[i];
                final isActive = cat.id == selectedId;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CategoryItem(
                      key: Key('category_$i'),
                      label: cat.name,
                      isActive: isActive,
                      onTap: () => ref
                          .read(selectedCategoryProvider.notifier)
                          .state = cat.id,
                    ),
                    const _CategoryDivider(),
                  ],
                );
              }),
            ],
          );
        },
      ),
    );
  }

  // =========================================================================
  // PRODUCT AREA - top bar + grid
  // =========================================================================

  Widget _buildProductArea() {
    final productsAsync = ref.watch(filteredProductsProvider);
    final ticket = ref.watch(currentTicketProvider);
    final cartQtys = _buildCartQuantities(ticket?.items ?? []);

    return ColoredBox(
      color: _Tok.surfaceLow,
      child: Column(
        children: [
          // Top bar
          _buildProductTopBar(),
          // Grid
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: _Tok.accentBlue),
              ),
              error: (err, _) => Center(
                child: Text('Error: $err',
                    style:
                        const TextStyle(fontSize: 13, color: _Tok.textDim)),
              ),
              data: (products) {
                if (products.isEmpty) {
                  return const Center(
                    child: Text('No products found',
                        style: TextStyle(fontSize: 14, color: _Tok.textDim)),
                  );
                }

                final sorted = _sortProducts(products);
                final crossAxisCount = _useBigButtons ? 3 : 4;

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: _showPictures ? 0.82 : 1.0,
                  ),
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final product = sorted[index];
                    final badgeQty = cartQtys[product.id] ?? 0;
                    return _ProductCard(
                      product: product,
                      showPictures: _showPictures,
                      showPrice: _showPrice,
                      badgeQuantity: badgeQty,
                      onTap: () => _onProductTapped(product),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          // "Menu" label (hidden when search expanded)
          if (!_searchExpanded) ...[
            const Text(
              'Menu',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _Tok.textPrimary,
              ),
            ),
            const Spacer(),
          ],

          // Search bar (expanded or icon)
          if (_searchExpanded)
            Expanded(
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: _Tok.surfaceMedium,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(Icons.search, size: 18, color: _Tok.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        onChanged: (v) => ref
                            .read(productSearchProvider.notifier)
                            .state = v,
                        style: const TextStyle(
                          fontSize: 14,
                          color: _Tok.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Search menu...',
                          hintStyle: TextStyle(fontSize: 14, color: _Tok.textDim),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _searchExpanded = false;
                          _searchController.clear();
                        });
                        ref.read(productSearchProvider.notifier).state = '';
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.close, size: 18, color: _Tok.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Search icon button
            _TopBarIconButton(
              icon: Icons.search,
              onTap: () => setState(() => _searchExpanded = true),
            ),
            const SizedBox(width: 8),
          ],

          // Resimli Mod toggle
          if (!_searchExpanded) ...[
            Flexible(
              child: GestureDetector(
                onTap: () => setState(() => _showPictures = !_showPictures),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: _showPictures
                        ? _Tok.accentBlue.withValues(alpha: 0.15)
                        : _Tok.surfaceMedium,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showPictures ? Icons.image : Icons.text_fields,
                        size: 16,
                        color: _showPictures
                            ? _Tok.accentBlue
                            : _Tok.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _showPictures ? 'Resimli Mod' : 'Text Mod',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _showPictures
                                ? _Tok.accentBlue
                                : _Tok.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Settings icon
            _TopBarIconButton(
              icon: Icons.settings,
              onTap: _openSettingsDialog,
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // ORDER PANEL (right) - Ordering / Ordered tabs
  // =========================================================================

  Widget _buildOrderPanel() {
    final ticket = ref.watch(currentTicketProvider);
    final gangMap = ref.watch(gangTemplateMapProvider);
    final allItems = ticket?.items ?? [];

    // Split items by sent status
    final orderingItems =
        allItems.where((i) => !i.sentToKitchen).toList();
    final orderedItems =
        allItems.where((i) => i.sentToKitchen).toList();

    final activeItems = _orderPanelTab == 0 ? orderingItems : orderedItems;

    // Totals
    final totalCents =
        allItems.fold<int>(0, (sum, item) => sum + item.subtotal);
    final totalItemCount =
        allItems.fold<int>(0, (sum, item) => sum + item.quantity.ceil());
    final hasOrderingItems = orderingItems.isNotEmpty;
    final hasAnyItems = allItems.isNotEmpty;

    return Container(
      width: 300,
      color: _Tok.surfaceBase,
      child: Column(
        children: [
          // Header: Order type + number
          _buildOrderPanelHeader(ticket),

          // Ordering / Ordered tab bar
          _buildOrderTabBar(orderingItems.length, orderedItems.length),

          // Item list
          Expanded(
            child: activeItems.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: activeItems.length,
                    itemBuilder: (context, index) {
                      final item = activeItems[index];
                      final isOrdering = _orderPanelTab == 0;
                      final gang = item.gangId != null
                          ? gangMap[item.gangId]
                          : null;
                      return _OrderItemRow(
                        item: item,
                        isEditable: isOrdering,
                        formatCHF: _formatCHF,
                        gangLabel: gang?.fallbackLabel,
                        gangColor: gang?.flutterColor,
                        onIncrement: isOrdering
                            ? () => ref
                                .read(currentTicketProvider.notifier)
                                .updateItemQuantity(
                                    item.id, item.quantity + 1)
                            : null,
                        onDecrement: isOrdering
                            ? () {
                                if (item.quantity > 1) {
                                  ref
                                      .read(currentTicketProvider.notifier)
                                      .updateItemQuantity(
                                          item.id, item.quantity - 1);
                                } else {
                                  ref
                                      .read(currentTicketProvider.notifier)
                                      .removeItem(item.id);
                                }
                              }
                            : null,
                        onDismissed: isOrdering
                            ? () => ref
                                .read(currentTicketProvider.notifier)
                                .removeItem(item.id)
                            : null,
                      );
                    },
                  ),
          ),

          // Footer: total + buttons
          _buildOrderPanelFooter(
            totalCents: totalCents,
            totalItemCount: totalItemCount,
            hasOrderingItems: hasOrderingItems,
            hasAnyItems: hasAnyItems,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderPanelHeader(TicketEntity? ticket) {
    final label = _orderTypeLabel(ticket?.orderType);
    final icon = _orderTypeIcon(ticket?.orderType);
    final orderNum = ticket?.orderNumber ?? '0001';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order type selector + order number
          Row(
            children: [
              Icon(icon, size: 16, color: _Tok.accentBlue),
              const SizedBox(width: 6),
              Text(
                '$label | #$orderNum',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _Tok.textPrimary,
                ),
              ),
              const Spacer(),
              // Three dots menu
              GestureDetector(
                onTap: () {},
                child: const Icon(Icons.more_vert, size: 18, color: _Tok.textDim),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Dine-In / Takeaway / Delivery selector
          Row(
            children: [
              _OrderTypeChip(
                key: const Key('order_type_dine_in'),
                label: 'Dine-In',
                icon: Icons.restaurant,
                isActive: ticket?.orderType == null || ticket?.orderType == OrderType.dineIn,
                onTap: () => _setOrderType(OrderType.dineIn),
              ),
              const SizedBox(width: 6),
              _OrderTypeChip(
                key: const Key('order_type_takeaway'),
                label: 'Takeaway',
                icon: Icons.shopping_bag_outlined,
                isActive: ticket?.orderType == OrderType.takeaway,
                onTap: () => _setOrderType(OrderType.takeaway),
              ),
              const SizedBox(width: 6),
              _OrderTypeChip(
                key: const Key('order_type_delivery'),
                label: 'Delivery',
                icon: Icons.delivery_dining,
                isActive: ticket?.orderType == OrderType.delivery,
                onTap: () => _setOrderType(OrderType.delivery),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _setOrderType(OrderType type) {
    final ticket = ref.read(currentTicketProvider);
    if (ticket != null) {
      ref.read(currentTicketProvider.notifier).updateOrderType(type);
    }
    setState(() {});
  }

  Widget _buildOrderTabBar(int orderingCount, int orderedCount) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _Tok.surfaceHigh, width: 1),
        ),
      ),
      child: Row(
        children: [
          _OrderTab(
            label: 'Ordering',
            count: orderingCount,
            isActive: _orderPanelTab == 0,
            onTap: () => setState(() => _orderPanelTab = 0),
          ),
          const SizedBox(width: 24),
          _OrderTab(
            label: 'Ordered',
            count: orderedCount,
            isActive: _orderPanelTab == 1,
            onTap: () => setState(() => _orderPanelTab = 1),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isOrdering = _orderPanelTab == 0;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOrdering ? Icons.add_shopping_cart : Icons.check_circle_outline,
            size: 40,
            color: _Tok.surfaceHigh,
          ),
          const SizedBox(height: 10),
          Text(
            isOrdering ? 'Select products to order' : 'No items sent yet',
            style: const TextStyle(fontSize: 13, color: _Tok.textDim),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderPanelFooter({
    required int totalCents,
    required int totalItemCount,
    required bool hasOrderingItems,
    required bool hasAnyItems,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: _Tok.surfaceLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Total row
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Total ($totalItemCount Items)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _Tok.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatCHF(totalCents),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _Tok.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          // "Order" button (send to kitchen) - visible when on Ordering tab
          if (_orderPanelTab == 0) ...[
            _GradientButton(
              key: const Key('order_btn'),
              label: 'Order',
              icon: Icons.restaurant_menu,
              enabled: hasOrderingItems,
              onTap: hasOrderingItems
                  ? () async {
                      await ref
                          .read(currentTicketProvider.notifier)
                          .sendToKitchen();
                      if (mounted) {
                        setState(() => _orderPanelTab = 1);
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 10),
          ],

          // "Check Out" button
          _GradientButton(
            key: const Key('checkout_btn'),
            label: 'Check Out',
            icon: Icons.arrow_forward,
            enabled: hasAnyItems,
            isSecondary: _orderPanelTab == 0,
            onTap: hasAnyItems
                ? () async {
                    try {
                      final notifier = ref.read(currentTicketProvider.notifier);
                      final ticket = ref.read(currentTicketProvider);
                      String? ticketId = ticket?.id;

                      // Save if draft (not yet persisted)
                      if (ticket?.status == TicketStatus.draft) {
                        final saved = await notifier.saveCurrentTicket();
                        ticketId = saved?.id;
                      } else {
                        ticketId = ticket?.id;
                      }

                      if (ticketId != null && mounted) {
                        context.go(AppRoutes.paymentFor(ticketId));
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: _Tok.badgeRed,
                          ),
                        );
                      }
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// PRIVATE WIDGETS
// ===========================================================================

// ---------------------------------------------------------------------------
// Category sidebar item
// ---------------------------------------------------------------------------

class _CategoryItem extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _CategoryItem({
    super.key,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: isActive ? _Tok.accentBlue : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? _Tok.textPrimary : _Tok.textDim,
          ),
        ),
      ),
    );
  }
}

class _CategoryDivider extends StatelessWidget {
  const _CategoryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 1,
      color: _Tok.surfaceHigh.withValues(alpha: 0.3),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar icon button
// ---------------------------------------------------------------------------

class _TopBarIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopBarIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _Tok.surfaceMedium,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: _Tok.textSecondary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Product Card with quantity badge
// ---------------------------------------------------------------------------

class _ProductCard extends StatefulWidget {
  final ProductEntity product;
  final bool showPictures;
  final bool showPrice;
  final int badgeQuantity;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.showPictures,
    required this.showPrice,
    required this.badgeQuantity,
    required this.onTap,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _isPressed = false;

  String _formatPrice(int cents) {
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    return '$whole.$frac';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Card body
            widget.showPictures ? _buildImageCard(p) : _buildTextCard(p),

            // Quantity badge
            if (widget.badgeQuantity > 0)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: _Tok.badgeRed,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${widget.badgeQuantity}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageCard(ProductEntity p) {
    final hasImage = p.imagePath != null && p.imagePath!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: _Tok.surfaceMedium,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image area
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: hasImage
                  ? Image.network(
                      p.imagePath!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(p),
                    )
                  : _buildPlaceholder(p),
            ),
          ),
          // Name + price
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _Tok.textPrimary,
                    height: 1.3,
                  ),
                ),
                if (widget.showPrice) ...[
                  const SizedBox(height: 4),
                  Text(
                    _formatPrice(p.price),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _Tok.accentBlueLight,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextCard(ProductEntity p) {
    return Container(
      decoration: BoxDecoration(
        color: _Tok.surfaceMedium,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            p.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _Tok.textPrimary,
            ),
          ),
          if (widget.showPrice) ...[
            const SizedBox(height: 6),
            Text(
              _formatPrice(p.price),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _Tok.accentBlueLight,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlaceholder(ProductEntity p) {
    return ColoredBox(
      color: _Tok.surfaceHigh,
      child: Center(
        child: Icon(
          Icons.restaurant,
          size: 28,
          color: _Tok.textDim.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Order panel tab button
// ---------------------------------------------------------------------------

class _OrderTab extends StatelessWidget {
  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _OrderTab({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? _Tok.accentBlue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isActive ? _Tok.textPrimary : _Tok.textDim,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isActive
                      ? _Tok.accentBlue.withValues(alpha: 0.2)
                      : _Tok.surfaceHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isActive ? _Tok.accentBlue : _Tok.textDim,
                  ),
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
// Order item row
// ---------------------------------------------------------------------------

class _OrderItemRow extends StatelessWidget {
  final OrderItemEntity item;
  final bool isEditable;
  final String Function(int) formatCHF;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback? onDismissed;

  /// Gang name to show as a badge (e.g. "Vorspeise"). Null = no badge.
  final String? gangLabel;

  /// Color for the Gang badge border and text.
  final Color? gangColor;

  const _OrderItemRow({
    required this.item,
    required this.isEditable,
    required this.formatCHF,
    this.onIncrement,
    this.onDecrement,
    this.onDismissed,
    this.gangLabel,
    this.gangColor,
  });

  String _modifierSummary() {
    if (item.modifiers.isEmpty) return '';
    final parts = <String>[];
    for (final m in item.modifiers) {
      if (m.priceDelta > 0) {
        final whole = m.priceDelta ~/ 100;
        final frac = (m.priceDelta % 100).toString().padLeft(2, '0');
        parts.add('${m.modifierName} (CHF $whole.$frac)');
      } else {
        parts.add(m.modifierName);
      }
    }
    return parts.join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quantity
          SizedBox(
            width: 28,
            child: Text(
              '${item.quantity.toInt()}x',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _Tok.accentBlue,
              ),
            ),
          ),

          // Name + modifiers
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _Tok.textPrimary,
                        ),
                      ),
                    ),
                    // Gang badge — small colored pill showing Gang name
                    if (gangLabel != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: (gangColor ?? _Tok.accentBlue)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: (gangColor ?? _Tok.accentBlue)
                                .withValues(alpha: 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          gangLabel!,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: gangColor ?? _Tok.accentBlue,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (item.modifiers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _modifierSummary(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _Tok.textDim,
                      ),
                    ),
                  ),
                if (item.notes != null && item.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.notes!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: _Tok.textDim,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Price
          Text(
            formatCHF(item.subtotal),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _Tok.textPrimary,
            ),
          ),

          // Qty controls (only in ordering tab)
          if (isEditable) ...[
            const SizedBox(width: 8),
            Column(
              children: [
                _QtyButton(
                  icon: Icons.add,
                  onTap: onIncrement,
                ),
                const SizedBox(height: 2),
                _QtyButton(
                  icon: Icons.remove,
                  onTap: onDecrement,
                ),
              ],
            ),
          ],
        ],
      ),
    );

    // Swipe to delete only on ordering tab
    if (isEditable && onDismissed != null) {
      return Dismissible(
        key: ValueKey(item.id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDismissed!(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: _Tok.badgeRed.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.delete_outline,
              color: _Tok.badgeRed, size: 20),
        ),
        child: content,
      );
    }

    return content;
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _QtyButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: _Tok.surfaceMedium,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: _Tok.textSecondary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gradient action button
// ---------------------------------------------------------------------------

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final bool isSecondary;
  final VoidCallback? onTap;

  const _GradientButton({
    super.key,
    required this.label,
    required this.icon,
    required this.enabled,
    this.isSecondary = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPrimary = !isSecondary;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: enabled && isPrimary
              ? const LinearGradient(
                  colors: [_Tok.accentBlueLight, _Tok.accentBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: enabled
              ? (isPrimary ? null : _Tok.surfaceHigh)
              : _Tok.surfaceMedium,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: enabled
                    ? (isPrimary ? const Color(0xFF001944) : _Tok.accentBlueLight)
                    : _Tok.textDim,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              icon,
              size: 18,
              color: enabled
                  ? (isPrimary ? const Color(0xFF001944) : _Tok.accentBlueLight)
                  : _Tok.textDim,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Order Type Chip (Dine-In / Takeaway / Delivery)
// ---------------------------------------------------------------------------

class _OrderTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _OrderTypeChip({
    super.key,
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? _Tok.accentBlue.withValues(alpha: 0.15) : _Tok.surfaceHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? _Tok.accentBlue : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isActive ? _Tok.accentBlue : _Tok.textDim),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? _Tok.accentBlue : _Tok.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
