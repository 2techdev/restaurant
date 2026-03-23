/// Ongoing Orders tab content for the Order Center screen.
///
/// Displays active (non-completed, non-cancelled) tickets as a filterable
/// grid of order cards. Each card shows order type, number, guest count,
/// total, waiter, and elapsed time. Tapping a card loads the ticket for
/// editing in the Menu tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/online_orders/presentation/providers/online_order_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';

// ---------------------------------------------------------------------------
// Ongoing Orders Tab
// ---------------------------------------------------------------------------

class OngoingOrdersTab extends ConsumerStatefulWidget {
  /// Called when user taps an order card to edit it in the Menu tab.
  final void Function(TicketEntity ticket) onOrderTap;

  const OngoingOrdersTab({super.key, required this.onOrderTap});

  @override
  ConsumerState<OngoingOrdersTab> createState() => _OngoingOrdersTabState();
}

class _OngoingOrdersTabState extends ConsumerState<OngoingOrdersTab> {
  _OrderFilter _activeFilter = _OrderFilter.all;

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(openTicketsProvider);

    return ColoredBox(
      color: AppColors.surfaceDim,
      child: ticketsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
        error: (err, _) => Center(
          child: Text(
            'Error: $err',
            style: const TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
        ),
        data: (tickets) {
          final filtered = _applyFilter(tickets);
          final allCount = tickets.length;
          final dineInCount =
              tickets.where((t) => t.orderType == OrderType.dineIn).length;
          final takeawayCount =
              tickets.where((t) => t.orderType == OrderType.takeaway).length;
          final deliveryCount =
              tickets.where((t) => t.orderType == OrderType.delivery).length;
          final onlineCount = tickets
              .where((t) =>
                  t.orderType == OrderType.online ||
                  t.channel == OrderChannel.web ||
                  t.channel == OrderChannel.qr)
              .length;

          // Pending online orders count for the badge.
          final pendingOnline = ref.watch(pendingOnlineOrdersProvider).length;

          return Column(
            children: [
              // -- Filter chips --
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip(
                        'All',
                        allCount,
                        _OrderFilter.all,
                        AppColors.accent,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Dine In',
                        dineInCount,
                        _OrderFilter.dineIn,
                        AppColors.green,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Takeaway',
                        takeawayCount,
                        _OrderFilter.takeaway,
                        AppColors.accent,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Delivery',
                        deliveryCount,
                        _OrderFilter.delivery,
                        AppColors.purple,
                      ),
                      const SizedBox(width: 8),
                      _buildOnlineFilterChip(
                        onlineCount,
                        pendingOnline,
                      ),
                    ],
                  ),
                ),
              ),

              // -- Order grid --
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(openTicketsProvider);
                        },
                        color: AppColors.accent,
                        backgroundColor: AppColors.surfaceContainer,
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 280,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.3,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            return _OrderCard(
                              ticket: filtered[index],
                              onTap: () => widget.onOrderTap(filtered[index]),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<TicketEntity> _applyFilter(List<TicketEntity> tickets) {
    switch (_activeFilter) {
      case _OrderFilter.all:
        return tickets;
      case _OrderFilter.dineIn:
        return tickets
            .where((t) => t.orderType == OrderType.dineIn)
            .toList();
      case _OrderFilter.takeaway:
        return tickets
            .where((t) => t.orderType == OrderType.takeaway)
            .toList();
      case _OrderFilter.delivery:
        return tickets
            .where((t) => t.orderType == OrderType.delivery)
            .toList();
      case _OrderFilter.online:
        return tickets
            .where((t) =>
                t.orderType == OrderType.online ||
                t.channel == OrderChannel.web ||
                t.channel == OrderChannel.qr)
            .toList();
    }
  }

  Widget _buildFilterChip(
    String label,
    int count,
    _OrderFilter filter,
    Color color,
  ) {
    final isActive = _activeFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.15) : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? color : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? color.withValues(alpha: 0.2)
                    : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isActive ? color : AppColors.textDim,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Filter chip with an optional red dot badge for pending online orders.
  Widget _buildOnlineFilterChip(int count, int pendingCount) {
    final isActive = _activeFilter == _OrderFilter.online;
    const color = AppColors.accent;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = _OrderFilter.online),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.15)
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: pendingCount > 0
              ? Border.all(
                  color: color.withValues(alpha: 0.4), width: 1.5)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Online',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? color : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isActive
                        ? color.withValues(alpha: 0.2)
                        : AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isActive ? color : AppColors.textDim,
                    ),
                  ),
                ),
                // Red dot for pending (unacknowledged) orders.
                if (pendingCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 56,
            color: AppColors.surfaceContainerHighest,
          ),
          SizedBox(height: 16),
          Text(
            'Aktif siparis yok',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textDim,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Yeni siparis almak icin Menu sekmesine gecin',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter enum
// ---------------------------------------------------------------------------

enum _OrderFilter { all, dineIn, takeaway, delivery, online }

// ---------------------------------------------------------------------------
// Order Card
// ---------------------------------------------------------------------------

class _OrderCard extends StatefulWidget {
  final TicketEntity ticket;
  final VoidCallback onTap;

  const _OrderCard({required this.ticket, required this.onTap});

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _isPressed = false;

  String _formatCHF(int cents) {
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    return 'CHF $whole.$frac';
  }

  String _formatElapsed(DateTime openedAt) {
    final diff = DateTime.now().difference(openedAt);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'now';
  }

  Color _typeBadgeColor(OrderType type) {
    switch (type) {
      case OrderType.dineIn:
        return AppColors.green;
      case OrderType.takeaway:
        return AppColors.accent;
      case OrderType.delivery:
        return AppColors.purple;
      case OrderType.online:
        return AppColors.yellow;
    }
  }

  String _typeLabel(OrderType type) {
    switch (type) {
      case OrderType.dineIn:
        return 'Dine In';
      case OrderType.takeaway:
        return 'Takeaway';
      case OrderType.delivery:
        return 'Delivery';
      case OrderType.online:
        return 'Online';
    }
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final badgeColor = _typeBadgeColor(t.orderType);

    final isOnlineOrder = t.channel == OrderChannel.web ||
        t.channel == OrderChannel.qr ||
        t.orderType == OrderType.online;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _isPressed
              ? AppColors.surfaceBright
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: isOnlineOrder
              ? Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3), width: 1.5)
              : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type badge + optional ONLINE tag + elapsed time
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    _typeLabel(t.orderType),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: badgeColor,
                    ),
                  ),
                ),
                if (isOnlineOrder) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      'ONLINE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  _formatElapsed(t.openedAt),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Order number
            Text(
              '#${t.orderNumber}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),

            // Guest count
            Row(
              children: [
                const Icon(
                  Icons.people_outline_rounded,
                  size: 14,
                  color: AppColors.textDim,
                ),
                const SizedBox(width: 4),
                Text(
                  '${t.guestCount}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${t.items.length} items',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
            const Spacer(),

            // Total + waiter
            Row(
              children: [
                Text(
                  _formatCHF(t.total),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withValues(alpha: 0.15),
                  ),
                  child: Center(
                    child: Text(
                      _initials(t.waiterId),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
