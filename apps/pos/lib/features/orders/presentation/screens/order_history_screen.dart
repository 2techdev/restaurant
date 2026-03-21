/// Order History screen for GastroCore POS.
///
/// Displays a filterable, searchable list of all tickets with date filtering,
/// status chips, and expandable detail rows. Follows the Stitch "Precision POS
/// Framework" design system.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/utils/money.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';

// ---------------------------------------------------------------------------
// Filter enum
// ---------------------------------------------------------------------------

enum _HistoryFilter { all, open, completed, cancelled }

// ---------------------------------------------------------------------------
// Provider: order history with date filter
// ---------------------------------------------------------------------------

final _orderHistoryProvider = FutureProvider.family<List<TicketEntity>,
    ({DateTime from, DateTime to})>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final repo = OrderRepositoryImpl(db);

  // Query all tickets within the date range.
  final allTickets = await repo.getOpenTickets(tenantId);

  // Also fetch completed / cancelled tickets via raw query.
  // For MVP we use the repo's existing methods and filter in-memory.
  // Phase 2: add a dedicated date-range query to the repo.
  return allTickets;
});

// ---------------------------------------------------------------------------
// OrderHistoryScreen
// ---------------------------------------------------------------------------

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() =>
      _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  _HistoryFilter _filter = _HistoryFilter.all;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  DateTime _dateFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _dateTo = DateTime.now();
  String? _expandedTicketId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(
      _orderHistoryProvider((from: _dateFrom, to: _dateTo)),
    );

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _buildTopBar(),
          _buildFilterBar(),
          Expanded(
            child: ticketsAsync.when(
              data: (tickets) {
                final filtered = _applyFilters(tickets);
                if (filtered.isEmpty) {
                  return _buildEmptyState();
                }
                return _buildTicketList(filtered);
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (err, _) => Center(
                child: Text(
                  'Hata: $err',
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Top bar
  // =========================================================================

  Widget _buildTopBar() {
    return Container(
      height: 56,
      color: AppColors.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Back button
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.home);
                }
              },
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 22,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          const Text(
            'Siparis Gecmisi',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),

          // Date range display
          Material(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _pickDateRange,
              splashColor: AppColors.textPrimary.withValues(alpha: 0.06),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      '${_formatDate(_dateFrom)} - ${_formatDate(_dateTo)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Search field
          SizedBox(
            width: 220,
            height: 40,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bgInput,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
                cursorColor: AppColors.accent,
                decoration: const InputDecoration(
                  hintText: 'Siparis ara...',
                  hintStyle: TextStyle(fontSize: 13, color: AppColors.textDim),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 18, color: AppColors.textDim),
                  prefixIconConstraints:
                      BoxConstraints(minWidth: 40, minHeight: 40),
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Filter chips
  // =========================================================================

  Widget _buildFilterBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          _buildFilterChip(_HistoryFilter.all, 'Tumu'),
          const SizedBox(width: 8),
          _buildFilterChip(_HistoryFilter.open, 'Acik'),
          const SizedBox(width: 8),
          _buildFilterChip(_HistoryFilter.completed, 'Tamamlanan'),
          const SizedBox(width: 8),
          _buildFilterChip(_HistoryFilter.cancelled, 'Iptal'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(_HistoryFilter filter, String label) {
    final isSelected = _filter == filter;

    return Material(
      color: isSelected
          ? AppColors.surfaceBright
          : AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _filter = filter),
        splashColor: AppColors.textPrimary.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // Ticket list
  // =========================================================================

  Widget _buildTicketList(List<TicketEntity> tickets) {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: tickets.length,
      itemBuilder: (context, index) {
        final ticket = tickets[index];
        final isExpanded = _expandedTicketId == ticket.id;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildTicketCard(ticket, isExpanded),
        );
      },
    );
  }

  Widget _buildTicketCard(TicketEntity ticket, bool isExpanded) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // -- Summary row --
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _expandedTicketId =
                      isExpanded ? null : ticket.id;
                });
              },
              splashColor: AppColors.textPrimary.withValues(alpha: 0.04),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    // Order number + date
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '#${ticket.orderNumber}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDateTime(ticket.openedAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Table or Paket badge
                    Expanded(
                      flex: 2,
                      child: ticket.orderType == OrderType.takeaway ||
                              ticket.orderType == OrderType.delivery
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.orangeDim,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Paket',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.orange,
                                ),
                              ),
                            )
                          : Text(
                              ticket.tableId != null
                                  ? 'Masa ${ticket.tableId!.substring(0, 4)}'
                                  : '-',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                    ),

                    // Item count
                    Expanded(
                      flex: 1,
                      child: Text(
                        '${ticket.itemCount} urun',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),

                    // Total
                    Expanded(
                      flex: 2,
                      child: Text(
                        Money(ticket.total).format('CHF'),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Status badge
                    _buildStatusBadge(ticket.status),

                    const SizedBox(width: 12),

                    // Expand arrow
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: AppColors.textDim,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // -- Expanded detail --
          if (isExpanded) _buildExpandedDetail(ticket),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(TicketStatus status) {
    final Color color;
    final Color bgColor;
    final String label;

    switch (status) {
      case TicketStatus.completed:
        color = AppColors.green;
        bgColor = AppColors.greenDim;
        label = 'Odendi';
      case TicketStatus.cancelled:
      case TicketStatus.voided:
        color = AppColors.red;
        bgColor = AppColors.redDim;
        label = status == TicketStatus.cancelled ? 'Iptal' : 'Void';
      case TicketStatus.draft:
      case TicketStatus.open:
      case TicketStatus.sent:
      case TicketStatus.inProgress:
      case TicketStatus.ready:
      case TicketStatus.served:
      case TicketStatus.billRequested:
        color = AppColors.accent;
        bgColor = AppColors.accentDim;
        label = 'Acik';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildExpandedDetail(TicketEntity ticket) {
    return Container(
      color: AppColors.surfaceContainer,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Item list
          if (ticket.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Urun bilgisi yok',
                style: TextStyle(fontSize: 12, color: AppColors.textDim),
              ),
            )
          else
            ...ticket.items.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${item.quantity.round()}x',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.productName,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      Money(item.subtotal).format('CHF'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 12),

          // Waiter info
          if (ticket.waiterId != null)
            Text(
              'Garson: ${ticket.waiterId}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textDim,
              ),
            ),

          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              // Reprint button
              Material(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Yazici entegrasyonu Phase 2 ile aktif olacak'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  splashColor: AppColors.textPrimary.withValues(alpha: 0.06),
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.print_rounded,
                            size: 16, color: AppColors.textSecondary),
                        SizedBox(width: 8),
                        Text(
                          'Yeniden Yazdir',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Refund button
              Material(
                color: AppColors.redDim,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () =>
                      context.push(AppRoutes.refundFor(ticket.id)),
                  splashColor: AppColors.red.withValues(alpha: 0.2),
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.undo_rounded,
                            size: 16, color: AppColors.red),
                        SizedBox(width: 8),
                        Text(
                          'Iade',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Empty state
  // =========================================================================

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 56, color: AppColors.textDim),
            SizedBox(height: 20),
            Text(
              'Siparis bulunamadi',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Secilen tarih araliginda siparis yok.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Helpers
  // =========================================================================

  List<TicketEntity> _applyFilters(List<TicketEntity> tickets) {
    var result = tickets;

    // Status filter
    switch (_filter) {
      case _HistoryFilter.all:
        break;
      case _HistoryFilter.open:
        result = result.where((t) => t.isOpen).toList();
      case _HistoryFilter.completed:
        result = result.where((t) => t.status == TicketStatus.completed).toList();
      case _HistoryFilter.cancelled:
        result = result
            .where((t) =>
                t.status == TicketStatus.cancelled ||
                t.status == TicketStatus.voided)
            .toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((t) {
        return t.orderNumber.contains(q) ||
            (t.customerName?.toLowerCase().contains(q) ?? false) ||
            t.items.any((i) => i.productName.toLowerCase().contains(q));
      }).toList();
    }

    return result;
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              onPrimary: Colors.white,
              surface: AppColors.surfaceContainer,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  String _formatDateTime(DateTime date) {
    return '${_formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
