/// Main POS Screen — Klein Professional POS dark theme.
///
/// Layout (tablet landscape):
///   [Top bar 64px — GASTROCORE wordmark | nav tabs | user]
///   [Product area flex] | [Order panel 320px — surfaceContainerLow]
///
/// No sidebar — navigation is in the top bar tabs.
/// Organic Brutalism: no borders, tonal surface layering, tight radius.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/shared/widgets/pos_top_bar.dart';

// ---------------------------------------------------------------------------
// POS Screen
// ---------------------------------------------------------------------------

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureTicket());
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

  String _formatCHF(int cents) {
    final isNeg = cents < 0;
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return '${isNeg ? '-' : ''}CHF $whole.$frac';
  }

  String _formatPrice(int cents) {
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    return 'CHF $whole.$frac';
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'Staff';

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          // ── Top bar — GASTROCORE | ONGOING | TABLES | MENU | STAFF | user ─
          PosTopBar(
            activeTab: PosTab.ongoing,
            onTabChanged: (tab) => context.go(tab.route),
            showLogo: true,
            shiftInfo: 'AM SHIFT',
            userName: userName,
            userInitials: _initials(userName),
          ),

          // ── Content: product area + order panel ─────────────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildProductArea()),
                _buildOrderPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Product area
  // -------------------------------------------------------------------------

  Widget _buildProductArea() {
    final productsAsync = ref.watch(filteredProductsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final selectedId = ref.watch(selectedCategoryProvider);

    return Column(
      children: [
        // Search + category filter bar
        Container(
          color: AppColors.surfaceContainer,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              // Search
              Expanded(
                flex: 2,
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: AppColors.textDim,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => ref
                              .read(productSearchProvider.notifier)
                              .state = v,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search items...',
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: AppColors.textDim,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Category tabs
              Expanded(
                flex: 3,
                child: categoriesAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (categories) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // All
                        _buildCategoryPill(
                          label: 'All',
                          isActive: selectedId == null,
                          onTap: () => ref
                              .read(selectedCategoryProvider.notifier)
                              .state = null,
                        ),
                        ...categories.map((cat) => Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: _buildCategoryPill(
                                label: cat.name,
                                isActive: cat.id == selectedId,
                                onTap: () => ref
                                    .read(selectedCategoryProvider.notifier)
                                    .state = cat.id,
                              ),
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Product grid
        Expanded(
          child: productsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            error: (err, _) => Center(
              child: Text(
                'Error: $err',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textDim,
                ),
              ),
            ),
            data: (products) {
              if (products.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 48,
                        color: AppColors.textDim.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No items found',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final product = products[index];
                  return _ProductCard(
                    product: product,
                    onTap: () => _addProduct(product),
                    formatPrice: _formatPrice,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryPill({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryDim
              : AppColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isActive ? Colors.white : AppColors.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }

  void _addProduct(ProductEntity product) {
    ref.read(currentTicketProvider.notifier).addItem(product);
  }

  // -------------------------------------------------------------------------
  // Order panel
  // -------------------------------------------------------------------------

  Widget _buildOrderPanel() {
    final ticket = ref.watch(currentTicketProvider);
    final fare = ref.watch(swissTicketFareProvider);
    final items = ticket?.items ?? [];
    final subtotal = ticket?.subtotal ?? 0;
    final total = ticket?.total ?? 0;
    final hasItems = items.isNotEmpty;
    final isDineIn = ticket?.orderType != OrderType.takeaway;

    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLow,
        border: Border(
          left: BorderSide(
            color: Color(0x0DFFFFFF), // white 5% — the one allowed separator
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // ── Panel header ─────────────────────────────────────────────────
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'CURRENT BILL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 10),
                if (ticket?.orderNumber != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accentDim,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#${ticket!.orderNumber}',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  '${items.length} item${items.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textDim,
                  ),
                ),
                if (hasItems) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      for (final item in List.of(items)) {
                        ref
                            .read(currentTicketProvider.notifier)
                            .removeItem(item.id);
                      }
                    },
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 14,
                        color: AppColors.textDim,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Dine-in / Takeaway toggle ─────────────────────────────────────
          _buildServiceTypeToggle(isDineIn),

          // ── Item list ────────────────────────────────────────────────────
          Expanded(
            child: !hasItems
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.receipt_long_outlined,
                            size: 32,
                            color: AppColors.textDim,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Order is empty',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap a product to add it',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Dismissible(
                        key: ValueKey(item.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) {
                          ref
                              .read(currentTicketProvider.notifier)
                              .removeItem(item.id);
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          decoration: BoxDecoration(
                            color: AppColors.redDim,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.delete_rounded,
                            color: AppColors.red,
                            size: 20,
                          ),
                        ),
                        child: _buildOrderItem(item),
                      );
                    },
                  ),
          ),

          // ── Totals ───────────────────────────────────────────────────────
          Container(
            color: AppColors.surfaceDim,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                _buildTotalRow(
                    'Subtotal', _formatCHF(subtotal), false),
                const SizedBox(height: 6),
                if (fare != null)
                  ...fare.dishesTaxes.map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _buildTotalRow(
                          'VAT ${t.rate}%',
                          _formatCHF(t.amount),
                          false,
                        ),
                      ))
                else
                  _buildTotalRow(
                      'VAT', _formatCHF(ticket?.taxAmount ?? 0), false),
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  color: AppColors.border,
                ),
                _buildTotalRow('Total', _formatCHF(total), true),
              ],
            ),
          ),

          // ── Action buttons ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Column(
              children: [
                // Quick action grid: SEND | SPLIT | PRINT | VOID
                Row(
                  children: [
                    _buildQuickAction(
                      icon: Icons.restaurant_rounded,
                      label: 'SEND',
                      color: AppColors.secondary,
                      enabled: hasItems,
                      onTap: hasItems
                          ? () async {
                              await ref
                                  .read(currentTicketProvider.notifier)
                                  .sendToKitchen();
                            }
                          : null,
                    ),
                    const SizedBox(width: 6),
                    _buildQuickAction(
                      icon: Icons.call_split_rounded,
                      label: 'SPLIT',
                      color: AppColors.textSecondary,
                      enabled: hasItems,
                      onTap: null,
                    ),
                    const SizedBox(width: 6),
                    _buildQuickAction(
                      icon: Icons.print_outlined,
                      label: 'PRINT',
                      color: AppColors.textSecondary,
                      enabled: hasItems,
                      onTap: null,
                    ),
                    const SizedBox(width: 6),
                    _buildQuickAction(
                      icon: Icons.block_rounded,
                      label: 'VOID',
                      color: AppColors.red,
                      enabled: hasItems,
                      onTap: hasItems
                          ? () {
                              for (final item in List.of(items)) {
                                ref
                                    .read(currentTicketProvider.notifier)
                                    .removeItem(item.id);
                              }
                            }
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // CHECKOUT — full width, 64px, primaryDim bg
                GestureDetector(
                  onTap: hasItems
                      ? () async {
                          final saved = await ref
                              .read(currentTicketProvider.notifier)
                              .saveCurrentTicket();
                          if (saved != null && mounted) {
                            context.go(AppRoutes.paymentFor(saved.id));
                          }
                        }
                      : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: hasItems ? 1.0 : 0.35,
                    child: Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: hasItems
                            ? AppColors.primaryDim
                            : AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.payment_rounded,
                            size: 16,
                            color: hasItems
                                ? Colors.white
                                : AppColors.textDim,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'CHECKOUT',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: hasItems
                                  ? Colors.white
                                  : AppColors.textDim,
                              letterSpacing: 2.0,
                            ),
                          ),
                          if (hasItems) ...[
                            const SizedBox(width: 8),
                            Text(
                              _formatCHF(total),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                                fontFeatures: [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(dynamic item) {
    // Dark Klein POS order item: transparent bg, hover surfaceContainerHighest
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Row(
        children: [
          // Qty badge — "2x" font-black, primaryDim color
          GestureDetector(
            onTap: () {
              if (item.quantity > 1) {
                ref
                    .read(currentTicketProvider.notifier)
                    .updateItemQuantity(item.id, item.quantity - 1);
              } else {
                ref
                    .read(currentTicketProvider.notifier)
                    .removeItem(item.id);
              }
            },
            child: Container(
              width: 32,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  '${item.quantity.toInt()}x',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDim,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Name + modifier
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.modifiers.isNotEmpty)
                  Text(
                    '+ ${item.modifiers.map((m) => m.modifierName).join(', ')}',
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Price + add qty
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatPrice(item.subtotal),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              GestureDetector(
                onTap: () => ref
                    .read(currentTicketProvider.notifier)
                    .updateItemQuantity(item.id, item.quantity + 1),
                child: const Icon(Icons.add,
                    size: 12, color: AppColors.textDim),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1.0 : 0.3,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Service type toggle
  // -------------------------------------------------------------------------

  Widget _buildServiceTypeToggle(bool isDineIn) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            _buildToggleSegment(
              label: 'Dine In',
              icon: Icons.restaurant_rounded,
              isActive: isDineIn,
              onTap: () => ref
                  .read(currentTicketProvider.notifier)
                  .updateOrderType(OrderType.dineIn),
            ),
            _buildToggleSegment(
              label: 'Takeaway',
              icon: Icons.takeout_dining_rounded,
              isActive: !isDineIn,
              onTap: () => ref
                  .read(currentTicketProvider.notifier)
                  .updateOrderType(OrderType.takeaway),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleSegment({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primaryDim
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive ? Colors.white : AppColors.textDim,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? Colors.white : AppColors.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, String value, bool isTotal) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isTotal
                ? AppColors.primaryDim
                : AppColors.textSecondary,
            letterSpacing: 1.2,
          ),
        ),
        Text(
          isTotal
              ? value.replaceAll('CHF ', '')
              : value,
          style: TextStyle(
            fontSize: isTotal ? 28 : 12,
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.w500,
            color: isTotal
                ? AppColors.textPrimary
                : AppColors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Product card widget
// ---------------------------------------------------------------------------

class _ProductCard extends StatefulWidget {
  const _ProductCard({
    required this.product,
    required this.onTap,
    required this.formatPrice,
  });

  final ProductEntity product;
  final VoidCallback onTap;
  final String Function(int) formatPrice;

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      // Klein POS product card: dark surfaceContainerHighest bg
      // Full-image top, price badge bottom-right, tight 4px radius
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        constraints: const BoxConstraints(minHeight: 100),
        decoration: BoxDecoration(
          color: _isPressed
              ? AppColors.surfaceBright
              : AppColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image / icon area
              Container(
                color: AppColors.surfaceContainerHigh,
                child: const Center(
                  child: Icon(
                    Icons.restaurant_rounded,
                    size: 36,
                    color: AppColors.textDim,
                  ),
                ),
              ),

              // Info overlay at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                  color: AppColors.surfaceContainerHighest.withValues(alpha: 0.95),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Price badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryDim,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          widget.formatPrice(widget.product.price),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
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
