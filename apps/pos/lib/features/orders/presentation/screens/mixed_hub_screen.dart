/// Mixed-mode Order Center hub.
///
/// Landing screen when `RestaurantConfig.PosMode.mixed` is active. Two
/// columns side by side so the operator can settle a table flow and
/// open a quick-sale counter ticket without leaving the hub:
///
///   LEFT  (≈340dp)  Quick-sale CTA + active-ticket summary list
///   RIGHT (Expanded) Floor plan grid (reuses the v3 enriched tile)
///
/// Faz 4 MVP — keeps the existing FloorPlanScreen + FastSaleScreen
/// reachable via deep links so the new hub only adds an entry point.
/// Sidebar Home button routes here for mode=mixed.
library;
// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/mode_switcher_pill.dart';
import 'package:gastrocore_pos/features/online_orders/presentation/providers/online_order_provider.dart';
import 'package:gastrocore_pos/features/online_orders/presentation/providers/online_orders_settings_provider.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';

class MixedHubScreen extends ConsumerWidget {
  const MixedHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: SafeArea(
        // v2 (2026-05-17 UX overhaul): 3-column command center.
        // LEFT (≈320) Active tickets list (was sol panel)
        // MID  (Expanded) Floor preview grid (was right panel)
        // RIGHT (≈300) Quick-sale CTA + online preview + KPI
        child: LayoutBuilder(builder: (context, bc) {
          final narrow = bc.maxWidth < 1180;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: 320, child: _LeftPanel()),
              const VerticalDivider(width: 1, color: AppColors.border),
              const Expanded(child: _RightPanel()),
              if (!narrow) ...[
                const VerticalDivider(width: 1, color: AppColors.border),
                const SizedBox(width: 300, child: _SideRail()),
              ],
            ],
          );
        }),
      ),
    );
  }
}

class _LeftPanel extends ConsumerWidget {
  const _LeftPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openTickets = ref.watch(openTicketsProvider);
    return Container(
      color: AppColors.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Text(
                  'Order Center',
                  style: TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const ModeSwitcherPill(),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tisch açın, hızlı satış başlatın veya bekleyen siparişe gidin.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'AKTİF BESTELLUNGEN',
            style: TextStyle(
              fontFamily: 'WorkSans',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: openTickets.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (_, __) => const Center(
                child: Text(
                  'Aktif sipariş yüklenemedi.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
              ),
              data: (tickets) {
                if (tickets.isEmpty) {
                  return const _LeftEmpty();
                }
                return ListView.separated(
                  itemCount: tickets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _TicketRow(ticket: tickets[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickSaleCta extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context.go(AppRoutes.fastSale),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                offset: Offset(0, 2),
                blurRadius: 6,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.flash_on_rounded,
                  size: 26,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Yeni Schnellverkauf',
                      style: TextStyle(
                        fontFamily: 'WorkSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Counter / Theke akışı — tek dokunuş',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xDDFFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 22,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketRow extends ConsumerWidget {
  const _TicketRow({required this.ticket});
  final TicketEntity ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = (ticket.total / 100).toStringAsFixed(2);
    final hasTable =
        ticket.tableId != null && ticket.tableId!.isNotEmpty;
    final delta = DateTime.now().difference(ticket.openedAt);
    final dur = delta.inHours > 0
        ? '${delta.inHours}h${(delta.inMinutes % 60).toString().padLeft(2, '0')}'
        : "${delta.inMinutes}'";
    return InkWell(
      onTap: () async {
        await ref
            .read(currentTicketProvider.notifier)
            .loadTicket(ticket.id);
        if (context.mounted) {
          context.push(AppRoutes.orderCenter);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: hasTable
                    ? AppColors.accentDim
                    : AppColors.orangeDim,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Icon(
                hasTable
                    ? Icons.table_restaurant_rounded
                    : Icons.flash_on_rounded,
                size: 18,
                color: hasTable ? AppColors.accent : AppColors.orange,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasTable
                        ? 'Tisch ${ticket.tableId}'
                        : 'Schnellverkauf',
                    style: const TextStyle(
                      fontFamily: 'WorkSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '#${ticket.orderNumber} · $dur',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'CHF $total',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// v2 right column — quick-sale hero CTA + online preview + KPIs.
/// Renders only when the layout has ≥1180dp width; narrower viewports
/// fall back to the 2-col view (Left + Mid).
class _SideRail extends ConsumerWidget {
  const _SideRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingOnlineOrdersProvider);
    final onlineEnabled = ref.watch(onlineOrdersEnabledProvider);
    final openTickets = ref.watch(openTicketsProvider).value ?? const [];
    // Naive KPI — sum of today's open tickets, no date filtering yet.
    // Faz D upgrade will add a closed-tickets-today provider.
    final activeRevenue = openTickets.fold<int>(0, (s, t) => s + t.total);
    return Container(
      color: AppColors.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'KOMUTLAR',
            style: TextStyle(
              fontFamily: 'WorkSans',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          _QuickSaleCta(),
          const SizedBox(height: 18),
          if (onlineEnabled) ...[
            _OnlinePreviewCard(pendingCount: pending.length),
            const SizedBox(height: 14),
          ],
          const Text(
            'GÜNCEL',
            style: TextStyle(
              fontFamily: 'WorkSans',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _KpiTile(
                  label: 'Aktif',
                  value: '${openTickets.length}',
                  caption: 'sipariş',
                  tint: const Color(0xFF1E40AF),
                  tintBg: const Color(0xFFDBEAFE),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiTile(
                  label: 'Açık Tutar',
                  value: 'CHF ${(activeRevenue / 100).toStringAsFixed(0)}',
                  caption: 'şu an',
                  tint: const Color(0xFF15803D),
                  tintBg: const Color(0xFFDCFCE7),
                ),
              ),
            ],
          ),
          const Spacer(),
          const Text(
            'v22 · mixed-hub',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              color: AppColors.textDim,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlinePreviewCard extends StatelessWidget {
  const _OnlinePreviewCard({required this.pendingCount});
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final empty = pendingCount == 0;
    return Material(
      color: empty ? AppColors.surface : const Color(0xFFFFEDD5),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => context.push(AppRoutes.onlineOrders),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: empty
                  ? AppColors.border
                  : const Color(0xFFEA580C).withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: empty
                      ? AppColors.surfaceContainerHigh
                      : const Color(0xFFEA580C),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.cloud_download_outlined,
                  size: 18,
                  color: empty ? AppColors.textDim : Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Online Bestellungen',
                      style: TextStyle(
                        fontFamily: 'WorkSans',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: empty
                            ? AppColors.textPrimary
                            : const Color(0xFF7C2D12),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      empty
                          ? 'Bekleyen yok'
                          : '$pendingCount yeni sipariş bekliyor',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: empty
                            ? AppColors.textDim
                            : const Color(0xFFC2410C),
                      ),
                    ),
                  ],
                ),
              ),
              if (!empty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA580C),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$pendingCount',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.tint,
    required this.tintBg,
  });
  final String label;
  final String value;
  final String caption;
  final Color tint;
  final Color tintBg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tintBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tint.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: 'WorkSans',
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: tint,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: tint,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeftEmpty extends StatelessWidget {
  const _LeftEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inbox_outlined,
              size: 32,
              color: AppColors.textDim,
            ),
            const SizedBox(height: 8),
            const Text(
              'Aktif sipariş yok.\nSağdan masa seç veya yukarıdan Schnellverkauf başlat.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textDim,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Right panel — quick floor preview pointing to the full plan.
/// Faz 4 MVP keeps it lightweight; embedding the full FloorPlanScreen
/// would require refactoring its Scaffold into a sliver-ready body
/// widget. Tap the CTA to jump into the full grid + edit mode.
class _RightPanel extends ConsumerWidget {
  const _RightPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablesAsync = ref.watch(tablesProvider);
    return Container(
      color: AppColors.surfaceDim,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Tisch Übersicht',
                style: TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => context.push(AppRoutes.tables),
                icon: const Icon(Icons.open_in_full_rounded, size: 14),
                label: const Text('Tam görünüm'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: tablesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (_, __) => const Center(
                child: Text(
                  'Masa listesi yüklenemedi.',
                  style: TextStyle(color: AppColors.textDim),
                ),
              ),
              data: (tables) {
                if (tables.isEmpty) {
                  return const Center(
                    child: Text(
                      'Henüz masa yok. Floor Plan ekranından ekleyin.',
                      style: TextStyle(color: AppColors.textDim),
                    ),
                  );
                }
                return GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 140,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: tables.length,
                  itemBuilder: (_, i) {
                    final t = tables[i];
                    final occupied = t.currentOrderId != null;
                    return GestureDetector(
                      onTap: () => context.push(AppRoutes.tables),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                              color: occupied
                                  ? AppColors.coral
                                  : AppColors.green,
                              width: 4,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              occupied ? 'BUSY' : 'FREE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: occupied
                                    ? AppColors.coral
                                    : AppColors.green,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${t.capacity} Sitze',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
