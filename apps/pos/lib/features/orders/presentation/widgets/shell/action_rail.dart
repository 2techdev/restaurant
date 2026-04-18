/// Right-column action rail — Kinetic semantic buttons.
///
/// SambaPOS-style vertical stack: Search / Note / Discount / Split / Void
/// with a Pay primary CTA pinned to the bottom. Each button carries the
/// semantic colour from the Kinetic Grid palette — Void is error-red,
/// Split is cyan, Pay is the primary gradient CTA.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';

class ActionRail extends ConsumerWidget {
  const ActionRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final hasTicket = ticket != null && ticket.items.isNotEmpty;

    return Container(
      width: AppTokens.actionRailWidth,
      color: GcColors.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(
        vertical: AppTokens.space8,
        horizontal: 4,
      ),
      child: Column(
        children: [
          _RailButton(
            icon: Icons.search_rounded,
            label: 'ARA',
            onTap: () {},
          ),
          _RailButton(
            icon: Icons.note_alt_outlined,
            label: 'NOT',
            enabled: hasTicket,
            onTap: () => _showComingSoon(context, 'Not ekleme'),
          ),
          _RailButton(
            icon: Icons.percent_rounded,
            label: 'İNDİRİM',
            enabled: hasTicket,
            onTap: () => _showComingSoon(context, 'İndirim'),
          ),
          _RailButton(
            icon: Icons.call_split_rounded,
            label: 'BÖL',
            enabled: hasTicket,
            accent: GcColors.catCyan,
            onTap: () {
              if (ticket != null) {
                context.push(AppRoutes.splitBillFor(ticket.id));
              }
            },
          ),
          _RailButton(
            icon: Icons.remove_circle_outline_rounded,
            label: 'İPTAL',
            enabled: hasTicket,
            accent: GcColors.error,
            onTap: () => _showComingSoon(context, 'Kalem iptali'),
          ),
          const Spacer(),
          _PayRailButton(
            enabled: hasTicket &&
                ticket.status != TicketStatus.completed &&
                ticket.status != TicketStatus.voided,
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

  void _showComingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label — ileriki sprint\'te.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final fg = !enabled
        ? GcColors.outlineVariant
        : (accent ?? GcColors.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: GcColors.surfaceContainerLowest,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: GcText.button.copyWith(
                    fontSize: 10,
                    color: fg,
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

class _PayRailButton extends StatelessWidget {
  const _PayRailButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            gradient: enabled ? kPrimaryGradient : null,
            color: enabled ? null : GcColors.surfaceContainerHighest,
            border: const Border(
              top: BorderSide(color: kInsetHighlight, width: 2),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.payments_rounded,
                size: 26,
                color: enabled ? GcColors.onPrimary : GcColors.outlineVariant,
              ),
              const SizedBox(height: 4),
              Text(
                'ÖDE',
                style: GcText.button.copyWith(
                  fontSize: 11,
                  color: enabled ? GcColors.onPrimary : GcColors.outlineVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
