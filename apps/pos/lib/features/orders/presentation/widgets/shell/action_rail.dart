/// Right-column action rail — global commands on the ticket.
///
/// SambaPOS-like vertical stack of icon+label buttons: Discount, Split, Note,
/// Void, Pay. Each button is a large touch target (48dp minimum) — avoids
/// mis-taps during service.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
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
      color: AppColors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space12),
      child: Column(
        children: [
          _RailButton(
            icon: Icons.search_rounded,
            label: 'Ara',
            onTap: () {
              // Search is handled in the CategoryStrip's search slot in v1.
            },
          ),
          _RailButton(
            icon: Icons.note_alt_outlined,
            label: 'Not',
            enabled: hasTicket,
            onTap: () => _showComingSoon(context, 'Not ekleme'),
          ),
          _RailButton(
            icon: Icons.percent_rounded,
            label: 'İndirim',
            enabled: hasTicket,
            onTap: () => _showComingSoon(context, 'İndirim'),
          ),
          _RailButton(
            icon: Icons.call_split_rounded,
            label: 'Böl',
            enabled: hasTicket,
            onTap: () {
              if (ticket != null) {
                context.push(AppRoutes.splitBillFor(ticket.id));
              }
            },
          ),
          _RailButton(
            icon: Icons.warning_amber_rounded,
            label: 'İptal',
            enabled: hasTicket,
            tone: _Tone.danger,
            onTap: () => _showComingSoon(context, 'Kalem iptali'),
          ),
          const Spacer(),
          _RailButton(
            icon: Icons.payments_rounded,
            label: 'Öde',
            enabled: hasTicket &&
                ticket.status != TicketStatus.completed &&
                ticket.status != TicketStatus.voided,
            tone: _Tone.primary,
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
        content: Text('$label — ileriki sprint\'te (placeholder).'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

enum _Tone { normal, primary, danger }

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.tone = _Tone.normal,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final fg = !enabled
        ? AppColors.textDim
        : switch (tone) {
            _Tone.primary => Colors.white,
            _Tone.danger => AppColors.red,
            _Tone.normal => AppColors.textPrimary,
          };
    final bg = tone == _Tone.primary
        ? AppColors.primaryContainer
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 4,
      ),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    letterSpacing: 0.3,
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
