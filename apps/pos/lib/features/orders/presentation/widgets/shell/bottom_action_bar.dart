/// Bottom action bar — KAPAT / ÖDEME (pilot v3).
///
/// The SambaPOS-style Split / Card / Cash cluster moved into a dedicated
/// payment screen (see [OrderPaymentScreen]); the bottom bar now shows just
/// two operator-scale actions so the ticket → settlement path is a single tap:
///
///   * [KAPAT] (error/catRed) — close the sales shell.
///   * [ÖDEME] (catGreen gradient, flex-1, full width) — push the payment
///     screen with the current ticket as context. Disabled when the ticket
///     has no items.
///
/// The running total sits on the ÖDEME button so the bar stays a two-child
/// row that scales down to narrow tablets without reflow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/screens/payment_screen.dart';

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
          _CloseButton(
            onTap: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                context.go(AppRoutes.home);
              }
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PayButton(
              enabled: hasItems,
              totalCents: total,
              onTap: () {
                if (ticket == null) return;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OrderPaymentScreen(ticketId: ticket.id),
                    fullscreenDialog: true,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KAPAT — fixed-width error button.
// ---------------------------------------------------------------------------

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GcColors.catRed,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: AppTokens.touchLarge,
          width: 160,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: kInsetHighlight, width: 2),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.close_rounded, size: 20, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'KAPAT',
                style: TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ÖDEME — flex-1 CTA with cash gradient + total readout.
// ---------------------------------------------------------------------------

class _PayButton extends StatelessWidget {
  const _PayButton({
    required this.enabled,
    required this.totalCents,
    required this.onTap,
  });

  final bool enabled;
  final int totalCents;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final whole = totalCents ~/ 100;
    final frac = (totalCents % 100).toString().padLeft(2, '0');
    return Material(
      color: enabled ? GcColors.catGreen : GcColors.surfaceContainerHighest,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          height: AppTokens.touchLarge,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: enabled ? kCashGradient : null,
            border: enabled
                ? const Border(
                    top: BorderSide(color: kInsetHighlight, width: 2),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                Icons.payments_rounded,
                size: 22,
                color: enabled ? Colors.white : GcColors.outlineVariant,
              ),
              const SizedBox(width: 12),
              Text(
                'ÖDEME',
                style: TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: enabled ? Colors.white : GcColors.outlineVariant,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Text(
                'CHF $whole.$frac',
                style: TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: enabled ? Colors.white : GcColors.outlineVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
