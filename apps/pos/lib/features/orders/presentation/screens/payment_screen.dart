/// Order payment screen — method chooser with ticket summary.
///
/// Pushed as a full-screen dialog from [BottomActionBar]'s ÖDEME CTA. Shows
/// the current ticket readonly on the left and a stack of large payment
/// method buttons on the right, matching the Kinetic theme scoped to the
/// sales shell:
///
///   * NAKİT (catGreen gradient) → routes to the settlement numpad with
///     cash pre-selected (existing `AppRoutes.paymentFor`).
///   * KART (primary blue) → routes to the settlement numpad with card as
///     the default method.
///   * BÖL (outline/neutral) → routes to the split-bill flow.
///   * KAPAT (error) → pops back to the sales shell without settling.
///
/// Named [OrderPaymentScreen] to disambiguate from the pre-existing
/// settlement `PaymentScreen` under `features/payments/...`. Cart state is
/// read via [currentTicketProvider]; no new provider is introduced.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';

class OrderPaymentScreen extends ConsumerWidget {
  const OrderPaymentScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);

    return Scaffold(
      backgroundColor: GcColors.surface,
      body: SafeArea(
        child: ticket == null
            ? const _EmptyState()
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: _TicketSummaryPanel(ticket: ticket),
                  ),
                  Expanded(
                    flex: 4,
                    child: _MethodsPanel(ticket: ticket),
                  ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left — ticket summary (readonly)
// ---------------------------------------------------------------------------

class _TicketSummaryPanel extends StatelessWidget {
  const _TicketSummaryPanel({required this.ticket});
  final TicketEntity ticket;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: GcColors.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: AppTokens.topBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.space20),
            color: GcColors.surfaceContainer,
            child: Row(
              children: [
                const Text(
                  'HESAP ÖZETİ',
                  style: TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: GcColors.onSurface,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Text(
                  '#${ticket.orderNumber}',
                  style: const TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: GcColors.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ticket.items.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.space16,
                      vertical: AppTokens.space12,
                    ),
                    itemCount: ticket.items.length,
                    separatorBuilder: (_, __) => const SizedBox(
                      height: 1,
                      child: ColoredBox(color: GcColors.ghostBorder),
                    ),
                    itemBuilder: (context, i) =>
                        _LineItemRow(item: ticket.items[i]),
                  ),
          ),
          _TotalsBar(ticket: ticket),
        ],
      ),
    );
  }
}

class _LineItemRow extends StatelessWidget {
  const _LineItemRow({required this.item});
  final OrderItemEntity item;

  @override
  Widget build(BuildContext context) {
    final qtyText = item.quantity == item.quantity.roundToDouble()
        ? item.quantity.toInt().toString()
        : item.quantity.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space8),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '$qtyText×',
              style: const TextStyle(
                fontFamily: 'WorkSans',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: GcColors.onSurfaceVariant,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              item.productName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: GcColors.onSurface,
              ),
            ),
          ),
          Text(
            _formatCents(item.subtotal),
            style: const TextStyle(
              fontFamily: 'WorkSans',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: GcColors.onSurface,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsBar extends StatelessWidget {
  const _TotalsBar({required this.ticket});
  final TicketEntity ticket;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space16,
        vertical: AppTokens.space16,
      ),
      color: GcColors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _totalRow('Ara Toplam', ticket.subtotal, emphasised: false),
          const SizedBox(height: 6),
          _totalRow('MWST', ticket.taxAmount, emphasised: false),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppTokens.space8),
            child: ColoredBox(
              color: GcColors.ghostBorder,
              child: SizedBox(height: 1, width: double.infinity),
            ),
          ),
          _totalRow('TOPLAM', ticket.total, emphasised: true),
        ],
      ),
    );
  }

  Widget _totalRow(String label, int cents, {required bool emphasised}) {
    final labelStyle = TextStyle(
      fontFamily: 'WorkSans',
      fontSize: emphasised ? 16 : 13,
      fontWeight: emphasised ? FontWeight.w900 : FontWeight.w700,
      color: emphasised ? GcColors.onSurface : GcColors.onSurfaceVariant,
      letterSpacing: emphasised ? 1.0 : 0.4,
    );
    final valueStyle = TextStyle(
      fontFamily: 'WorkSans',
      fontSize: emphasised ? 22 : 14,
      fontWeight: emphasised ? FontWeight.w900 : FontWeight.w700,
      color: emphasised ? GcColors.onSurface : GcColors.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: -0.5,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: labelStyle)),
        Text('CHF ${_formatCents(cents)}', style: valueStyle),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Right — method chooser stack
// ---------------------------------------------------------------------------

class _MethodsPanel extends StatelessWidget {
  const _MethodsPanel({required this.ticket});
  final TicketEntity ticket;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: GcColors.surface,
      padding: const EdgeInsets.all(AppTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _MethodsHeader(),
          const SizedBox(height: AppTokens.space16),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _MethodButton(
                    label: 'NAKİT',
                    icon: Icons.payments_rounded,
                    fill: GcColors.catGreen,
                    fg: Colors.white,
                    gradient: kCashGradient,
                    onTap: () =>
                        context.push(AppRoutes.paymentFor(ticket.id)),
                  ),
                ),
                const SizedBox(height: AppTokens.space12),
                Expanded(
                  child: _MethodButton(
                    label: 'KART',
                    icon: Icons.credit_card_rounded,
                    fill: GcColors.primary,
                    fg: GcColors.onPrimary,
                    gradient: kPrimaryGradient,
                    onTap: () =>
                        context.push(AppRoutes.paymentFor(ticket.id)),
                  ),
                ),
                const SizedBox(height: AppTokens.space12),
                Expanded(
                  child: _MethodButton(
                    label: 'BÖL',
                    icon: Icons.call_split_rounded,
                    fill: GcColors.surfaceContainerLowest,
                    fg: GcColors.onSurface,
                    outlined: true,
                    onTap: () =>
                        context.push(AppRoutes.splitBillFor(ticket.id)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.space16),
          _MethodButton(
            label: 'KAPAT',
            icon: Icons.close_rounded,
            fill: GcColors.error,
            fg: Colors.white,
            height: 64,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _MethodsHeader extends StatelessWidget {
  const _MethodsHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text(
          'ÖDEME YÖNTEMİ',
          style: TextStyle(
            fontFamily: 'WorkSans',
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: GcColors.onSurface,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.label,
    required this.icon,
    required this.fill,
    required this.fg,
    required this.onTap,
    this.gradient,
    this.outlined = false,
    this.height,
  });

  final String label;
  final IconData icon;
  final Color fill;
  final Color fg;
  final VoidCallback onTap;
  final Gradient? gradient;
  final bool outlined;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label ödeme yöntemi',
      child: Material(
      color: fill,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: gradient,
            border: Border(
              top: BorderSide(
                color: outlined ? GcColors.outlineVariant : kInsetHighlight,
                width: outlined ? 1 : 2,
              ),
              left: outlined
                  ? const BorderSide(color: GcColors.outlineVariant)
                  : BorderSide.none,
              right: outlined
                  ? const BorderSide(color: GcColors.outlineVariant)
                  : BorderSide.none,
              bottom: outlined
                  ? const BorderSide(color: GcColors.outlineVariant)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26, color: fg),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: fg,
                  letterSpacing: 1.2,
                ),
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
// Empty state — shown if the ticket vanished between tap and render.
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Aktif adisyon bulunamadı.',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: GcColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

String _formatCents(int cents) {
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = (abs % 100).toString().padLeft(2, '0');
  return '$whole.$frac';
}
