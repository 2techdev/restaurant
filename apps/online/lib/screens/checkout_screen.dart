/// Checkout screen — order summary, optional customer name, confirm order.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gastrocore_online/core/theme/app_theme.dart';
import 'package:gastrocore_online/core/utils/money.dart';
import 'package:gastrocore_online/domain/cart.dart';
import 'package:gastrocore_online/domain/models/order_models.dart';
import 'package:gastrocore_online/l10n/app_localizations.dart';
import 'package:gastrocore_online/providers/cart_provider.dart';
import 'package:gastrocore_online/providers/order_provider.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.restaurantId});
  final String restaurantId;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder(Cart cart) async {
    final l10n = AppLocalizations.of(context)!;
    final order = await ref.read(placeOrderProvider.notifier).placeOrder(
          restaurantId: widget.restaurantId,
          cart: cart,
          customerName: _nameController.text.trim().isEmpty
              ? null
              : _nameController.text.trim(),
        );

    if (!mounted) return;
    if (order != null) {
      ref.read(cartProvider.notifier).clear();
      context.go(
        '/${widget.restaurantId}/confirmation/${order.id}'
        '?number=${order.orderNumber}',
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.orderFailed),
          backgroundColor: OnlineColors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cart = ref.watch(cartProvider);
    final orderState = ref.watch(placeOrderProvider);
    final isLoading = orderState is AsyncLoading;

    return Scaffold(
      backgroundColor: OnlineColors.bgPage,
      appBar: AppBar(
        backgroundColor: OnlineColors.charcoal,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: isLoading
              ? null
              : () => context.go('/${widget.restaurantId}/cart'),
        ),
        title: Text(
          l10n.orderSummary,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order type badge
            _OrderTypeBadge(cart: cart),
            const SizedBox(height: 20),

            // Items summary
            _ItemsSummaryCard(cart: cart),
            const SizedBox(height: 16),

            // Customer name
            _FormCard(
              title: l10n.yourName,
              child: TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: l10n.yourNameHint,
                  prefixIcon: const Icon(
                    Icons.person_outline_rounded,
                    color: OnlineColors.textDim,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Totals
            _CheckoutTotals(cart: cart),
          ],
        ),
      ),

      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: OnlineColors.bgCard,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : () => _placeOrder(cart),
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Text(l10n.confirmOrder),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form card
// ---------------------------------------------------------------------------

class _FormCard extends StatelessWidget {
  const _FormCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OnlineColors.bgCard,
        borderRadius: BorderRadius.circular(kRadiusLarge),
        border: Border.all(color: OnlineColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: OnlineColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Order type badge
// ---------------------------------------------------------------------------

class _OrderTypeBadge extends StatelessWidget {
  const _OrderTypeBadge({required this.cart});
  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDineIn = cart.orderType == OrderType.dineIn;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: OnlineColors.pillActiveBg,
        borderRadius: BorderRadius.circular(kRadiusMedium),
        border: Border.all(color: OnlineColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDineIn ? Icons.table_restaurant_rounded : Icons.shopping_bag_outlined,
            size: 16,
            color: OnlineColors.primary,
          ),
          const SizedBox(width: 8),
          Text(
            isDineIn ? l10n.dineIn : l10n.takeaway,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: OnlineColors.primary,
            ),
          ),
          if (isDineIn && cart.tableNumber != null) ...[
            const SizedBox(width: 6),
            Text(
              '· Tisch ${cart.tableNumber}',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: OnlineColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Items summary
// ---------------------------------------------------------------------------

class _ItemsSummaryCard extends StatelessWidget {
  const _ItemsSummaryCard({required this.cart});
  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OnlineColors.bgCard,
        borderRadius: BorderRadius.circular(kRadiusLarge),
        border: Border.all(color: OnlineColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.orderSummary,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: OnlineColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...cart.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: OnlineColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${item.quantity}',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.product.name,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          if (item.selectedModifiers.isNotEmpty)
                            Text(
                              item.selectedModifiers
                                  .map((m) => m.name)
                                  .join(', '),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: OnlineColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      Money(item.lineTotal).format('CHF'),
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Totals
// ---------------------------------------------------------------------------

class _CheckoutTotals extends StatelessWidget {
  const _CheckoutTotals({required this.cart});
  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vatLabel = cart.vatRate == SwissVat.standard ? '8.1' : '2.6';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OnlineColors.bgCard,
        borderRadius: BorderRadius.circular(kRadiusLarge),
        border: Border.all(color: OnlineColors.divider),
      ),
      child: Column(
        children: [
          _R(l10n.subtotal, cart.subtotalCents),
          const SizedBox(height: 6),
          _R('${l10n.vat} ($vatLabel%)', cart.vatCents, dim: true),
          if (cart.roundingCents != 0) ...[
            const SizedBox(height: 6),
            _R(l10n.rounding, cart.roundingCents, dim: true),
          ],
          const SizedBox(height: 12),
          const Divider(color: OnlineColors.divider),
          const SizedBox(height: 12),
          _R(l10n.total, cart.totalRounded, isTotal: true),
        ],
      ),
    );
  }

  Widget _R(String label, int cents, {bool isTotal = false, bool dim = false}) {
    final color = dim ? OnlineColors.textSecondary : OnlineColors.textPrimary;
    final weight = isTotal ? FontWeight.w700 : FontWeight.w400;
    final size = isTotal ? 16.0 : 14.0;

    return Row(
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: size, fontWeight: weight, color: color)),
        const Spacer(),
        Text(
          Money(cents.abs()).format('CHF'),
          style: GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color),
        ),
      ],
    );
  }
}
