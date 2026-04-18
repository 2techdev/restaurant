/// Fine-dining shell — Kinetic Grid 4-column layout.
///
/// Left:   [OrderPanel]        — ticket sidebar with selected/void states.
/// Centre: [CategoryStrip]     — horizontal SambaPOS warm tiles.
///         [ProductGrid]       — 1/2-column responsive grid.
/// Right:  [ActionRail]        — Pay + Split + Void in semantic colours.
/// Bottom: [BottomActionBar]   — Close / New / Send / Split / Card / Cash.
///
/// The whole subtree is wrapped in a local [Theme] override so only the
/// sales surface gets the Kinetic palette — Settings / Tables / Reports
/// continue to render on the existing dark theme.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
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

    final pendingByProduct = <String, int>{};
    if (ticket != null) {
      for (final item in ticket.items) {
        if (item.sentToKitchen) continue;
        pendingByProduct[item.productId] =
            (pendingByProduct[item.productId] ?? 0) + item.quantity.round();
      }
    }

    return Theme(
      data: buildKineticTheme(),
      child: Scaffold(
        backgroundColor: GcColors.surface,
        body: SafeArea(
          child: Column(
            children: [
              const _TopBar(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const OrderPanel(),
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
                    const ActionRail(),
                  ],
                ),
              ),
              const BottomActionBar(),
            ],
          ),
        ),
      ),
    );
  }

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
// Top bar — dark-green SambaPOS accent, Terminal / Admin identity.
// ---------------------------------------------------------------------------

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final initials = _initials(user?.name ?? 'Staff');
    return Container(
      height: AppTokens.topBarHeight,
      color: GcColors.catDarkGreen,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.space12),
      child: Row(
        children: [
          _IconTile(
            icon: Icons.grid_view_rounded,
            onTap: () => context.go(AppRoutes.home),
          ),
          const SizedBox(width: AppTokens.space12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'TERMINAL 01',
                style: GcText.labelTiny.copyWith(
                  color: GcColors.onPrimary.withValues(alpha: 0.75),
                ),
              ),
              Text(
                (user?.name ?? 'Admin').toUpperCase(),
                style: GcText.headline.copyWith(
                  color: GcColors.onPrimary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Spacer(),
          const _TopTileGroup(),
          const SizedBox(width: AppTokens.space8),
          _IconTile(
            icon: Icons.table_restaurant_rounded,
            onTap: () => context.push(AppRoutes.tables),
          ),
          const SizedBox(width: 4),
          _IconTile(
            icon: Icons.settings_rounded,
            onTap: () => context.push(AppRoutes.settings),
          ),
          const SizedBox(width: AppTokens.space8),
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
      color: GcColors.secondaryDim,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 18, color: GcColors.onPrimary),
        ),
      ),
    );
  }
}

/// Small cluster of "quick item" tiles on the top bar — a placeholder
/// for the SambaPOS-style favourites row (e.g. Coca-Cola variants).
/// Rendered only on wide tablets (>= 1100px) so it doesn't crowd the
/// 7" pilot layout.
class _TopTileGroup extends StatelessWidget {
  const _TopTileGroup();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, bc) {
        final wide = MediaQuery.sizeOf(ctx).width >= 1100;
        if (!wide) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _quick('COLA', GcColors.catRed),
            const SizedBox(width: 2),
            _quick('ZERO', GcColors.error),
            const SizedBox(width: 2),
            _quick('LIGHT', GcColors.catRed),
          ],
        );
      },
    );
  }

  Widget _quick(String label, Color bg) {
    return Container(
      color: bg,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      child: Text(
        label,
        style: GcText.button.copyWith(
          fontSize: 10,
          color: GcColors.onPrimary,
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
      color: GcColors.secondaryDim,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GcText.button.copyWith(
          fontSize: 12,
          color: GcColors.onPrimary,
        ),
      ),
    );
  }
}
