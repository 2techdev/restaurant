/// Fine-dining shell — SambaPOS-style three-column layout.
///
/// Left:   [OrderPanel]        — ticket items grouped by Gang (1/2/3).
/// Center: [CategoryStrip]     — horizontal pill chips + column-toggle button.
///         [ProductGrid]       — user-toggleable 1 ↔ 2 column grid (KRİTİK).
/// Right:  [ActionRail]        — vertical action buttons (Note, Split, Pay…).
/// Bottom: [BottomActionBar]   — Geri / Yeni / Gönder / TOPLAM / ÖDEME.
///
/// This screen is intentionally thin: it pulls providers for the active
/// ticket + device id and delegates rendering to the shell widgets under
/// `widgets/shell/`. Menu / order composition lives in those leaves so
/// we can reuse them in a future "waiter app" flavour without dragging
/// the POS-only top bar along.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/action_rail.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/bottom_action_bar.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/category_strip.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/column_toggle_button.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/order_panel.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/product_grid.dart';

class FineDiningShell extends ConsumerWidget {
  const FineDiningShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final columns = ref.watch(productGridColumnsProvider);
    final activeGang = ref.watch(activeGangProvider);

    // Derive pending-quantity map for the grid badge. Only items still in
    // the active Gang and not yet sent should influence the overlay.
    final pendingByProduct = <String, int>{};
    if (ticket != null) {
      for (final item in ticket.items) {
        if (item.sentToKitchen) continue;
        pendingByProduct[item.productId] =
            (pendingByProduct[item.productId] ?? 0) + item.quantity.round();
      }
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: SafeArea(
        child: Column(
          children: [
            const _TopBar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const OrderPanel(),
                  const VerticalDivider(
                    width: 1,
                    color: AppColors.border,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        const CategoryStrip(trailing: ColumnToggleButton()),
                        Expanded(
                          child: ProductGrid(
                            columns: columns,
                            cartQuantities: pendingByProduct,
                            onProductTap: (product) {
                              _onProductTap(
                                context,
                                ref,
                                product,
                                course: activeGang,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(
                    width: 1,
                    color: AppColors.border,
                  ),
                  const ActionRail(),
                ],
              ),
            ),
            const BottomActionBar(),
          ],
        ),
      ),
    );
  }

  /// Add [product] to the active ticket. If no ticket exists yet, create a
  /// fresh draft bound to the current terminal device. [course] maps 1:1 to
  /// Gang number so the new item lands in the currently-focused Gang.
  Future<void> _onProductTap(
    BuildContext context,
    WidgetRef ref,
    ProductEntity product, {
    required int course,
  }) async {
    final notifier = ref.read(currentTicketProvider.notifier);
    var ticket = ref.read(currentTicketProvider);
    if (ticket == null) {
      final user = ref.read(currentUserProvider);
      await notifier.createNewTicket(
        deviceId: 'DEV-POS-01',
        waiterId: user?.id,
      );
      ticket = ref.read(currentTicketProvider);
    }
    if (ticket == null) return;
    notifier.addItem(product, course: course);
  }
}

// ---------------------------------------------------------------------------
// Top bar — compact header with home, ticket, and settings hotspots.
// ---------------------------------------------------------------------------

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final initials = _initials(user?.name ?? 'Staff');
    return Container(
      height: AppTokens.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.space16),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          _IconTile(
            icon: Icons.grid_view_rounded,
            onTap: () => context.go(AppRoutes.home),
          ),
          const SizedBox(width: AppTokens.space12),
          const Expanded(
            child: Text(
              'GastroCore POS — Fine Dining',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          _IconTile(
            icon: Icons.table_restaurant_rounded,
            onTap: () => context.push(AppRoutes.tables),
          ),
          const SizedBox(width: AppTokens.space8),
          _IconTile(
            icon: Icons.settings_rounded,
            onTap: () => context.push(AppRoutes.settings),
          ),
          const SizedBox(width: AppTokens.space12),
          _UserBadge(initials: initials),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _UserBadge extends StatelessWidget {
  const _UserBadge({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.accent.withValues(alpha: 0.15),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}
