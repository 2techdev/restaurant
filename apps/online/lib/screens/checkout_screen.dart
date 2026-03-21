/// Checkout screen — order summary, optional customer name, payment method, confirm.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gastrocore_online/core/theme/app_theme.dart';
import 'package:gastrocore_online/core/utils/money.dart';
import 'package:gastrocore_online/domain/cart.dart';
import 'package:gastrocore_online/domain/models/order_models.dart';
import 'package:gastrocore_online/l10n/app_localizations.dart';
import 'package:gastrocore_online/providers/cart_provider.dart';
import 'package:gastrocore_online/providers/order_provider.dart';

// ---------------------------------------------------------------------------
// Payment method
// ---------------------------------------------------------------------------

enum _PaymentMethod { payOnPickup, payOnline }

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.restaurantId});
  final String restaurantId;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _nameController = TextEditingController();
  _PaymentMethod _paymentMethod = _PaymentMethod.payOnPickup;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder(Cart cart) async {
    final l10n = AppLocalizations.of(context)!;

    // 1) Place the order
    final order = await ref.read(placeOrderProvider.notifier).placeOrder(
          restaurantId: widget.restaurantId,
          cart: cart,
          customerName: _nameController.text.trim().isEmpty
              ? null
              : _nameController.text.trim(),
        );

    if (!mounted) return;

    if (order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.orderFailed),
          backgroundColor: OnlineColors.red,
        ),
      );
      return;
    }

    // 2) If paying online → create Stripe checkout session
    if (_paymentMethod == _PaymentMethod.payOnline) {
      await _redirectToStripe(order, cart);
    } else {
      // Pay on pickup → go directly to confirmation
      ref.read(cartProvider.notifier).clear();
      if (mounted) {
        context.go(
          '/${widget.restaurantId}/confirmation/${order.id}'
          '?number=${order.orderNumber}',
        );
      }
    }
  }

  Future<void> _redirectToStripe(PlacedOrder order, Cart cart) async {
    final result =
        await ref.read(createPaymentCheckoutProvider.notifier).createCheckout(
              orderId: order.id,
              restaurantId: widget.restaurantId,
              amountCents: cart.totalRounded,
              currency: 'chf',
              description: 'Order #${order.orderNumber}',
            );

    if (!mounted) return;

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment setup failed. Please try Pay on Pickup.'),
          backgroundColor: OnlineColors.red,
        ),
      );
      return;
    }

    // Open Stripe Checkout in browser
    final uri = Uri.parse(result.checkoutUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      // After returning from browser, clear cart and show confirmation
      ref.read(cartProvider.notifier).clear();
      if (mounted) {
        context.go(
          '/${widget.restaurantId}/confirmation/${order.id}'
          '?number=${order.orderNumber}&payment=stripe',
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open payment page. Please try again.'),
            backgroundColor: OnlineColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cart = ref.watch(cartProvider);
    final orderState = ref.watch(placeOrderProvider);
    final checkoutState = ref.watch(createPaymentCheckoutProvider);
    final isLoading = orderState is AsyncLoading || checkoutState is AsyncLoading;

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

            // Payment method
            _PaymentMethodSelector(
              selected: _paymentMethod,
              onChanged: (m) => setState(() => _paymentMethod = m),
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
            onPressed: isLoading ? null : () => _placeOrder(cart),
            style: ElevatedButton.styleFrom(
              backgroundColor: _paymentMethod == _PaymentMethod.payOnline
                  ? const Color(0xFF6772E5) // Stripe purple
                  : OnlineColors.primary,
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_paymentMethod == _PaymentMethod.payOnline)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.lock_rounded,
                              size: 16, color: Colors.white),
                        ),
                      Text(
                        _paymentMethod == _PaymentMethod.payOnline
                            ? 'Pay Securely Online'
                            : l10n.confirmOrder,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment method selector
// ---------------------------------------------------------------------------

class _PaymentMethodSelector extends StatelessWidget {
  const _PaymentMethodSelector({
    required this.selected,
    required this.onChanged,
  });

  final _PaymentMethod selected;
  final ValueChanged<_PaymentMethod> onChanged;

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
            'Payment Method',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          _PaymentOption(
            icon: Icons.store_rounded,
            title: 'Pay on Pickup / At Table',
            subtitle: 'Pay with cash or card when you receive your order',
            isSelected: selected == _PaymentMethod.payOnPickup,
            onTap: () => onChanged(_PaymentMethod.payOnPickup),
          ),
          const SizedBox(height: 8),
          _PaymentOption(
            icon: Icons.credit_card_rounded,
            title: 'Pay Online (Card)',
            subtitle: 'Secure payment via Stripe — Visa, Mastercard, AMEX',
            isSelected: selected == _PaymentMethod.payOnline,
            onTap: () => onChanged(_PaymentMethod.payOnline),
            badge: 'Stripe',
          ),
        ],
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? OnlineColors.primaryLight
              : OnlineColors.bgPage,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? OnlineColors.primary
                : OnlineColors.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected
                  ? OnlineColors.primary
                  : OnlineColors.textDim,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? OnlineColors.primary
                              : OnlineColors.textPrimary,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6772E5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? OnlineColors.primary.withValues(alpha: 0.7)
                          : OnlineColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: isSelected ? OnlineColors.primary : OnlineColors.textDim,
            ),
          ],
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
