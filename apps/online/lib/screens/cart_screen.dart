/// Cart screen — items list, order type toggle, table number, totals.
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

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key, required this.restaurantId});
  final String restaurantId;

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _tableController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cart = ref.read(cartProvider);
      if (cart.tableNumber != null) {
        _tableController.text = '${cart.tableNumber}';
      }
      if (cart.notes != null) {
        _notesController.text = cart.notes!;
      }
    });
  }

  @override
  void dispose() {
    _tableController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cart = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: OnlineColors.bgPage,
      appBar: AppBar(
        title: Text(l10n.cart),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () =>
              context.go('/${widget.restaurantId}/menu'),
        ),
      ),
      body: cart.isEmpty
          ? _buildEmpty(context, l10n)
          : _buildCart(context, l10n, cart),
    );
  }

  Widget _buildEmpty(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shopping_cart_outlined,
              size: 72, color: OnlineColors.textDim),
          const SizedBox(height: 16),
          Text(l10n.cartEmpty,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(l10n.cartEmptyHint,
              style: const TextStyle(color: OnlineColors.textSecondary)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () =>
                context.go('/${widget.restaurantId}/menu'),
            icon: const Icon(Icons.restaurant_menu),
            label: Text(l10n.browseMenu),
          ),
        ],
      ),
    );
  }

  Widget _buildCart(
    BuildContext context,
    AppLocalizations l10n,
    Cart cart,
  ) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            children: [
              // Cart items
              ...cart.items.map((item) => _CartItemTile(
                    item: item,
                    onRemove: () => ref
                        .read(cartProvider.notifier)
                        .removeItem(item.id),
                    onQuantityChanged: (q) => ref
                        .read(cartProvider.notifier)
                        .updateQuantity(item.id, q),
                  )),

              const SizedBox(height: 16),

              // Order type
              _SectionCard(
                title: l10n.orderType,
                child: _OrderTypeToggle(
                  selected: cart.orderType,
                  onChanged: (type) => ref
                      .read(cartProvider.notifier)
                      .setOrderType(type),
                ),
              ),

              // Table number (dine-in only)
              if (cart.orderType == OrderType.dineIn) ...[
                const SizedBox(height: 12),
                _SectionCard(
                  title: l10n.tableNumber,
                  child: TextField(
                    controller: _tableController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: l10n.tableNumberHint,
                      prefixIcon: const Icon(
                          Icons.table_restaurant,
                          color: OnlineColors.textDim),
                    ),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      ref
                          .read(cartProvider.notifier)
                          .setTableNumber(n);
                    },
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Notes
              _SectionCard(
                title: l10n.orderNotes,
                child: TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: l10n.orderNotesHint,
                  ),
                  onChanged: (v) =>
                      ref.read(cartProvider.notifier).setNotes(v),
                ),
              ),

              const SizedBox(height: 16),

              // Totals
              _TotalsCard(cart: cart),
              const SizedBox(height: 100),
            ],
          ),
        ),

        // CTA bar
        _CheckoutBar(
          cart: cart,
          restaurantId: widget.restaurantId,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cart item tile
// ---------------------------------------------------------------------------

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    required this.item,
    required this.onRemove,
    required this.onQuantityChanged,
  });

  final CartItem item;
  final VoidCallback onRemove;
  final void Function(int) onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OnlineColors.bgCard,
        borderRadius: BorderRadius.circular(kRadiusMedium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 60,
              height: 60,
              child: item.product.imageUrl != null
                  ? Image.network(item.product.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _placeholder())
                  : _placeholder(),
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (item.selectedModifiers.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.selectedModifiers.map((m) => m.name).join(', '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (item.notes != null && item.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.notes!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                            color: OnlineColors.textDim,
                            fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      Money(item.lineTotal).format('CHF'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: OnlineColors.primary,
                      ),
                    ),
                    const Spacer(),
                    // Quantity stepper
                    _MiniStepper(
                      quantity: item.quantity,
                      onDecrement: () =>
                          onQuantityChanged(item.quantity - 1),
                      onIncrement: () =>
                          onQuantityChanged(item.quantity + 1),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Remove
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline,
                size: 20, color: OnlineColors.textDim),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        color: OnlineColors.primaryLight,
        child: const Center(
          child: Icon(Icons.restaurant,
              size: 24, color: OnlineColors.primary),
        ),
      );
}

class _MiniStepper extends StatelessWidget {
  const _MiniStepper({
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MiniBtn(icon: Icons.remove, onTap: onDecrement),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('$quantity',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        _MiniBtn(icon: Icons.add, onTap: onIncrement),
      ],
    );
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: OnlineColors.chipBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Order type toggle
// ---------------------------------------------------------------------------

class _OrderTypeToggle extends StatelessWidget {
  const _OrderTypeToggle({this.selected, required this.onChanged});
  final OrderType? selected;
  final void Function(OrderType) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: _TypeButton(
            icon: Icons.table_restaurant,
            label: l10n.dineIn,
            selected: selected == OrderType.dineIn,
            onTap: () => onChanged(OrderType.dineIn),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TypeButton(
            icon: Icons.shopping_bag_outlined,
            label: l10n.takeaway,
            selected: selected == OrderType.takeaway,
            onTap: () => onChanged(OrderType.takeaway),
          ),
        ),
      ],
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? OnlineColors.primaryLight
              : OnlineColors.bgPage,
          borderRadius: BorderRadius.circular(kRadiusMedium),
          border: Border.all(
            color: selected
                ? OnlineColors.primary
                : OnlineColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: selected
                    ? OnlineColors.primary
                    : OnlineColors.textSecondary),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? OnlineColors.primary
                    : OnlineColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section card
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

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
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Totals card
// ---------------------------------------------------------------------------

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.cart});
  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vatRate = cart.vatRate;
    final vatLabel =
        '${vatRate == SwissVat.standard ? '8.1' : '2.6'}%';

    Widget row(String label, int cents,
        {bool isTotal = false, bool isDim = false}) {
      final amount = Money(cents.abs()).format('CHF');
      final isNeg = cents < 0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: isTotal ? 16 : 14,
                fontWeight:
                    isTotal ? FontWeight.w700 : FontWeight.w400,
                color: isDim
                    ? OnlineColors.textSecondary
                    : OnlineColors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '${isNeg ? '-' : ''}$amount',
              style: TextStyle(
                fontSize: isTotal ? 16 : 14,
                fontWeight:
                    isTotal ? FontWeight.w700 : FontWeight.w400,
                color: isTotal
                    ? OnlineColors.primary
                    : (isDim
                        ? OnlineColors.textSecondary
                        : OnlineColors.textPrimary),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OnlineColors.bgCard,
        borderRadius: BorderRadius.circular(kRadiusMedium),
      ),
      child: Column(
        children: [
          row(l10n.subtotal, cart.subtotalCents),
          row(
            '${l10n.vat} ($vatLabel)',
            cart.vatCents,
            isDim: true,
          ),
          if (cart.roundingCents != 0) ...[
            row(l10n.rounding, cart.roundingCents, isDim: true),
          ],
          const Divider(height: 20),
          row(l10n.total, cart.totalRounded, isTotal: true),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Checkout CTA bar
// ---------------------------------------------------------------------------

class _CheckoutBar extends ConsumerWidget {
  const _CheckoutBar({
    required this.cart,
    required this.restaurantId,
  });

  final Cart cart;
  final String restaurantId;

  bool get _canCheckout {
    if (cart.isEmpty) return false;
    if (cart.orderType == null) return false;
    if (cart.orderType == OrderType.dineIn &&
        cart.tableNumber == null) return false;
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 16 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: OnlineColors.bgCard,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _canCheckout
            ? () => context.go('/$restaurantId/checkout')
            : null,
        child: Text(l10n.continueToCheckout),
      ),
    );
  }
}
