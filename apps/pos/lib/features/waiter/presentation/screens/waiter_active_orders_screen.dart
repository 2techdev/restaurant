/// Active orders screen — shows all open orders assigned to the current waiter.
///
/// Each order card displays the table name, item count, total, and the
/// current kitchen status. Tap a card to navigate to that order.
/// Pull-to-refresh syncs the list from the database.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/sync/domain/repositories/sync_repository.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/waiter/presentation/providers/waiter_provider.dart';
import 'package:gastrocore_pos/features/waiter/router/waiter_router.dart';

// ---------------------------------------------------------------------------
// WaiterActiveOrdersScreen
// ---------------------------------------------------------------------------

class WaiterActiveOrdersScreen extends ConsumerWidget {
  const WaiterActiveOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(waiterActiveOrdersProvider);
    final tablesAsync = ref.watch(waiterAllTablesProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          'My Orders',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: () => ref.invalidate(waiterActiveOrdersProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          const _PendingSyncPill(),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.surface,
              onRefresh: () async {
                ref.invalidate(waiterActiveOrdersProvider);
                await ref.read(syncProvider.notifier).sync();
              },
              child: ordersAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 48, color: AppColors.red),
                const SizedBox(height: 12),
                Text(e.toString(),
                    style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
          data: (orders) {
            if (orders.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 72, color: AppColors.textDim),
                        SizedBox(height: 16),
                        Text(
                          'No active orders',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDim,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Head to Tables to start a new order',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textDim),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            final tables = tablesAsync.asData?.value ?? const [];

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                final table = tables
                    .where((t) => t.id == order.tableId)
                    .firstOrNull;
                return _OrderCard(
                  order: order,
                  table: table,
                  onTap: () => _openOrder(context, ref, order),
                );
              },
            );
          },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openOrder(
    BuildContext context,
    WidgetRef ref,
    TicketEntity order,
  ) async {
    await ref
        .read(waiterActiveTicketProvider.notifier)
        .loadTicket(order.id);
    if (context.mounted && order.tableId != null) {
      context.go(WaiterRoutes.orderFor(order.tableId!));
    }
  }
}

// ---------------------------------------------------------------------------
// Order card
// ---------------------------------------------------------------------------

class _OrderCard extends StatelessWidget {
  final TicketEntity order;
  final RestaurantTableEntity? table;
  final VoidCallback onTap;

  const _OrderCard({
    required this.order,
    required this.table,
    required this.onTap,
  });

  String _fmt(int cents) => 'CHF ${(cents / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _statusBorderColor.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: table + order number + time ─────────────────────
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _statusBorderColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_statusIcon,
                      color: _statusBorderColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        table?.name ?? 'Table',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Order #${order.orderNumber}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: order.status),
              ],
            ),
            const SizedBox(height: 12),
            // ── Items summary ─────────────────────────────────────────────
            if (order.items.isNotEmpty) ...[
              Text(
                order.items
                    .take(3)
                    .map((i) => '${i.quantity.toInt()}× ${i.productName}')
                    .join(', ') +
                    (order.items.length > 3
                        ? ' +${order.items.length - 3} more'
                        : ''),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
            ],
            // ── Bottom row: item count + total + elapsed time ─────────────
            Row(
              children: [
                _InfoChip(
                  icon: Icons.shopping_bag_outlined,
                  label: '${order.itemCount} items',
                ),
                const SizedBox(width: 8),
                _InfoChip(
                  icon: Icons.access_time,
                  label: _elapsed(order.openedAt),
                ),
                const Spacer(),
                Text(
                  _fmt(order.total),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color get _statusBorderColor {
    switch (order.status) {
      case TicketStatus.draft:
        return AppColors.textDim;
      case TicketStatus.open:
        return AppColors.primary;
      case TicketStatus.sent:
        return AppColors.orange;
      case TicketStatus.inProgress:
        return AppColors.yellow;
      case TicketStatus.ready:
        return AppColors.green;
      case TicketStatus.served:
        return AppColors.textSecondary;
      case TicketStatus.billRequested:
        return AppColors.purple;
      default:
        return AppColors.textDim;
    }
  }

  IconData get _statusIcon {
    switch (order.status) {
      case TicketStatus.sent:
      case TicketStatus.inProgress:
        return Icons.local_fire_department_outlined;
      case TicketStatus.ready:
        return Icons.check_circle_outline;
      case TicketStatus.billRequested:
        return Icons.receipt_outlined;
      default:
        return Icons.table_restaurant_outlined;
    }
  }

  String _elapsed(DateTime openedAt) {
    final diff = DateTime.now().difference(openedAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ${diff.inMinutes % 60}m';
  }
}

// ---------------------------------------------------------------------------
// Status badge
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final TicketStatus status;

  const _StatusBadge({required this.status});

  Color get _color {
    switch (status) {
      case TicketStatus.open:
        return AppColors.primary;
      case TicketStatus.sent:
        return AppColors.orange;
      case TicketStatus.inProgress:
        return AppColors.yellow;
      case TicketStatus.ready:
        return AppColors.green;
      case TicketStatus.served:
        return AppColors.textSecondary;
      case TicketStatus.billRequested:
        return AppColors.purple;
      default:
        return AppColors.textDim;
    }
  }

  String get _label {
    switch (status) {
      case TicketStatus.open:
        return 'Open';
      case TicketStatus.sent:
        return 'In Kitchen';
      case TicketStatus.inProgress:
        return 'Cooking';
      case TicketStatus.ready:
        return 'Ready!';
      case TicketStatus.served:
        return 'Served';
      case TicketStatus.billRequested:
        return 'Bill Req.';
      default:
        return status.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info chip
// ---------------------------------------------------------------------------

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppColors.textDim),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textDim,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pending-sync pill
// ---------------------------------------------------------------------------

/// Surfaces how many orders are still queued locally.
///
/// Sits at the top of the My Orders list so the waiter never has to wonder
/// whether the kitchen has seen their last entry. Tapping "Sync now" kicks
/// the outbox immediately — handy when Wi-Fi just came back and the 5-minute
/// periodic timer hasn't fired yet.
class _PendingSyncPill extends ConsumerWidget {
  const _PendingSyncPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    final pending = sync.pendingCount;
    if (pending == 0) return const SizedBox.shrink();

    final syncing = sync.status == SyncStatus.syncing;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined,
              size: 18, color: AppColors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              pending == 1
                  ? '1 change waiting to sync'
                  : '$pending changes waiting to sync',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: syncing
                ? null
                : () => ref.read(syncProvider.notifier).sync(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.orange,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              syncing ? 'Syncing…' : 'Sync now',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
