/// Main POS Screen — Lightspeed-inspired professional UI.
///
/// Layout (tablet landscape):
///   [GcSidebar 64px] | [Product area flex] | [Order panel 340px]
///
/// Product area:
///   Top bar (logo, status, user) → Category tabs (horizontal pills) →
///   Product grid (white cards, touch-optimised)
///
/// Order panel:
///   White card with shadow → item list with qty controls →
///   Totals (subtotal, VAT, grand total) →
///   Send to Kitchen (coral) + Pay (teal) buttons
///
/// Wired to real Riverpod providers — all state management unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/theme/app_theme.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/shared/widgets/gc_sidebar.dart';

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
      body: Row(
        children: [
          // ── Left nav sidebar (dark navy) ─────────────────────────────────
          GcSidebar(
            activeRoute: '/pos',
            userName: userName,
            userInitials: _initials(userName),
            onLogout: () => context.go('/shift-close'),
          ),

          // ── Main content ─────────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // Top bar
                _buildTopBar(userName),
                // Product area + order panel
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Product area (categories + grid)
                      Expanded(child: _buildProductArea()),
                      // Order panel
                      _buildOrderPanel(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Top bar
  // -------------------------------------------------------------------------

  Widget _buildTopBar(String userName) {
    return Container(
      height: 56,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Logo
          const Text(
            'Gastro',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const Text(
            'Core',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 16),

          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.greenDim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'ONLINE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Terminal info
          const Text(
            'Terminal 01  \u2022  Main Floor',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textDim,
            ),
          ),

          const Spacer(),

          // User
          Text(
            userName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.12),
            ),
            child: Center(
              child: Text(
                _initials(userName),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
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
        // Category pills (horizontal scrollable)
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              // Search
              Expanded(
                flex: 2,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.search_rounded,
                        size: 18,
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
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search items...',
                            hintStyle: TextStyle(
                              fontSize: 13,
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

        // Thin separator
        Container(height: 1, color: AppColors.border),

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
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.white : AppColors.textSecondary,
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
      width: 340,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: kPanelShadow,
      ),
      child: Column(
        children: [
          // ── Panel header ─────────────────────────────────────────────────
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                // Order number badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accentDim,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ticket?.orderNumber != null
                        ? '#${ticket!.orderNumber}'
                        : 'New Order',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${items.length} item${items.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDim,
                  ),
                ),
                const Spacer(),
                if (hasItems)
                  GestureDetector(
                    onTap: () {
                      for (final item in List.of(items)) {
                        ref
                            .read(currentTicketProvider.notifier)
                            .removeItem(item.id);
                      }
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.redDim,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: AppColors.red,
                      ),
                    ),
                  ),
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
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Column(
              children: [
                // Send to kitchen — coral
                GestureDetector(
                  onTap: hasItems
                      ? () async {
                          await ref
                              .read(currentTicketProvider.notifier)
                              .sendToKitchen();
                        }
                      : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: hasItems ? 1.0 : 0.45,
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: hasItems
                            ? AppColors.coral
                            : AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: hasItems
                            ? [
                                BoxShadow(
                                  color: AppColors.coral.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.restaurant_rounded,
                            size: 18,
                            color: hasItems
                                ? Colors.white
                                : AppColors.textDim,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Send to Kitchen',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: hasItems
                                  ? Colors.white
                                  : AppColors.textDim,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Discount
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          // TODO: open discount dialog
                        },
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.border),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.local_offer_outlined,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Discount',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Pay — teal gradient
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: hasItems
                            ? () async {
                                final saved = await ref
                                    .read(currentTicketProvider.notifier)
                                    .saveCurrentTicket();
                                if (saved != null && mounted) {
                                  context.go(
                                      AppRoutes.paymentFor(saved.id));
                                }
                              }
                            : null,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: hasItems ? 1.0 : 0.45,
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: hasItems
                                  ? const LinearGradient(
                                      colors: [
                                        AppColors.primary,
                                        AppColors.primaryContainer,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: hasItems
                                  ? null
                                  : AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: hasItems ? kButtonShadow : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.payment_rounded,
                                  size: 18,
                                  color: hasItems
                                      ? Colors.white
                                      : AppColors.textDim,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Pay',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: hasItems
                                        ? Colors.white
                                        : AppColors.textDim,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                if (hasItems) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatCHF(total),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white70,
                                      fontFeatures: [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(dynamic item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: kCardShadow,
      ),
      child: Row(
        children: [
          // Qty controls
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _qtyButton(
                  icon: Icons.remove,
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
                ),
                SizedBox(
                  width: 28,
                  child: Center(
                    child: Text(
                      '${item.quantity.toInt()}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                _qtyButton(
                  icon: Icons.add,
                  onTap: () => ref
                      .read(currentTicketProvider.notifier)
                      .updateItemQuantity(item.id, item.quantity + 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.modifiers.isNotEmpty)
                  Text(
                    item.modifiers
                        .map((m) => m.modifierName)
                        .join(', '),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textDim,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Price
          Text(
            _formatPrice(item.subtotal),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(icon, size: 14, color: AppColors.textSecondary),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Service type toggle
  // -------------------------------------------------------------------------

  Widget _buildServiceTypeToggle(bool isDineIn) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
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
            color: isActive ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
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
          label,
          style: TextStyle(
            fontSize: isTotal ? 14 : 12,
            fontWeight: isTotal ? FontWeight.w600 : FontWeight.w400,
            color: isTotal
                ? AppColors.textPrimary
                : AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 20 : 13,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
            color: isTotal ? AppColors.textPrimary : AppColors.textSecondary,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minHeight: 100),
        decoration: BoxDecoration(
          color: _isPressed ? AppColors.surfaceBright : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: _isPressed ? null : kCardShadow,
          border: _isPressed
              ? Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3))
              : null,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image placeholder
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(
                    Icons.restaurant_rounded,
                    size: 32,
                    color: AppColors.textDim,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Name
            Text(
              widget.product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if (widget.product.description != null) ...[
              const SizedBox(height: 2),
              Text(
                widget.product.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textDim,
                ),
              ),
            ],
            const SizedBox(height: 6),
            // Price + add button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.formatPrice(widget.product.price),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
