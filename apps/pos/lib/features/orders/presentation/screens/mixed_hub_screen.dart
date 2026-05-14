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
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';

class MixedHubScreen extends ConsumerWidget {
  const MixedHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            SizedBox(width: 340, child: _LeftPanel()),
            VerticalDivider(width: 1, color: AppColors.border),
            Expanded(child: _RightPanel()),
          ],
        ),
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
          const Text(
            'Order Center',
            style: TextStyle(
              fontFamily: 'WorkSans',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
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
          _QuickSaleCta(),
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
