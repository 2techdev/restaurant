/// Kiosk cart review screen.
///
/// Shows all items in the current session cart with the ability to
/// edit quantities or remove items. Displays:
///   - Dine-in / Takeaway toggle (affects Swiss VAT)
///   - Subtotal (gross, tax-inclusive)
///   - Extracted MwSt (informational)
///   - 5-Rappen rounded total (for cash)
///   - Proceed to payment CTA
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/utils/money.dart';
import 'package:gastrocore_pos/features/kiosk/domain/kiosk_cart_item.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/providers/kiosk_provider.dart';
import 'package:gastrocore_pos/features/kiosk/router/kiosk_router.dart';
import 'package:gastrocore_pos/features/kiosk/services/kiosk_order_service.dart';
import 'package:gastrocore_pos/features/kiosk/theme/kiosk_theme.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_welcome_screen.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_language_screen.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';

class KioskCartScreen extends ConsumerWidget {
  const KioskCartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(kioskSessionProvider);
    final items = session.items;
    final orderType = session.orderType;

    if (items.isEmpty) {
      return Scaffold(
        backgroundColor: KioskColors.bgPage,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.shopping_cart_outlined,
                  size: 96,
                  color: KioskColors.textDim,
                ),
                const SizedBox(height: 24),
                Text(
                  'Your cart is empty',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => context.go(KioskRoutes.menu),
                  child: const Text('Browse Menu'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Compute totals
    final subtotal = session.subtotal;
    final taxAmount = _computeTax(items, orderType);
    final roundedTotal = KioskOrderService.roundToFiveRappen(subtotal);
    final roundingAdjustment = roundedTotal - subtotal;

    return Scaffold(
      backgroundColor: KioskColors.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ────────────────────────────────────────────────────
            _CartTopBar(
              itemCount: session.itemCount,
              onBack: () => context.go(KioskRoutes.menu),
            ),

            // ── Body: item list + order type + totals ──────────────────────
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: cart items
                  Expanded(
                    flex: 3,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _CartItemRow(item: items[i]),
                    ),
                  ),

                  // Divider
                  Container(width: 1, color: KioskColors.border),

                  // Right: order type + totals + CTA
                  SizedBox(
                    width: 360,
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Dine-in / takeaway toggle ──────────────
                                _OrderTypeToggle(
                                  orderType: orderType,
                                  onChanged: (type) {
                                    ref
                                        .read(kioskSessionProvider.notifier)
                                        .setOrderType(type);
                                  },
                                ),
                                const SizedBox(height: 28),

                                // ── Totals ─────────────────────────────────
                                _TotalsSection(
                                  subtotal: subtotal,
                                  taxAmount: taxAmount,
                                  roundingAdjustment: roundingAdjustment,
                                  roundedTotal: roundedTotal,
                                ),
                                const SizedBox(height: 28),

                                // ── Checkout button ────────────────────────
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () =>
                                        context.go(KioskRoutes.payment),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 20,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.arrow_forward_rounded,
                                            size: 22),
                                        SizedBox(width: 10),
                                        Text(
                                          'Proceed to Payment',
                                          style: TextStyle(fontSize: 18),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        context.go(KioskRoutes.menu),
                                    child: const Text('Add More Items'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Step indicator ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: const KioskStepIndicator(currentStep: 2),
            ),
          ],
        ),
      ),
    );
  }

  int _computeTax(List<KioskCartItem> items, OrderType orderType) {
    return items.fold<int>(0, (sum, item) {
      return sum +
          KioskOrderService.taxRate(item.product.taxGroup, orderType)
              .let((rate) => (item.subtotal * rate / (100 + rate)).round());
    });
  }
}

extension _NumLet<T> on T {
  R let<R>(R Function(T) block) => block(this);
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _CartTopBar extends StatelessWidget {
  final int itemCount;
  final VoidCallback onBack;

  const _CartTopBar({required this.itemCount, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: KioskColors.bgCard,
        border: Border(bottom: BorderSide(color: KioskColors.border)),
      ),
      child: Row(
        children: [
          KioskBackButton(onTap: onBack),
          const SizedBox(width: 20),
          Text(
            'Your Order',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: KioskColors.primaryContainer,
              borderRadius: BorderRadius.circular(kKioskRadiusSmall),
            ),
            child: Text(
              '$itemCount item${itemCount == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: KioskColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cart item row
// ---------------------------------------------------------------------------

class _CartItemRow extends ConsumerWidget {
  final KioskCartItem item;
  const _CartItemRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(kioskSessionProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KioskColors.bgCard,
        borderRadius: BorderRadius.circular(kKioskRadiusMedium),
        border: Border.all(color: KioskColors.border),
      ),
      child: Row(
        children: [
          // Product name + modifiers
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: KioskColors.textPrimary,
                  ),
                ),
                if (item.modifiers.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.modifiers.map((m) => m.modifierName).join(', '),
                    style: const TextStyle(
                      fontSize: 13,
                      color: KioskColors.textSecondary,
                    ),
                  ),
                ],
                if (item.notes != null && item.notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.notes!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: KioskColors.textDim,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Quantity stepper
          _InlineQuantityStepper(
            quantity: item.quantity,
            onDecrement: () {
              if (item.quantity <= 1) {
                notifier.removeItem(item.id);
              } else {
                notifier.setQuantity(item.id, item.quantity - 1);
              }
            },
            onIncrement: () =>
                notifier.setQuantity(item.id, item.quantity + 1),
          ),

          const SizedBox(width: 16),

          // Subtotal
          SizedBox(
            width: 90,
            child: Text(
              Money(item.subtotal).format('CHF'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KioskColors.textPrimary,
              ),
              textAlign: TextAlign.right,
            ),
          ),

          // Remove button
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => notifier.removeItem(item.id),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: KioskColors.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: KioskColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineQuantityStepper extends StatelessWidget {
  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _InlineQuantityStepper({
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SmallStepBtn(icon: Icons.remove, onTap: onDecrement),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '$quantity',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KioskColors.textPrimary,
            ),
          ),
        ),
        _SmallStepBtn(icon: Icons.add, onTap: onIncrement),
      ],
    );
  }
}

class _SmallStepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SmallStepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: KioskColors.bgCardAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KioskColors.border),
        ),
        child: Icon(icon, size: 18, color: KioskColors.textPrimary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Order type toggle
// ---------------------------------------------------------------------------

class _OrderTypeToggle extends StatelessWidget {
  final OrderType orderType;
  final ValueChanged<OrderType> onChanged;

  const _OrderTypeToggle({
    required this.orderType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How would you like to eat?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: KioskColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TypeButton(
                label: 'Dine In',
                icon: Icons.restaurant_rounded,
                color: KioskColors.dineIn,
                isSelected: orderType == OrderType.dineIn,
                onTap: () => onChanged(OrderType.dineIn),
                subtitle: '8.1% VAT',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TypeButton(
                label: 'Takeaway',
                icon: Icons.takeout_dining_rounded,
                color: KioskColors.takeaway,
                isSelected: orderType == OrderType.takeaway,
                onTap: () => onChanged(OrderType.takeaway),
                subtitle: '2.6% VAT (food)',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TypeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final String subtitle;

  const _TypeButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : KioskColors.bgCardAlt,
          borderRadius: BorderRadius.circular(kKioskRadiusMedium),
          border: Border.all(
            color: isSelected ? color : KioskColors.border,
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? color : KioskColors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isSelected ? color : KioskColors.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: KioskColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Totals section
// ---------------------------------------------------------------------------

class _TotalsSection extends StatelessWidget {
  final int subtotal;
  final int taxAmount;
  final int roundingAdjustment;
  final int roundedTotal;

  const _TotalsSection({
    required this.subtotal,
    required this.taxAmount,
    required this.roundingAdjustment,
    required this.roundedTotal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KioskColors.bgCardAlt,
        borderRadius: BorderRadius.circular(kKioskRadiusMedium),
        border: Border.all(color: KioskColors.border),
      ),
      child: Column(
        children: [
          _TotalRow(
            label: 'Subtotal (incl. tax)',
            amount: Money(subtotal).format('CHF'),
            isLight: true,
          ),
          const SizedBox(height: 8),
          _TotalRow(
            label: 'incl. MwSt',
            amount: Money(taxAmount).format('CHF'),
            isLight: true,
            isSmall: true,
          ),
          if (roundingAdjustment != 0) ...[
            const SizedBox(height: 8),
            _TotalRow(
              label: '5-Rappen rounding',
              amount: (roundingAdjustment >= 0 ? '+' : '') +
                  Money(roundingAdjustment).format('CHF'),
              isLight: true,
              isSmall: true,
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              height: 1,
              color: KioskColors.border,
            ),
          ),
          _TotalRow(
            label: 'Total',
            amount: Money(roundedTotal).format('CHF'),
            isBold: true,
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String amount;
  final bool isLight;
  final bool isSmall;
  final bool isBold;

  const _TotalRow({
    required this.label,
    required this.amount,
    this.isLight = false,
    this.isSmall = false,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isLight ? KioskColors.textSecondary : KioskColors.textPrimary;
    final fontSize = isBold ? 20.0 : (isSmall ? 13.0 : 15.0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            color: color,
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: isBold ? KioskColors.primary : color,
          ),
        ),
      ],
    );
  }
}
