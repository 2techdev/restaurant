/// Bottom action bar — POS v2 three-cluster footer.
///
/// Layout (left → total → right):
///
///   Left cluster:
///     * [SCHLIESSEN] (error/catRed) — close the sales shell.
///     * [NEUER BON]                 — park current + start a new ticket.
///     * [SENDEN]                    — fire all unsent items to the kitchen.
///
///   Center:
///     * GESAMT readout — running total, Work Sans Black, tabular figures.
///
///   Right cluster:
///     * [TEILEN]   — split bill dialog (existing route).
///     * [KARTE]    — jump straight to card-payment path (payment screen).
///     * [BEZAHLEN] (catGreen gradient) — primary CTA; payment screen.
///
/// When there's no active ticket or no items, the action-dependent buttons
/// render in a dimmed disabled state — the bar never reflows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/screens/payment_screen.dart';

class BottomActionBar extends ConsumerWidget {
  const BottomActionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final hasTicket = ticket != null;
    final hasItems = hasTicket && ticket.items.isNotEmpty;
    final hasUnsent =
        hasItems && ticket.items.any((i) => !i.sentToKitchen);
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
          _SecondaryButton(
            icon: Icons.note_add_rounded,
            label: 'NEUER BON',
            enabled: true,
            onTap: () => _onNewTicket(context, ref, hasItems: hasItems),
          ),
          const SizedBox(width: 8),
          _SecondaryButton(
            icon: Icons.send_rounded,
            label: 'SENDEN',
            enabled: hasUnsent,
            onTap: () => _onSend(context, ref),
          ),
          const SizedBox(width: 12),
          Expanded(child: _TotalReadout(totalCents: total)),
          const SizedBox(width: 12),
          _SecondaryButton(
            icon: Icons.call_split_rounded,
            label: 'TEILEN',
            enabled: hasItems,
            onTap: () {
              if (ticket == null) return;
              context.push(AppRoutes.splitBillFor(ticket.id));
            },
          ),
          const SizedBox(width: 8),
          _SecondaryButton(
            icon: Icons.credit_card_rounded,
            label: 'KARTE',
            enabled: hasItems,
            onTap: () => _openPayment(context, ticket),
          ),
          const SizedBox(width: 8),
          _PayButton(
            enabled: hasItems,
            totalCents: total,
            onTap: () => _openPayment(context, ticket),
          ),
        ],
      ),
    );
  }

  Future<void> _onNewTicket(
    BuildContext context,
    WidgetRef ref, {
    required bool hasItems,
  }) async {
    // Parked table tickets are allowed to sit unpaid — starting a new bon
    // from a table view never discards work (the bon is safely linked to
    // the table), so skip the warning dialog in that mode.
    final isTableTicket = ref.read(currentTicketProvider)?.tableId != null;
    if (hasItems && !isTableTicket) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Neuen Bon starten?'),
          content: const Text(
            'Der aktuelle Bon hat noch Artikel. Beim Start eines '
            'neuen Bons gehen nicht gesendete Änderungen verloren.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Neu starten'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    final user = ref.read(currentUserProvider);
    await ref.read(currentTicketProvider.notifier).createNewTicket(
          deviceId: 'DEV-POS-01',
          waiterId: user?.id,
        );
  }

  Future<void> _onSend(BuildContext context, WidgetRef ref) async {
    await ref.read(currentTicketProvider.notifier).sendToKitchen();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('An die Küche gesendet'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openPayment(BuildContext context, TicketEntity? ticket) {
    if (ticket == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderPaymentScreen(ticketId: ticket.id),
        fullscreenDialog: true,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SCHLIESSEN — fixed-width error button.
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
          width: 130,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: kInsetHighlight, width: 2),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.close_rounded, size: 18, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'SCHLIESSEN',
                style: TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.6,
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
// _SecondaryButton — neutral surface, icon + label, 88–112px wide.
// ---------------------------------------------------------------------------

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = enabled
        ? GcColors.surfaceContainerLowest
        : GcColors.surfaceContainerHighest;
    final fg = enabled ? GcColors.onSurface : GcColors.outline;
    return Material(
      color: bg,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          height: AppTokens.touchLarge,
          constraints: const BoxConstraints(minWidth: 96),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: enabled
              ? const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: kInsetHighlight, width: 2),
                  ),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  letterSpacing: 0.6,
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
// Center GESAMT readout — tabular figures, Work Sans Black.
// ---------------------------------------------------------------------------

class _TotalReadout extends StatelessWidget {
  const _TotalReadout({required this.totalCents});
  final int totalCents;

  @override
  Widget build(BuildContext context) {
    final whole = totalCents ~/ 100;
    final frac = (totalCents % 100).toString().padLeft(2, '0');
    return Container(
      height: AppTokens.touchLarge,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: GcColors.surfaceContainerLowest),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('GESAMT', style: GcText.labelTiny),
          const SizedBox(width: 12),
          Text(
            'CHF $whole.$frac',
            style: GcText.displayBlack.copyWith(
              fontSize: 24,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// BEZAHLEN — flex CTA with cash gradient; the primary settlement action.
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
    // a11y: the primary CTA gets a screen-reader label that includes the
    // amount so operators hear "Bezahlen, CHF 42.50" rather than just
    // "Bezahlen". The disabled state is exposed via enabled=false so
    // assistive tech can skip it when there's no active ticket.
    final chf = (totalCents / 100).toStringAsFixed(2);
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Bezahlen, CHF $chf',
      excludeSemantics: true,
      child: Material(
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.payments_rounded,
                  size: 20,
                  color: enabled ? Colors.white : GcColors.outlineVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'BEZAHLEN',
                  style: TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: enabled ? Colors.white : GcColors.outlineVariant,
                    letterSpacing: 0.8,
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
