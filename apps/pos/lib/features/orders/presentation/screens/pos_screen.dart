/// Main POS Screen for GastroCore POS.
///
/// Three-column layout: category sidebar, product grid, and order panel.
/// Follows the Stitch "Precision POS Framework" design system
/// (s03_main_pos reference).
///
/// Wired to real Riverpod providers for categories, products, and tickets.
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
import 'package:gastrocore_pos/features/orders/presentation/widgets/discount_dialog.dart';

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
    // Ensure a draft ticket exists when entering the POS screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureTicket();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Create a draft ticket if none is currently active.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          // -- Top bar --
          _buildTopBar(),
          // -- Main 3-col layout --
          Expanded(
            child: Row(
              children: [
                // LEFT: Category sidebar
                _buildCategorySidebar(),
                // CENTER: Product grid
                Expanded(child: _buildProductArea()),
                // RIGHT: Order panel
                _buildOrderPanel(),
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

  Widget _buildTopBar() {
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'Unknown';
    final initials = _initials(userName);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: AppColors.surface,
      child: Row(
        children: [
          // Logo
          Row(
            children: [
              const Text(
                'Gastro',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryContainer],
                ).createShader(bounds),
                child: const Text(
                  'Core',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),

          // Online badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.greenDim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'ONLINE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Info text
          const Text(
            'Terminal 01  \u2022  Main Floor  \u2022  Lunch',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textDim,
            ),
          ),
          const Spacer(),

          // User avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.15),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            userName,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  // -------------------------------------------------------------------------
  // Category sidebar
  // -------------------------------------------------------------------------

  Widget _buildCategorySidebar() {
    final categoriesAsync = ref.watch(categoriesProvider);
    final selectedId = ref.watch(selectedCategoryProvider);

    return Container(
      width: 80,
      color: AppColors.surface,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: categoriesAsync.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                ),
              ),
              error: (_, __) => const Center(
                child: Icon(Icons.error_outline,
                    size: 24, color: AppColors.textDim),
              ),
              data: (categories) {
                // Prepend an "All" option
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: categories.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // "All" category
                      final isActive = selectedId == null;
                      return _buildCategoryTile(
                        icon: '\u2B50',
                        name: 'Tumu',
                        isActive: isActive,
                        onTap: () => ref
                            .read(selectedCategoryProvider.notifier)
                            .state = null,
                      );
                    }

                    final cat = categories[index - 1];
                    final isActive = cat.id == selectedId;
                    return _buildCategoryTile(
                      icon: cat.icon,
                      name: cat.name,
                      isActive: isActive,
                      onTap: () => ref
                          .read(selectedCategoryProvider.notifier)
                          .state = cat.id,
                    );
                  },
                );
              },
            ),
          ),

          // -- Bottom: Floor Plan & Settings shortcuts --
          const Divider(
            color: AppColors.surfaceContainerHigh,
            height: 1,
            indent: 12,
            endIndent: 12,
          ),
          _buildSidebarAction(Icons.grid_view_rounded, 'Masalar', () {
            context.go('/tables');
          }),
          _buildSidebarAction(Icons.kitchen_rounded, 'Mutfak', () {
            context.go('/kitchen');
          }),
          _buildSidebarAction(Icons.logout_rounded, 'Kapat', () {
            context.go('/shift-close');
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCategoryTile({
    required String icon,
    required String name,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accentDim : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              icon,
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? AppColors.accent : AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          children: [
            Icon(icon, size: 20, color: AppColors.textDim),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Product area (center)
  // -------------------------------------------------------------------------

  Widget _buildProductArea() {
    final productsAsync = ref.watch(filteredProductsProvider);

    return ColoredBox(
      color: AppColors.surfaceDim,
      child: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AppColors.textDim,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => ref
                          .read(productSearchProvider.notifier)
                          .state = v,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Urun ara...',
                        hintStyle: TextStyle(
                          fontSize: 14,
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

          // Product grid
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (err, _) => Center(
                child: Text(
                  'Error: $err',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textDim),
                ),
              ),
              data: (products) {
                if (products.isEmpty) {
                  return const Center(
                    child: Text(
                      'Urun bulunamadi',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textDim,
                      ),
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return _ProductCard(
                      product: product,
                      onTap: () => _addProduct(product),
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

  void _addProduct(ProductEntity product) {
    ref.read(currentTicketProvider.notifier).addItem(product);
  }

  // -------------------------------------------------------------------------
  // Order panel (right)
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
      color: AppColors.surface,
      child: Column(
        children: [
          // -- Header --
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
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
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${items.length} items',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDim,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: hasItems
                      ? () {
                          // Clear all items from ticket.
                          for (final item in List.of(items)) {
                            ref
                                .read(currentTicketProvider.notifier)
                                .removeItem(item.id);
                          }
                        }
                      : null,
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: hasItems ? AppColors.textDim : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),

          // Thin separator via color shift
          Container(height: 1, color: AppColors.surfaceContainerLow),

          // -- Dine-in / Takeaway toggle (Swiss MWST) --
          _buildServiceTypeToggle(isDineIn),

          // -- Item list --
          Expanded(
            child: !hasItems
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 40,
                          color: AppColors.surfaceContainerHigh,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Siparis bos',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textDim,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Urun eklemek icin tiklayiniz',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: items.length,
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
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.delete_rounded,
                            color: AppColors.red,
                            size: 20,
                          ),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              // Qty controls
                              GestureDetector(
                                onTap: () {
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
                                },
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.remove,
                                    size: 14,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${item.quantity.toInt()}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                  fontFeatures: [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  ref
                                      .read(currentTicketProvider.notifier)
                                      .updateItemQuantity(
                                          item.id, item.quantity + 1);
                                },
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    size: 14,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Name + modifiers
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.productName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textPrimary,
                                      ),
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
                                      ),
                                  ],
                                ),
                              ),
                              // Price
                              Text(
                                _formatPrice(item.subtotal),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                  fontFeatures: [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // -- Totals --
          Container(
            color: AppColors.surfaceContainerLow,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              children: [
                _buildTotalRow('Ara Toplam', _formatCHF(subtotal), false),
                const SizedBox(height: 4),
                // MWST breakdown: one line per rate (A=8.1%, B=2.6%, C=3.8%)
                if (fare != null)
                  ...fare.dishesTaxes.map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: _buildTotalRow(
                          'MwSt ${t.rate}%',
                          _formatCHF(t.amount),
                          false,
                        ),
                      ))
                else
                  _buildTotalRow('MwSt', _formatCHF(ticket?.taxAmount ?? 0), false),
                const SizedBox(height: 10),
                _buildTotalRow('Genel Toplam', _formatCHF(total), true),
              ],
            ),
          ),

          // -- Action buttons --
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                // Send to kitchen
                GestureDetector(
                  onTap: hasItems
                      ? () async {
                          await ref
                              .read(currentTicketProvider.notifier)
                              .sendToKitchen();
                        }
                      : null,
                  child: Container(
                    width: double.infinity,
                    height: 48,
                    decoration: BoxDecoration(
                      color: hasItems
                          ? AppColors.orange
                          : AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        'MUTFAGA GONDER',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: hasItems
                              ? const Color(0xFF1A0A00)
                              : AppColors.textDim,
                          letterSpacing: 1.0,
                        ),
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
                        onTap: hasItems
                            ? () async {
                                final ticket =
                                    ref.read(currentTicketProvider);
                                if (ticket == null) return;
                                final result =
                                    await DiscountDialog.show(
                                  context: context,
                                  ref: ref,
                                  orderTotal: ticket.total,
                                );
                                if (result != null && mounted) {
                                  final currentUser =
                                      ref.read(currentUserProvider);
                                  if (currentUser == null) return;
                                  await ref
                                      .read(currentTicketProvider
                                          .notifier)
                                      .applyDiscount(
                                        discountType:
                                            result.discountType,
                                        discountValue:
                                            result.discountValue,
                                        reason: result.reason,
                                        requestedBy: currentUser,
                                        approvedBy: result.approvedBy,
                                      );
                                }
                              }
                            : null,
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: Text(
                              'INDIRIM',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Payment
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: hasItems
                            ? () async {
                                // Save the ticket first, then navigate.
                                final saved = await ref
                                    .read(currentTicketProvider.notifier)
                                    .saveCurrentTicket();
                                if (saved != null && mounted) {
                                  context.go(
                                      AppRoutes.paymentFor(saved.id));
                                }
                              }
                            : null,
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: hasItems
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF05B046),
                                      Color(0xFF038A38),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: hasItems
                                ? null
                                : AppColors.surfaceContainerHigh,
                          ),
                          child: Center(
                            child: Text(
                              'ODEME',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: hasItems
                                    ? const Color(0xFF003A11)
                                    : AppColors.textDim,
                                letterSpacing: 1.0,
                              ),
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

  // -------------------------------------------------------------------------
  // Service type toggle (Hier essen / Zum Mitnehmen)
  // -------------------------------------------------------------------------

  /// Two-segment toggle for dine-in vs takeaway.
  ///
  /// Switching changes the MWST rate on food items (8.1% ↔ 2.6%).
  Widget _buildServiceTypeToggle(bool isDineIn) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _buildToggleSegment(
              label: 'Hier essen',
              isActive: isDineIn,
              onTap: () => ref
                  .read(currentTicketProvider.notifier)
                  .updateOrderType(OrderType.dineIn),
            ),
            _buildToggleSegment(
              label: 'Zum Mitnehmen',
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
            color: isActive ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? AppColors.textPrimary
                    : AppColors.textDim,
              ),
            ),
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
            color:
                isTotal ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 20 : 13,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
            color: isTotal ? AppColors.accent : AppColors.textPrimary,
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
  final ProductEntity product;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.onTap});

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _isPressed = false;

  String _formatPrice(int cents) {
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    return 'CHF $whole.$frac';
  }

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
        constraints: const BoxConstraints(minHeight: 88),
        decoration: BoxDecoration(
          color: _isPressed
              ? AppColors.surfaceBright
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(14),
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
                    size: 28,
                    color: AppColors.surfaceContainerHighest,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
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
            const SizedBox(height: 2),
            // Description
            if (widget.product.description != null)
              Text(
                widget.product.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textDim,
                ),
              ),
            const SizedBox(height: 6),
            // Price
            Text(
              _formatPrice(widget.product.price),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
