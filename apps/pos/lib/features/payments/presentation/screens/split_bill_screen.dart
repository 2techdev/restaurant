/// Split Bill Screen — seat-first split payment.
///
/// Three modes, matching Sprint 2 P0.2:
///  - **By Seat** (default): uses [SeatSplitCalculator] to derive a
///    per-seat share from each item's [OrderItemEntity.seatNumber].
///    Unassigned items are pooled and divided equally, with any penny
///    remainder landing on seat 1 so the sum never drifts.
///  - **By Item**: each line is paid individually; running balance tracks
///    what's still outstanding.
///  - **Custom Amount**: waiter types an ad-hoc tender; remainder stays
///    on the ticket for the next round.
///
/// The seat-first split is the Gastrocore delta over SambaPOS-3 — there
/// is no seat concept in SambaPOS, but fine-dining service needs per-seat
/// totals *before* a single payment is tendered.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/payments/domain/services/seat_split_calculator.dart';

// ---------------------------------------------------------------------------
// Split Bill Screen
// ---------------------------------------------------------------------------

class SplitBillScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const SplitBillScreen({super.key, required this.ticketId});

  @override
  ConsumerState<SplitBillScreen> createState() => _SplitBillScreenState();
}

enum _SplitMode { seat, item, amount, percent }

class _SplitBillScreenState extends ConsumerState<SplitBillScreen> {
  _SplitMode _mode = _SplitMode.seat;

  /// Seats already settled (by seat number, 1-based).
  final Set<int> _paidSeats = <int>{};

  /// Items already settled (by item id).
  final Set<String> _paidItems = <String>{};

  /// Tenders collected under the Custom Amount tab, in cents.
  final List<int> _customTenders = <int>[];
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _percentController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _percentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticketAsync = ref.watch(ticketByIdProvider(widget.ticketId));
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: ticketAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text('Fiş yüklenemedi: $err',
              style: const TextStyle(color: AppColors.red)),
        ),
        data: (ticket) {
          if (ticket == null) {
            return const Center(
              child: Text('Fiş bulunamadı',
                  style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return _buildBody(ticket);
        },
      ),
    );
  }

  Widget _buildBody(TicketEntity ticket) {
    return Column(
      children: [
        _buildHeader(ticket),
        _buildTabSelector(),
        Expanded(child: _buildContent(ticket)),
        _buildFooter(ticket),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Header
  // -------------------------------------------------------------------------

  Widget _buildHeader(TicketEntity ticket) {
    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      color: AppColors.surfaceContainerHigh,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.arrow_back,
                  color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 24),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hesabı Böl',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                _subheader(ticket),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'KALAN BAKİYE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 2.0,
                ),
              ),
              Text(
                _formatCHF(_outstanding(ticket)),
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  letterSpacing: -2.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _subheader(TicketEntity ticket) {
    final parts = <String>[
      'FİŞ #${ticket.orderNumber}',
      '${ticket.guestCount} KİŞİ',
    ];
    if (ticket.tableId != null) {
      parts.insert(0, 'MASA ${ticket.tableId}');
    }
    return parts.join('  \u2014  ');
  }

  // -------------------------------------------------------------------------
  // Tab selector
  // -------------------------------------------------------------------------

  Widget _buildTabSelector() {
    const labels = ['Koltuk', 'Ürün', 'Tutar', 'Yüzde'];
    const modes = [
      _SplitMode.seat,
      _SplitMode.item,
      _SplitMode.amount,
      _SplitMode.percent,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(labels.length, (i) {
              final isActive = _mode == modes[i];
              return GestureDetector(
                key: Key('split_tab_${modes[i].name}'),
                onTap: () => setState(() => _mode = modes[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 12),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.surfaceContainerHigh
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 12),
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(TicketEntity ticket) {
    switch (_mode) {
      case _SplitMode.seat:
        return _buildSeatMode(ticket);
      case _SplitMode.item:
        return _buildItemMode(ticket);
      case _SplitMode.amount:
        return _buildAmountMode(ticket);
      case _SplitMode.percent:
        return _buildPercentMode(ticket);
    }
  }

  // -------------------------------------------------------------------------
  // Seat mode
  // -------------------------------------------------------------------------

  Widget _buildSeatMode(TicketEntity ticket) {
    final seatCount =
        ticket.guestCount.clamp(1, 99); // guestCount defaults to 1
    final result =
        SeatSplitCalculator.split(ticket, seatCount: seatCount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
      child: ListView.builder(
        itemCount: seatCount + (result.unassignedItems.isNotEmpty ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == seatCount) {
            return _buildUnassignedCard(result.unassignedItems);
          }
          final seat = index + 1;
          final share = result.shareBySeat[seat] ?? 0;
          final items = result.itemsBySeat[seat] ?? const <OrderItemEntity>[];
          final isPaid = _paidSeats.contains(seat);
          return _buildSeatCard(seat, share, items, isPaid);
        },
      ),
    );
  }

  Widget _buildSeatCard(
      int seat, int share, List<OrderItemEntity> items, bool isPaid) {
    return Container(
      key: Key('seat_card_$seat'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isPaid
            ? AppColors.green.withValues(alpha: 0.05)
            : AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: isPaid
            ? const Border(
                left: BorderSide(color: AppColors.green, width: 4))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPaid
                  ? AppColors.green.withValues(alpha: 0.2)
                  : AppColors.surfaceContainer,
            ),
            child: Center(
              child: isPaid
                  ? const Icon(Icons.check, color: AppColors.green)
                  : Text(
                      '$seat',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryLight,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Koltuk ${seat.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                if (items.isEmpty)
                  const Text(
                    'Atanmış ürün yok',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  )
                else
                  Text(
                    items
                        .map((i) => '${i.quantity.toStringAsFixed(0)}× '
                            '${i.productName}')
                        .join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatCHF(share),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              if (isPaid)
                const Text(
                  'Ödendi',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.green,
                      fontWeight: FontWeight.w700),
                )
              else
                GestureDetector(
                  key: Key('settle_seat_$seat'),
                  onTap: () => setState(() => _paidSeats.add(seat)),
                  child: const Text(
                    'Tahsil Et',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryLight,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnassignedCard(List<OrderItemEntity> items) {
    final total = items.fold<int>(0, (s, i) => s + i.subtotal);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.group, color: AppColors.textSecondary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Koltuksuz (eşit dağıtıldı)',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '${items.length} ürün',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            _formatCHF(total),
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Item mode
  // -------------------------------------------------------------------------

  Widget _buildItemMode(TicketEntity ticket) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
      child: ListView.builder(
        itemCount: ticket.items.length,
        itemBuilder: (context, index) {
          final item = ticket.items[index];
          final isPaid = _paidItems.contains(item.id);
          return Container(
            key: Key('item_row_${item.id}'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isPaid
                  ? AppColors.green.withValues(alpha: 0.05)
                  : AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: isPaid
                  ? const Border(
                      left:
                          BorderSide(color: AppColors.green, width: 4))
                  : null,
            ),
            child: Row(
              children: [
                if (item.seatNumber != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#${item.seatNumber}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryLight),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.quantity.toStringAsFixed(0)}× '
                        '${item.productName}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (item.notes != null && item.notes!.isNotEmpty)
                        Text(
                          item.notes!,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                Text(
                  _formatCHF(item.subtotal),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: isPaid
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 16),
                if (isPaid)
                  const Icon(Icons.check_circle, color: AppColors.green)
                else
                  GestureDetector(
                    key: Key('settle_item_${item.id}'),
                    onTap: () =>
                        setState(() => _paidItems.add(item.id)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Tahsil',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryLight),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Amount mode
  // -------------------------------------------------------------------------

  Widget _buildAmountMode(TicketEntity ticket) {
    final outstanding = _outstanding(ticket);
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('split_amount_field'),
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.,]')),
                    ],
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: '0.00',
                      hintStyle: TextStyle(color: AppColors.textDim),
                      prefixText: 'CHF  ',
                      prefixStyle: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  key: const Key('split_amount_add'),
                  onPressed: outstanding > 0
                      ? () => _addCustomTender(outstanding)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Ekle',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Tahsil edilenler',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary
                    .withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 8),
          if (_customTenders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Henüz tutar eklenmedi.',
                  style:
                      TextStyle(color: AppColors.textDim, fontSize: 13)),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _customTenders.length,
                itemBuilder: (context, index) {
                  final cents = _customTenders[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Text('Tender #${index + 1}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        const Spacer(),
                        Text(_formatCHF(cents),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary)),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: AppColors.textSecondary,
                          onPressed: () => setState(
                              () => _customTenders.removeAt(index)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _addCustomTender(int outstanding) {
    final raw = _amountController.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) return;
    final cents = (parsed * 100).round();
    if (cents <= 0) return;
    final capped = cents.clamp(0, outstanding);
    setState(() {
      _customTenders.add(capped);
      _amountController.clear();
    });
  }

  // -------------------------------------------------------------------------
  // Percent mode
  // -------------------------------------------------------------------------

  Widget _buildPercentMode(TicketEntity ticket) {
    final outstanding = _outstanding(ticket);
    final raw = _percentController.text.trim().replaceAll(',', '.');
    final parsedPercent = double.tryParse(raw);
    final previewCents = (parsedPercent != null && parsedPercent > 0)
        ? (ticket.total * parsedPercent / 100).round()
        : 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('split_percent_field'),
                        controller: _percentController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]')),
                        ],
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          hintText: '0',
                          hintStyle: TextStyle(color: AppColors.textDim),
                          labelText: 'Yüzde (%)',
                          labelStyle: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700),
                          suffixText: '%',
                          suffixStyle: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      key: const Key('split_percent_add'),
                      onPressed:
                          outstanding > 0 && previewCents > 0
                              ? () => _addPercentTender(
                                  ticket.total, outstanding)
                              : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Tenderle',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Tutar: ${_formatCHF(previewCents)}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Tahsil edilenler',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 8),
          if (_customTenders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Henüz yüzde eklenmedi.',
                  style:
                      TextStyle(color: AppColors.textDim, fontSize: 13)),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _customTenders.length,
                itemBuilder: (context, index) {
                  final cents = _customTenders[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Text('Tender #${index + 1}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        const Spacer(),
                        Text(_formatCHF(cents),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary)),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: AppColors.textSecondary,
                          onPressed: () => setState(
                              () => _customTenders.removeAt(index)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _addPercentTender(int ticketTotal, int outstanding) {
    final raw = _percentController.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) return;
    final cents = (ticketTotal * parsed / 100).round();
    if (cents <= 0) return;
    final capped = cents.clamp(0, outstanding);
    setState(() {
      _customTenders.add(capped);
      _percentController.clear();
    });
  }

  // -------------------------------------------------------------------------
  // Footer
  // -------------------------------------------------------------------------

  Widget _buildFooter(TicketEntity ticket) {
    final outstanding = _outstanding(ticket);
    final settled = ticket.total - outstanding;
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TAHSIL EDILEN',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5)),
              Text(
                _formatCHF(settled),
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.green),
              ),
            ],
          ),
          const SizedBox(width: 32),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('KALAN',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5)),
              Text(
                _formatCHF(outstanding),
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            key: const Key('split_reset'),
            onTap: () => setState(() {
              _paidSeats.clear();
              _paidItems.clear();
              _customTenders.clear();
              _amountController.clear();
              _percentController.clear();
            }),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.undo, color: AppColors.textPrimary),
                  SizedBox(width: 8),
                  Text('Sıfırla',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            key: const Key('split_settle_all'),
            onTap: outstanding == 0 ? () => context.pop() : null,
            child: Opacity(
              opacity: outstanding == 0 ? 1.0 : 0.5,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryLight, AppColors.primary],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Text('Hesabı Kapat',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                    SizedBox(width: 12),
                    Icon(Icons.payments, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  int _outstanding(TicketEntity ticket) {
    int settled = 0;
    switch (_mode) {
      case _SplitMode.seat:
        final result = SeatSplitCalculator.split(ticket,
            seatCount: ticket.guestCount.clamp(1, 99));
        for (final seat in _paidSeats) {
          settled += result.shareBySeat[seat] ?? 0;
        }
      case _SplitMode.item:
        for (final item in ticket.items) {
          if (_paidItems.contains(item.id)) settled += item.subtotal;
        }
      case _SplitMode.amount:
        settled = _customTenders.fold<int>(0, (s, v) => s + v);
      case _SplitMode.percent:
        settled = _customTenders.fold<int>(0, (s, v) => s + v);
    }
    final remaining = ticket.total - settled;
    return remaining < 0 ? 0 : remaining;
  }

  String _formatCHF(int cents) {
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return 'CHF $whole.$frac';
  }
}
