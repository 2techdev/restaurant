/// Fine-dining shell — Kinetic Grid 4-column layout (v3).
///
/// Top bar          — "Gastro Core" brand + sync / settings / user icons.
/// Row:
///   1. [LeftNavRail]          — nav stack + action zone (incl. Pay).
///   2. [OrderPanel]           — ticket sidebar (header / items / totals).
///   3. [GridCategoryColumn]   — vertical 2-col aspect-square category grid.
///   4. Product area           — category header, favorites bar, product grid.
/// Bottom: [BottomActionBar]   — Close + Pay CTA.
///
/// The app-level theme is now Kinetic (see `app.dart`), so the earlier local
/// `Theme(data: buildKineticTheme(), ...)` wrap has been removed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/bottom_action_bar.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/column_toggle_button.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/favorites_bar.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/grid_category_column.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/left_nav_rail.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/order_panel.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/product_grid.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';

class FineDiningShell extends ConsumerWidget {
  const FineDiningShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final activeGang = ref.watch(activeGangProvider);

    final pendingByProduct = <String, int>{};
    if (ticket != null) {
      for (final item in ticket.items) {
        if (item.sentToKitchen) continue;
        pendingByProduct[item.productId] =
            (pendingByProduct[item.productId] ?? 0) + item.quantity.round();
      }
    }

    return Scaffold(
      backgroundColor: GcColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const _TopBar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LeftNavRail(),
                  const OrderPanel(),
                  const GridCategoryColumn(),
                  Expanded(
                    child: _ProductArea(
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
            const BottomActionBar(),
          ],
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
// Product area — h-14 header with category name + underline search, then grid.
// ---------------------------------------------------------------------------

class _ProductArea extends ConsumerWidget {
  const _ProductArea({
    required this.cartQuantities,
    required this.onProductTap,
  });

  final Map<String, int> cartQuantities;
  final void Function(ProductEntity) onProductTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedCategoryProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final headerLabel = categoriesAsync.maybeWhen(
      data: (cats) => _headerFor(selectedId, cats),
      orElse: () => 'TÜMÜ',
    );

    return ColoredBox(
      color: GcColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProductHeader(title: headerLabel),
          FavoritesBar(onAddProduct: onProductTap),
          Expanded(
            child: ProductGrid(
              cartQuantities: cartQuantities,
              onProductTap: onProductTap,
            ),
          ),
        ],
      ),
    );
  }

  String _headerFor(String? id, List<CategoryEntity> cats) {
    if (id == null) return 'TÜMÜ';
    return cats
        .firstWhere(
          (c) => c.id == id,
          orElse: () => cats.isEmpty
              ? const CategoryEntity(
                  id: '',
                  tenantId: '',
                  name: '',
                  displayOrder: 0,
                  color: '',
                  icon: '',
                  isActive: true,
                )
              : cats.first,
        )
        .name
        .toUpperCase();
  }
}

class _ProductHeader extends ConsumerWidget {
  const _ProductHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 56,
      color: GcColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.space16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontFamily: 'WorkSans',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: GcColors.onSurface,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const ColumnToggleButton(),
          const SizedBox(width: AppTokens.space12),
          const _SearchField(),
        ],
      ),
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(productSearchProvider),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 36,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: GcColors.surfaceContainerLowest,
          border: Border(
            bottom: BorderSide(color: GcColors.primary, width: 2),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: AppTokens.space8),
            const Icon(
              Icons.search_rounded,
              size: 18,
              color: GcColors.onSurfaceVariant,
            ),
            const SizedBox(width: AppTokens.space8),
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: (v) =>
                    ref.read(productSearchProvider.notifier).state = v,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: GcColors.onSurface,
                ),
                decoration: const InputDecoration(
                  hintText: 'Ara…',
                  hintStyle: TextStyle(
                    color: GcColors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar — "Gastro Core" brand on a high-surface strip.
// ---------------------------------------------------------------------------

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: AppTokens.topBarHeight,
      color: GcColors.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.space16),
      child: Row(
        children: [
          const Text(
            'Gastro Core',
            style: TextStyle(
              fontFamily: 'WorkSans',
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: GcColors.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: AppTokens.space12),
          const _DiagnosticBadge(),
          const Spacer(),
          _IconButton(
            icon: Icons.sync_rounded,
            onTap: () {},
          ),
          _IconButton(
            icon: Icons.settings_rounded,
            onTap: () => context.push(AppRoutes.settings),
          ),
          _IconButton(
            icon: Icons.person_rounded,
            onTap: () => context.go(AppRoutes.home),
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: GcColors.surfaceContainerHigh,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 20,
            color: GcColors.primary,
          ),
        ),
      ),
    );
  }
}

// TEMPORARY pilot diagnostic — remove after the empty-screens bug is solved.
// Shows the runtime tenantId tail, and the counts of the objects the three
// "broken" surfaces depend on: categories, active products, favorites
// (SharedPreferences), and all tables (DB). If the overlay shows the seed
// tenantId with non-zero counts, the storefront bug is a rendering problem,
// not a data-loading one. If the counts are zero the seed didn't land.
class _DiagnosticBadge extends ConsumerWidget {
  const _DiagnosticBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = ref.watch(tenantIdProvider);
    final tenantTail = tenantId.length > 8
        ? tenantId.substring(tenantId.length - 8)
        : tenantId;
    final cats = ref.watch(categoriesProvider).asData?.value.length ?? -1;
    final prods =
        ref.watch(allActiveProductsProvider).asData?.value.length ?? -1;
    final favs = ref.watch(favoritesProvider).length;
    final tbls = ref.watch(allTablesProvider).asData?.value.length ?? -1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.amber.shade100,
      child: Text(
        'T:$tenantTail C:$cats P:$prods F:$favs TBL:$tbls',
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
      ),
    );
  }
}
