/// Cart screen — items list, order type toggle, table number, totals.
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
        backgroundColor: OnlineColors.charcoal,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.go('/${widget.restaurantId}/menu'),
        ),
        title: Text(
          l10n.cart,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        centerTitle: false,
      ),
      body: cart.isEmpty
          ? _buildEmpty(context, l10n)
          : _buildCart(context, l10n, cart),
    );
  }

  Widget _buildEmpty(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: OnlineColors.pillInactiveBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 36,
                color: OnlineColors.textDim,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.cartEmpty,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: OnlineColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.cartEmptyHint,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: OnlineColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: () => context.go('/${widget.restaurantId}/menu'),
              icon: const Icon(Icons.restaurant_menu_rounded),
              label: Text(l10n.browseMenu),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(200, 48),
              ),
            ),
          ],
        ),
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
              // Section label
              Text(
                'Ihre Bestellung',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: OnlineColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),

              // Cart items
              ...cart.items.map((item) => _CartItemTile(
                    item: item,
                    onRemove: () =>
                        ref.read(cartProvider.notifier).removeItem(item.id),
                    onQuantityChanged: (q) => ref
                        .read(cartProvider.notifier)
                        .updateQuantity(item.id, q),
                  )),

              const SizedBox(height: 20),

              // Order type
              _SectionCard(
                title: l10n.orderType,
                child: _OrderTypeToggle(
                  selected: cart.orderType,
                  onChanged: (type) =>
                      ref.read(cartProvider.notifier).setOrderType(type),
                ),
              ),

              // Table number
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
                        Icons.table_restaurant_rounded,
                        color: OnlineColors.textDim,
                        size: 20,
                      ),
                    ),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      ref.read(cartProvider.notifier).setTableNumber(n);
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

              const SizedBox(height: 12),

              // Totals
              _TotalsCard(cart: cart),
              const SizedBox(height: 100),
            ],
          ),
        ),

        // CTA bar
        _CheckoutBar(cart: cart, restaurantId: widget.restaurantId),
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
        borderRadius: BorderRadius.circular(kRadiusLarge),
        border: Border.all(color: OnlineColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image
          ClipRRect(
            borderRadius: BorderRadius.circular(kRadiusMedium),
            child: SizedBox(
              width: 64,
              height: 64,
              child: item.product.imageUrl != null
                  ? Image.network(
                      item.product.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
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
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: OnlineColors.textPrimary,
                  ),
                ),
                if (item.selectedModifiers.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.selectedModifiers.map((m) => m.name).join(', '),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: OnlineColors.textSecondary,
                    ),
                  ),
                ],
                if (item.notes != null && item.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.notes!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: OnlineColors.textDim,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      Money(item.lineTotal).format('CHF'),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: OnlineColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
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

          // Delete
          GestureDetector(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: OnlineColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        color: OnlineColors.pillActiveBg,
        child: const Center(
          child: Icon(Icons.restaurant_rounded,
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
    return Container(
      decoration: BoxDecoration(
        color: OnlineColors.pillInactiveBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Btn(icon: Icons.remove_rounded, onTap: onDecrement),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$quantity',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          _Btn(icon: Icons.add_rounded, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: OnlineColors.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: Colors.white),
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
            icon: Icons.table_restaurant_rounded,
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
          color: selected ? OnlineColors.pillActiveBg : OnlineColors.bgPage,
          borderRadius: BorderRadius.circular(kRadiusMedium),
          border: Border.all(
            color: selected ? OnlineColors.primary : OnlineColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected
                  ? OnlineColors.primary
                  : OnlineColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
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
    final vatLabel = '${vatRate == SwissVat.standard ? '8.1' : '2.6'}%';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OnlineColors.bgCard,
        borderRadius: BorderRadius.circular(kRadiusLarge),
        border: Border.all(color: OnlineColors.divider),
      ),
      child: Column(
        children: [
          _Row(label: l10n.subtotal, value: Money(cart.subtotalCents).format('CHF')),
          const SizedBox(height: 6),
          _Row(
            label: '${l10n.vat} ($vatLabel)',
            value: Money(cart.vatCents).format('CHF'),
            dim: true,
          ),
          if (cart.roundingCents != 0) ...[
            const SizedBox(height: 6),
            _Row(
              label: l10n.rounding,
              value: '${cart.roundingCents < 0 ? '-' : ''}${Money(cart.roundingCents.abs()).format('CHF')}',
              dim: true,
            ),
          ],
          const SizedBox(height: 12),
          const Divider(color: OnlineColors.divider),
          const SizedBox(height: 12),
          _Row(
            label: l10n.total,
            value: Money(cart.totalRounded).format('CHF'),
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.bold = false,
    this.dim = false,
  });
  final String label;
  final String value;
  final bool bold;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final color = dim ? OnlineColors.textSecondary : OnlineColors.textPrimary;
    final weight = bold ? FontWeight.w700 : FontWeight.w400;
    final size = bold ? 16.0 : 14.0;

    return Row(
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: size, fontWeight: weight, color: color)),
        const Spacer(),
        Text(value,
            style: GoogleFonts.inter(
                fontSize: size, fontWeight: weight, color: color)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Checkout CTA bar
// ---------------------------------------------------------------------------

class _CheckoutBar extends ConsumerWidget {
  const _CheckoutBar({required this.cart, required this.restaurantId});
  final Cart cart;
  final String restaurantId;

  bool get _canCheckout {
    if (cart.isEmpty) return false;
    if (cart.orderType == null) return false;
    if (cart.orderType == OrderType.dineIn && cart.tableNumber == null)
      return false;
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
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
        onPressed: _canCheckout
            ? () => context.go('/$restaurantId/checkout')
            : null,
        child: Text(l10n.continueToCheckout),
      ),
    );
  }
}
