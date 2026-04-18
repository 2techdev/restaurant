/// Bottom action bar for the fine-dining shell.
///
/// Mirrors SambaPOS' bottom strip: back (close ticket), new order, send to
/// kitchen (fires the active Gang), running total, and a prominent Pay CTA.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';

class BottomActionBar extends ConsumerWidget {
  const BottomActionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final hasItems = ticket != null && ticket.items.isNotEmpty;
    final total = ticket?.total ?? 0;

    return Container(
      height: AppTokens.bottomBarHeight,
      padding: AppInsets.h12v8,
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainer,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          _SecondaryButton(
            icon: Icons.arrow_back_rounded,
            label: 'Geri',
            onTap: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                context.go(AppRoutes.home);
              }
            },
          ),
          const SizedBox(width: AppTokens.space8),
          _SecondaryButton(
            icon: Icons.add_circle_outline_rounded,
            label: 'Yeni',
            onTap: () => _createNew(context, ref),
          ),
          const SizedBox(width: AppTokens.space8),
          _SecondaryButton(
            icon: Icons.send_rounded,
            label: 'Gönder',
            onTap: hasItems ? () => _sendToKitchen(context, ref) : null,
          ),
          const Spacer(),
          _TotalDisplay(totalCents: total),
          const SizedBox(width: AppTokens.space12),
          _PayCta(
            enabled: hasItems,
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
    // New order from scratch — waiter context resolved by provider.
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
    // TODO(sprint 2): wire to CurrentTicketNotifier.sendToKitchen.
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = enabled ? AppColors.textPrimary : AppColors.textDim;
    return Material(
      color: AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space12,
            vertical: AppTokens.space8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: fg,
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
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'TOPLAM',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.textDim,
            letterSpacing: 1.2,
          ),
        ),
        Text(
          'CHF $whole.$frac',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _PayCta extends StatelessWidget {
  const _PayCta({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppTokens.touchLarge,
      child: ElevatedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: const Icon(Icons.payments_rounded, size: 20),
        label: const Text(
          'ÖDEME',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryContainer,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
        ),
      ),
    );
  }
}
