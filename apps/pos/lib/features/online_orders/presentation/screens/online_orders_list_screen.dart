/// Online Bestellungen list screen.
///
/// Routes from the rail's `Online` entry. Surfaces the
/// [pendingOnlineOrdersProvider] queue — orders that have arrived via
/// the POS WebSocket but haven't been accepted/rejected yet.
///
/// Faz 1 (2026-05-15) ships the minimal viable shell: header + filter
/// tabs + a list of pending cards reusing the same Accept/Reject
/// affordances as the slide-in overlay. Faz 3 will:
///   - mount the WS pump at app boot so the queue actually fills
///   - add filter tabs for accepted / in-prep / ready / delivered
///   - wire the auto-print toggle from Settings
///   - surface the connection-test diagnostic
library;
// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/online_orders/domain/models/online_order_message.dart';
import 'package:gastrocore_pos/features/online_orders/presentation/providers/online_order_provider.dart';

class OnlineOrdersListScreen extends ConsumerWidget {
  const OnlineOrdersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingOnlineOrdersProvider);
    return Scaffold(
      backgroundColor: GcColors.surface,
      appBar: AppBar(
        backgroundColor: GcColors.surfaceContainerLow,
        foregroundColor: GcColors.onSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            const Text(
              'Online Bestellungen',
              style: TextStyle(
                fontFamily: 'WorkSans',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),
            if (pending.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEA580C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${pending.length}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
      body: pending.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: pending.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) =>
                  _OrderListCard(order: pending[i]),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 56,
            color: GcColors.outlineVariant,
          ),
          const SizedBox(height: 16),
          const Text(
            'Henüz online sipariş yok.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: GcColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'gastro.2hub.ch üzerinden gelen siparişler burada\nlistelenir. Bağlantı Settings → Online Bestellungen.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: GcColors.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderListCard extends ConsumerWidget {
  const _OrderListCard({required this.order});
  final OnlineOrderPayload order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String fmt(int c) => 'CHF ${(c / 100).toStringAsFixed(2)}';
    final typeIcon = switch (order.orderType) {
      'delivery' => Icons.delivery_dining_rounded,
      'takeaway' => Icons.takeout_dining_rounded,
      _ => Icons.restaurant_rounded,
    };
    final typeLabel = switch (order.orderType) {
      'delivery' => 'Lieferung',
      'takeaway' => 'Mitnahme',
      _ => 'Im Haus',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GcColors.surfaceContainerLowest,
        border: Border.all(color: GcColors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(typeIcon, size: 18, color: GcColors.primary),
              const SizedBox(width: 8),
              Text(
                typeLabel,
                style: const TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: GcColors.onSurfaceVariant,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                '#${order.orderNumber.toString().padLeft(4, '0')}',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: GcColors.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            order.customerName ?? 'Gast',
            style: const TextStyle(
              fontFamily: 'WorkSans',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: GcColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${order.items.length} ürün · ${fmt(order.total)}',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: GcColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await rejectOnlineOrder(
                      ref,
                      order.id,
                      'Operator vom Listenbildschirm abgelehnt',
                    );
                  },
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Ablehnen'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    await acceptOnlineOrder(ref, order.id);
                  },
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Annehmen'),
                  style: FilledButton.styleFrom(
                    backgroundColor: GcColors.secondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
