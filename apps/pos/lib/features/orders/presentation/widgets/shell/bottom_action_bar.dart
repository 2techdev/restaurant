/// Bottom action bar — SambaPOS warm defaults (pilot v3).
///
/// Close / New / Send / totals / Split / Card / Cash cluster. Colours are
/// seeded from the classic SambaPOS warm palette so operators coming from
/// the old terminal land on familiar greens / reds / blues:
///   * Close → [catRed] + white
///   * New   → neutral surface, dark text
///   * Send  → [catDarkGreen] + white
///   * Split → [primary] blue + white
///   * Card  → [primary] blue + white
///   * Cash  → [catGreen] + white (with [kCashGradient] top→dark-green)
/// The Pay CTA lives in the [LeftNavRail]'s action zone — this bar is for
/// mid-flow settlement actions only. Per-restaurant overrides land in a
/// later sprint via `RestaurantSettings.buttonColorMap`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';

class BottomActionBar extends ConsumerWidget {
  const BottomActionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final hasItems = ticket != null && ticket.items.isNotEmpty;
    final total = ticket?.total ?? 0;

    return Container(
      height: AppTokens.bottomBarHeight + 8,
      color: GcColors.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _ActionButton(
            label: 'KAPAT',
            icon: Icons.close_rounded,
            fill: GcColors.catRed,
            fg: Colors.white,
            onTap: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                context.go(AppRoutes.home);
              }
            },
          ),
          const SizedBox(width: 6),
          _ActionButton(
            label: 'YENİ',
            icon: Icons.add_rounded,
            fill: GcColors.surfaceContainerLowest,
            fg: GcColors.onSurface,
            onTap: () => _createNew(context, ref),
          ),
          const SizedBox(width: 6),
          _ActionButton(
            label: 'GÖNDER',
            icon: Icons.send_rounded,
            fill: GcColors.catDarkGreen,
            fg: Colors.white,
            enabled: hasItems,
            onTap: () => _sendToKitchen(context, ref),
          ),
          const SizedBox(width: 12),
          Expanded(child: _TotalDisplay(totalCents: total)),
          const SizedBox(width: 12),
          _ActionButton(
            label: 'BÖL',
            icon: Icons.call_split_rounded,
            fill: GcColors.primary,
            fg: GcColors.onPrimary,
            enabled: hasItems,
            onTap: () {
              if (ticket != null) {
                context.push(AppRoutes.splitBillFor(ticket.id));
              }
            },
          ),
          const SizedBox(width: 6),
          _ActionButton(
            label: 'KART',
            icon: Icons.credit_card_rounded,
            fill: GcColors.primary,
            fg: GcColors.onPrimary,
            enabled: hasItems,
            onTap: () {
              if (ticket != null) {
                context.push(AppRoutes.paymentFor(ticket.id));
              }
            },
          ),
          const SizedBox(width: 6),
          _ActionButton(
            label: 'NAKİT',
            icon: Icons.payments_rounded,
            fill: GcColors.catGreen,
            fg: Colors.white,
            enabled: hasItems,
            gradient: kCashGradient,
            onTap: () {
              if (ticket != null) {
                context.push(AppRoutes.paymentFor(ticket.id));
              }
            },
          ),
        ],
      ),
    );
  }

  void _createNew(BuildContext ctx, WidgetRef ref) {
    ref.read(currentTicketProvider.notifier).createNewTicket(
          deviceId: 'DEV-POS-01',
        );
  }

  void _sendToKitchen(BuildContext ctx, WidgetRef ref) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        content: Text('Aktif kalemler mutfağa gönderiliyor…'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.fill,
    required this.fg,
    required this.onTap,
    this.enabled = true,
    this.gradient,
  });

  final String label;
  final IconData icon;
  final Color fill;
  final Color fg;
  final VoidCallback onTap;
  final bool enabled;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final effectiveFg = enabled ? fg : GcColors.outlineVariant;
    return Material(
      color: enabled ? fill : GcColors.surfaceContainerHighest,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          height: AppTokens.touchLarge,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: enabled ? gradient : null,
            border: enabled
                ? const Border(
                    top: BorderSide(color: kInsetHighlight, width: 2),
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: effectiveFg),
              const SizedBox(width: 6),
              Text(
                label,
                style: GcText.button.copyWith(
                  fontSize: 12,
                  color: effectiveFg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalDisplay extends StatelessWidget {
  const _TotalDisplay({required this.totalCents});
  final int totalCents;

  @override
  Widget build(BuildContext context) {
    final whole = totalCents ~/ 100;
    final frac = (totalCents % 100).toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('TOPLAM', style: GcText.labelTiny),
        Text(
          'CHF $whole.$frac',
          style: GcText.displayBlack.copyWith(fontSize: 22),
        ),
      ],
    );
  }
}
