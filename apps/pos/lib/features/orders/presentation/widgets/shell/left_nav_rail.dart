/// Left navigation + action rail — Kinetic mockup layout.
///
/// Top half is the nav stack (Tables / Orders / Tickets / Accounts /
/// Inventory / Reports) with the active item rendered in primary blue and
/// an inset 4px white stripe down its leading edge. The bottom half is the
/// global action zone — a column of 5 aspect-square buttons
/// (Void / Print / Gift / Lock / Pay) wired to the current ticket. Pay
/// carries the primary gradient CTA treatment.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/order_panel.dart';

class LeftNavRail extends ConsumerWidget {
  const LeftNavRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final hasItems = ticket != null && ticket.items.isNotEmpty;
    final canPay = hasItems &&
        ticket.status != TicketStatus.completed &&
        ticket.status != TicketStatus.voided;
    final selectedItemId = ref.watch(selectedTicketItemProvider);
    final hasSelection = selectedItemId != null;

    return Container(
      width: AppTokens.leftNavRailWidth,
      color: GcColors.surfaceContainerLow,
      child: Column(
        children: [
          const SizedBox(height: AppTokens.space12),
          const _TerminalBadge(),
          const SizedBox(height: AppTokens.space16),
          // Nav stack
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _NavButton(
                  icon: Icons.table_restaurant_rounded,
                  label: 'MASALAR',
                  onTap: () => context.push(AppRoutes.tables),
                ),
                const _NavButton(
                  icon: Icons.receipt_long_rounded,
                  label: 'SATIŞ',
                  active: true,
                ),
                _NavButton(
                  icon: Icons.confirmation_number_outlined,
                  label: 'ADİSYON',
                  onTap: () => context.push(AppRoutes.orderHistory),
                ),
                _NavButton(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'KASA',
                  onTap: () => context.push(AppRoutes.zReport),
                ),
                _NavButton(
                  icon: Icons.inventory_2_rounded,
                  label: 'MENÜ',
                  onTap: () => context.push(AppRoutes.menuManagement),
                ),
                _NavButton(
                  icon: Icons.assessment_rounded,
                  label: 'RAPOR',
                  onTap: () => context.push(AppRoutes.analytics),
                ),
              ],
            ),
          ),
          // Action zone
          _ActionButton(
            icon: Icons.block_rounded,
            label: 'İPTAL',
            enabled: hasItems,
            onTap: () {
              if (ticket != null) {
                context.push(AppRoutes.voidFor(ticket.id));
              }
            },
          ),
          _ActionButton(
            icon: Icons.print_rounded,
            label: 'YAZDIR',
            enabled: hasItems,
            onTap: () {
              if (ticket != null) {
                context.push(AppRoutes.receiptFor(ticket.id));
              }
            },
          ),
          _ActionButton(
            icon: Icons.redeem_rounded,
            label: 'İKRAM',
            enabled: hasSelection,
            onTap: () => _showComingSoon(context, 'İkram'),
          ),
          _ActionButton(
            icon: Icons.lock_rounded,
            label: 'KİLİT',
            onTap: () => context.push(AppRoutes.login),
          ),
          _PayButton(
            enabled: canPay,
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

  void _showComingSoon(BuildContext ctx, String label) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text('$label — ileriki sprint\'te.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _TerminalBadge extends StatelessWidget {
  const _TerminalBadge();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppTokens.space4),
      child: Column(
        children: [
          Text('TERMİNAL 01', style: GcText.labelTiny),
          SizedBox(height: 2),
          Text(
            'ADMIN',
            style: TextStyle(
              fontFamily: 'WorkSans',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: GcColors.onSurfaceVariant,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? GcColors.onPrimary : GcColors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space4,
        vertical: 2,
      ),
      child: Material(
        color: active ? GcColors.primary : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: GcColors.surfaceContainerHigh,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: active
                  ? const Border(
                      left: BorderSide(color: Colors.white, width: 4),
                    )
                  : null,
              gradient: active ? kPrimaryGradient : null,
            ),
            child: Container(
              height: 64,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22, color: fg),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'WorkSans',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: fg,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? GcColors.onSurface : GcColors.outlineVariant;
    return AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: GcColors.surfaceContainerHigh,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: GcColors.outlineVariant),
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22, color: fg),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: fg,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  const _PayButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? GcColors.onPrimary : GcColors.outlineVariant;
    return AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: enabled ? GcColors.primary : GcColors.surfaceContainerHighest,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: enabled ? kPrimaryGradient : null,
              border: const Border(
                top: BorderSide(color: kInsetHighlight, width: 2),
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payments_rounded, size: 26, color: fg),
                  const SizedBox(height: 4),
                  Text(
                    'ÖDE',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: fg,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
