/// Waiter order screen — combines the order ticket view with the menu.
///
/// Layout (phone portrait):
///   Top:    table name + status chip
///   Middle: TabBar → "Menu" tab / "Order" tab
///           Menu tab  = [WaiterMenuScreen] embedded widget
///           Order tab = scrollable list of order items + totals
///   Bottom: "Send to Kitchen" / "Request Bill" action bar
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/waiter/presentation/providers/waiter_provider.dart';
import 'package:gastrocore_pos/features/waiter/presentation/screens/waiter_menu_screen.dart';
import 'package:gastrocore_pos/features/waiter/router/waiter_router.dart';

// ---------------------------------------------------------------------------
// WaiterOrderScreen
// ---------------------------------------------------------------------------

class WaiterOrderScreen extends ConsumerStatefulWidget {
  final String tableId;

  const WaiterOrderScreen({super.key, required this.tableId});

  @override
  ConsumerState<WaiterOrderScreen> createState() => _WaiterOrderScreenState();
}

class _WaiterOrderScreenState extends ConsumerState<WaiterOrderScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _didInit = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      _loadExistingTicket();
    }
  }

  /// If there's already an open ticket for this table, load it.
  Future<void> _loadExistingTicket() async {
    final current = ref.read(waiterActiveTicketProvider);
    if (current != null && current.tableId == widget.tableId) return;

    final svc = ref.read(waiterOrderServiceProvider);
    final tenantId = ref.read(tenantIdProvider);
    final orders = await svc.getOrdersForTable(
      tenantId: tenantId,
      tableId: widget.tableId,
    );
    if (orders.isNotEmpty && mounted) {
      await ref
          .read(waiterActiveTicketProvider.notifier)
          .loadTicket(orders.first.id);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = ref.watch(waiterActiveTicketProvider);
    final tablesAsync = ref.watch(waiterAllTablesProvider);

    final tableName = tablesAsync.when(
      data: (tables) {
        final t = tables.where((t) => t.id == widget.tableId).firstOrNull;
        return t?.name ?? 'Table';
      },
      loading: () => 'Table',
      error: (_, __) => 'Table',
    );

    final itemCount = ticket?.itemCount ?? 0;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.go(WaiterRoutes.tables),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tableName,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            if (ticket != null)
              Text(
                'Order #${ticket.orderNumber}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        actions: [
          // Quick order status badge
          if (ticket != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _StatusChip(status: ticket.status),
            ),
          if (ticket != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
              onSelected: (key) {
                if (key == 'transfer') _openTransferSheet(ticket);
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem<String>(
                  value: 'transfer',
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz_outlined,
                          size: 18, color: AppColors.textPrimary),
                      SizedBox(width: 8),
                      Text('Move to another table'),
                    ],
                  ),
                ),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700),
          tabs: [
            const Tab(text: 'Menu'),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Order'),
                  if (itemCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$itemCount',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.surfaceDim,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Menu tab ──────────────────────────────────────────────────────
          const WaiterMenuScreen(),
          // ── Order tab ─────────────────────────────────────────────────────
          _OrderTab(ticket: ticket),
        ],
      ),
      // ── Action bar ───────────────────────────────────────────────────────
      bottomNavigationBar: _ActionBar(
        ticket: ticket,
        onSendToKitchen: _sendToKitchen,
        onRequestBill: _requestBill,
        onMarkServed: _markServed,
        onSplitBill: ticket != null ? () => _splitBill(ticket) : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _sendToKitchen() async {
    final notifier = ref.read(waiterActiveTicketProvider.notifier);
    await notifier.sendToKitchen();
    if (mounted) {
      _tabController.animateTo(1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order sent to kitchen!',
              style: TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _requestBill() async {
    await ref.read(waiterActiveTicketProvider.notifier).requestBill();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bill requested — POS will handle payment'),
          backgroundColor: AppColors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _splitBill(TicketEntity ticket) {
    context.push(WaiterRoutes.splitBillFor(ticket.id));
  }

  Future<void> _markServed() async {
    await ref.read(waiterActiveTicketProvider.notifier).markServed();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order marked as served'),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openTransferSheet(TicketEntity ticket) async {
    final tables = ref.read(waiterAllTablesProvider).valueOrNull ?? const [];
    final candidates = tables
        .where((t) => t.id != ticket.tableId)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final selected = await showModalBottomSheet<RestaurantTableEntity>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Move order to another table',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                if (candidates.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'No other tables available',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textDim),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (_, i) {
                        final t = candidates[i];
                        final isOccupied = t.status == TableStatus.occupied;
                        return ListTile(
                          leading: Icon(
                            Icons.table_restaurant_outlined,
                            color: isOccupied
                                ? AppColors.orange
                                : AppColors.primary,
                          ),
                          title: Text(
                            t.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            isOccupied ? 'Occupied' : 'Available',
                            style: TextStyle(
                              fontSize: 11,
                              color: isOccupied
                                  ? AppColors.orange
                                  : AppColors.textDim,
                            ),
                          ),
                          onTap: () => Navigator.of(ctx).pop(t),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) return;

    if (selected.status == TableStatus.occupied) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Move to occupied table?'),
          content: Text(
            '${selected.name} already has an active order. Moving this '
            'order there will merge it visually but keep tickets separate.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Move anyway'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    await ref
        .read(waiterActiveTicketProvider.notifier)
        .transferToTable(selected);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moved to ${selected.name}'),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Navigate the screen to track the new table so subsequent rebuilds
      // key off the correct tableId.
      context.go(WaiterRoutes.orderFor(selected.id));
    }
  }
}

// ---------------------------------------------------------------------------
// Order tab
// ---------------------------------------------------------------------------

class _OrderTab extends ConsumerWidget {
  final TicketEntity? ticket;

  const _OrderTab({required this.ticket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ticket == null || ticket!.items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 64, color: AppColors.textDim),
            SizedBox(height: 16),
            Text(
              'No items yet',
              style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textDim,
                  fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Switch to Menu to add products',
              style: TextStyle(fontSize: 13, color: AppColors.textDim),
            ),
          ],
        ),
      );
    }

    // Group items by gang number so fine-dining service reads as
    // Gang 1 / Gang 2 / Gang 3 blocks.
    final grouped = <int, List<OrderItemEntity>>{};
    for (final item in ticket!.items) {
      grouped.putIfAbsent(item.course, () => []).add(item);
    }
    final gangNumbers = grouped.keys.toList()..sort();

    return Column(
      children: [
        // Items list (grouped by gang)
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: gangNumbers.length,
            itemBuilder: (context, index) {
              final gangNum = gangNumbers[index];
              final items = grouped[gangNum]!;
              final hasUnsent = items.any((i) => !i.sentToKitchen);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CourseHeader(
                    courseNumber: gangNum,
                    itemCount: items.length,
                    hasUnsent: hasUnsent,
                    onFire: hasUnsent
                        ? () => ref
                            .read(waiterActiveTicketProvider.notifier)
                            .fireGang(gangNum)
                        : null,
                  ),
                  for (final item in items)
                    _OrderItemRow(
                      item: item,
                      onRemove: () => ref
                          .read(waiterActiveTicketProvider.notifier)
                          .removeItem(item.id),
                    ),
                ],
              );
            },
          ),
        ),
        // Totals summary
        _TotalsSummary(ticket: ticket!),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Course header
// ---------------------------------------------------------------------------

class _CourseHeader extends StatelessWidget {
  final int courseNumber;
  final int itemCount;

  /// `true` if any item in this gang is still unsent. Drives the
  /// Fire-this-gang CTA visibility.
  final bool hasUnsent;

  /// Tapped by the waiter to push just this gang to the kitchen.
  /// `null` disables the button (all items in the gang already fired).
  final VoidCallback? onFire;

  const _CourseHeader({
    required this.courseNumber,
    required this.itemCount,
    this.hasUnsent = false,
    this.onFire,
  });

  String get _label => 'Gang $courseNumber';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: AppColors.accentDim,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$courseNumber',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '· $itemCount',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textDim,
            ),
          ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Divider(color: AppColors.outlineVariant, height: 1),
            ),
          ),
          if (hasUnsent)
            SizedBox(
              height: 28,
              child: TextButton.icon(
                onPressed: onFire,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: AppColors.primary, width: 1),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.local_fire_department_outlined, size: 14),
                label: Text(
                  'Fire Gang $courseNumber',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Fired',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDim,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  final OrderItemEntity item;
  final VoidCallback onRemove;

  const _OrderItemRow({required this.item, required this.onRemove});

  String _formatPrice(int cents) =>
      'CHF ${(cents / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final isSent = item.sentToKitchen;
    return Dismissible(
      key: Key(item.id),
      direction:
          isSent ? DismissDirection.none : DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.redDim,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.red),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Qty badge
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '×${item.quantity.toInt()}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name + modifiers
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSent
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (item.notes != null && item.notes!.isNotEmpty)
                    Text(
                      item.notes!,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.yellow),
                    ),
                  if (item.modifiers.isNotEmpty)
                    Text(
                      item.modifiers.map((m) => m.modifierName).join(', '),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textDim),
                    ),
                ],
              ),
            ),
            // Price + status
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatPrice(item.subtotal),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (isSent)
                  _StatusPill(status: item.status)
                else
                  const Text(
                    'Swipe to remove',
                    style: TextStyle(fontSize: 9, color: AppColors.textDim),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final OrderItemStatus status;

  const _StatusPill({required this.status});

  Color get _color {
    switch (status) {
      case OrderItemStatus.sent:
        return AppColors.orange;
      case OrderItemStatus.preparing:
        return AppColors.yellow;
      case OrderItemStatus.ready:
        return AppColors.green;
      case OrderItemStatus.served:
        return AppColors.textSecondary;
      default:
        return AppColors.textDim;
    }
  }

  String get _label {
    switch (status) {
      case OrderItemStatus.sent:
        return 'Sent';
      case OrderItemStatus.preparing:
        return 'Cooking';
      case OrderItemStatus.ready:
        return 'Ready';
      case OrderItemStatus.served:
        return 'Served';
      default:
        return status.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Totals summary
// ---------------------------------------------------------------------------

class _TotalsSummary extends ConsumerWidget {
  final TicketEntity ticket;

  const _TotalsSummary({required this.ticket});

  String _fmt(int cents) => 'CHF ${(cents / 100).toStringAsFixed(2)}';

  /// Compute the service charge in cents from the current tax-inclusive
  /// subtotal. Returns `0` when the toggle is off.
  int _computeServiceCharge({
    required bool enabled,
    required double percent,
    required int subtotalCents,
  }) {
    if (!enabled || percent <= 0 || subtotalCents <= 0) return 0;
    return (subtotalCents * percent / 100).round();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(restaurantSettingsProvider).valueOrNull;
    final serviceChargeEnabled = settings?.serviceChargeEnabled ?? false;
    final serviceChargePercent = settings?.serviceChargePercent ?? 0;
    final serviceCharge = _computeServiceCharge(
      enabled: serviceChargeEnabled,
      percent: serviceChargePercent,
      subtotalCents: ticket.subtotal,
    );
    final displayTotal = ticket.total + serviceCharge;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      color: AppColors.surfaceContainerLow,
      child: Column(
        children: [
          _TotalRow(label: 'Subtotal (incl. VAT)', value: _fmt(ticket.subtotal)),
          const SizedBox(height: 4),
          _TotalRow(
              label: 'VAT',
              value: _fmt(ticket.taxAmount),
              valueColor: AppColors.textSecondary),
          if (serviceChargeEnabled && serviceCharge > 0) ...[
            const SizedBox(height: 4),
            _TotalRow(
              label:
                  'Service charge (${serviceChargePercent.toStringAsFixed(serviceChargePercent.truncateToDouble() == serviceChargePercent ? 0 : 1)}%)',
              value: _fmt(serviceCharge),
              valueColor: AppColors.textSecondary,
            ),
          ],
          const Divider(color: AppColors.outlineVariant, height: 20),
          _TotalRow(
            label: 'Total',
            value: _fmt(displayTotal),
            labelStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
            valueStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  const _TotalRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.labelStyle,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: labelStyle ??
              const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: valueStyle ??
              TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.textPrimary,
              ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status chip
// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  final TicketStatus status;

  const _StatusChip({required this.status});

  Color get _color {
    switch (status) {
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

  String get _label {
    switch (status) {
      case TicketStatus.draft:
        return 'Draft';
      case TicketStatus.open:
        return 'Open';
      case TicketStatus.sent:
        return 'In Kitchen';
      case TicketStatus.inProgress:
        return 'Cooking';
      case TicketStatus.ready:
        return 'Ready';
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
            fontSize: 11, fontWeight: FontWeight.w700, color: _color),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action bar
// ---------------------------------------------------------------------------

class _ActionBar extends StatelessWidget {
  final TicketEntity? ticket;
  final VoidCallback onSendToKitchen;
  final VoidCallback onRequestBill;
  final VoidCallback onMarkServed;
  final VoidCallback? onSplitBill;

  const _ActionBar({
    required this.ticket,
    required this.onSendToKitchen,
    required this.onRequestBill,
    required this.onMarkServed,
    this.onSplitBill,
  });

  bool get _hasUnsent =>
      ticket != null &&
      ticket!.items.any((i) => !i.sentToKitchen);

  bool get _canBill =>
      ticket != null &&
      (ticket!.status == TicketStatus.sent ||
          ticket!.status == TicketStatus.inProgress ||
          ticket!.status == TicketStatus.ready ||
          ticket!.status == TicketStatus.served);

  bool get _canMarkServed =>
      ticket != null && ticket!.status == TicketStatus.ready;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;

    if (ticket == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + safeBottom),
      color: AppColors.surface,
      child: Row(
        children: [
          if (_hasUnsent) ...[
            Expanded(
              flex: 3,
              child: _ActionButton(
                label: 'Send to Kitchen',
                icon: Icons.send_outlined,
                color: AppColors.orange,
                onTap: onSendToKitchen,
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (_canMarkServed) ...[
            Expanded(
              flex: 2,
              child: _ActionButton(
                label: 'Mark Served',
                icon: Icons.check_circle_outline,
                color: AppColors.green,
                onTap: onMarkServed,
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (_canBill) ...[
            Expanded(
              flex: 2,
              child: _ActionButton(
                label: 'Request Bill',
                icon: Icons.receipt_outlined,
                color: AppColors.purple,
                onTap: onRequestBill,
              ),
            ),
            if (onSplitBill != null) ...[
              const SizedBox(width: 10),
              _ActionButton(
                label: 'Split',
                icon: Icons.call_split_outlined,
                color: AppColors.yellow,
                onTap: onSplitBill!,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
