/// Checkout screen — order summary, optional customer name, confirm order.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
        title: Text(l10n.orderSummary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: isLoading
              ? null
              : () => context.go('/${widget.restaurantId}/cart'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order type chip
            _OrderTypeBadge(cart: cart),
            const SizedBox(height: 16),

            // Items summary
            _ItemsSummaryCard(cart: cart),
            const SizedBox(height: 16),

            // Customer name
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: OnlineColors.bgCard,
                borderRadius: BorderRadius.circular(kRadiusMedium),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.yourName,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: l10n.yourNameHint,
                      prefixIcon: const Icon(Icons.person_outline,
                          color: OnlineColors.textDim),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Totals
            _CheckoutTotals(cart: cart),
          ],
        ),
      ),

      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: ElevatedButton(
            onPressed:
                isLoading ? null : () => _placeOrder(cart),
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
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: OnlineColors.primaryLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDineIn ? Icons.table_restaurant : Icons.shopping_bag_outlined,
                size: 16,
                color: OnlineColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                isDineIn ? l10n.dineIn : l10n.takeaway,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: OnlineColors.primary,
                ),
              ),
              if (isDineIn && cart.tableNumber != null) ...[
                const SizedBox(width: 6),
                Text(
                  '· ${l10n.tableNumber} ${cart.tableNumber}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: OnlineColors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OnlineColors.bgCard,
        borderRadius: BorderRadius.circular(kRadiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.orderSummary,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          ...cart.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
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
                        style: const TextStyle(
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
                          Text(item.product.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500)),
                          if (item.selectedModifiers.isNotEmpty)
                            Text(
                              item.selectedModifiers
                                  .map((m) => m.name)
                                  .join(', '),
                              style: const TextStyle(
                                fontSize: 12,
                                color: OnlineColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      Money(item.lineTotal).format('CHF'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
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
    final vatRate = cart.vatRate;
    final vatLabel = vatRate == SwissVat.standard ? '8.1' : '2.6';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OnlineColors.bgCard,
        borderRadius: BorderRadius.circular(kRadiusMedium),
      ),
      child: Column(
        children: [
          _row(l10n.subtotal, cart.subtotalCents),
          _row('${l10n.vat} ($vatLabel%)', cart.vatCents, dim: true),
          if (cart.roundingCents != 0)
            _row(l10n.rounding, cart.roundingCents, dim: true),
          const Divider(height: 20),
          _row(l10n.total, cart.totalRounded, isTotal: true),
        ],
      ),
    );
  }

  Widget _row(String label, int cents,
      {bool isTotal = false, bool dim = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                fontSize: isTotal ? 16 : 14,
                fontWeight: isTotal ? FontWeight.w700 : FontWeight.w400,
                color: dim
                    ? OnlineColors.textSecondary
                    : OnlineColors.textPrimary,
              )),
          const Spacer(),
          Text(
            Money(cents.abs()).format('CHF'),
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w400,
              color: isTotal ? OnlineColors.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}
