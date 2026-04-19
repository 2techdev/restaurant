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
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
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
// Top bar — POS v2 brand lockup + ticket meta + mode switch + user pill.
//
// Layout (left → right):
//   * "Gastro" (upright) + "Core" (italic) — brand lockup
//   * "POS · v2" chip
//   * Ticket # · table meta (when a ticket is active)
//   * mode switch: Im Haus / Takeaway / Theke
//   * diagnostic tenant/count badge
//   * [flex spacer]
//   * search (owned by product area below — not duplicated here)
//   * sync / settings icons
//   * user pill: "Terminal · <name>"
// ---------------------------------------------------------------------------

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final user = ref.watch(currentUserProvider);

    return Container(
      height: AppTokens.topBarHeight,
      color: GcColors.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.space16),
      child: Row(
        children: [
          const _BrandLockup(),
          const SizedBox(width: AppTokens.space8),
          const _PosTag(),
          if (ticket != null) ...[
            const SizedBox(width: AppTokens.space12),
            _TicketMeta(ticket: ticket),
          ],
          const SizedBox(width: AppTokens.space12),
          const _ModeSwitch(),
          const SizedBox(width: AppTokens.space8),
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
          const SizedBox(width: AppTokens.space4),
          _UserPill(
            userLabel: user?.name.split(' ').first ?? 'Kullanıcı',
            onTap: () => context.go(AppRoutes.home),
          ),
        ],
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          'Gastro',
          style: TextStyle(
            fontFamily: 'WorkSans',
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: GcColors.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        Text(
          'Core',
          style: TextStyle(
            fontFamily: 'WorkSans',
            fontSize: 20,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            color: GcColors.primary,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

class _PosTag extends StatelessWidget {
  const _PosTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: const BoxDecoration(color: GcColors.surfaceContainerHigh),
      child: Text(
        'POS · v2',
        style: GcText.labelTiny.copyWith(
          fontSize: 10,
          color: GcColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TicketMeta extends StatelessWidget {
  const _TicketMeta({required this.ticket});
  final TicketEntity ticket;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      '#${ticket.orderNumber}',
      if (ticket.tableId != null && ticket.tableId!.isNotEmpty)
        'T ${ticket.tableId}'
      else
        _orderTypeShort(ticket.orderType),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: const BoxDecoration(
        color: GcColors.surfaceContainerLowest,
        border: Border(
          left: BorderSide(color: GcColors.primary, width: 2),
        ),
      ),
      child: Text(
        parts.join(' · '),
        style: GcText.button.copyWith(
          fontSize: 11,
          color: GcColors.onSurface,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  static String _orderTypeShort(OrderType t) {
    switch (t) {
      case OrderType.dineIn:
        return 'Im Haus';
      case OrderType.takeaway:
        return 'Takeaway';
      case OrderType.delivery:
        return 'Delivery';
      case OrderType.online:
        return 'Online';
    }
  }
}

class _ModeSwitch extends ConsumerWidget {
  const _ModeSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final current = ticket?.orderType ?? OrderType.dineIn;
    final hasTicket = ticket != null;

    return DecoratedBox(
      decoration: const BoxDecoration(color: GcColors.surfaceContainerLowest),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeChip(
            label: 'Im Haus',
            active: current == OrderType.dineIn,
            enabled: hasTicket,
            onTap: () => ref
                .read(currentTicketProvider.notifier)
                .updateOrderType(OrderType.dineIn),
          ),
          _ModeChip(
            label: 'Takeaway',
            active: current == OrderType.takeaway,
            enabled: hasTicket,
            onTap: () => ref
                .read(currentTicketProvider.notifier)
                .updateOrderType(OrderType.takeaway),
          ),
          _ModeChip(
            label: 'Theke',
            // POS v2 "Theke" ≈ counter / quick-serve. Maps to delivery slot
            // internally — it's the fastest takeaway bucket the domain has
            // and preserves the tax path (takeaway MWST).
            active: current == OrderType.delivery,
            enabled: hasTicket,
            onTap: () => ref
                .read(currentTicketProvider.notifier)
                .updateOrderType(OrderType.delivery),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active ? GcColors.primary : Colors.transparent;
    final fg = active
        ? GcColors.onPrimary
        : (enabled ? GcColors.onSurface : GcColors.outline);
    return Material(
      color: bg,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: GcText.button.copyWith(
              fontSize: 11,
              color: fg,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}

class _UserPill extends StatelessWidget {
  const _UserPill({required this.userLabel, required this.onTap});
  final String userLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GcColors.surfaceContainerLowest,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_rounded,
                size: 14,
                color: GcColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'T·01 · $userLabel',
                style: GcText.button.copyWith(
                  fontSize: 11,
                  color: GcColors.onSurface,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
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
          width: 40,
          height: 40,
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
