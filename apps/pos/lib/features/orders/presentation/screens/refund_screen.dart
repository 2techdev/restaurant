/// Refund (İade) Screen for GastroCore POS.
///
/// Two-column layout: original order items (left) and refund summary (right).
/// Supports partial (item-level) and full-order refunds with mandatory reason
/// tracking and manager PIN authorisation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart' show ticketByIdProvider;
import 'package:gastrocore_pos/features/overrides/presentation/widgets/manager_pin_dialog.dart';
import 'package:gastrocore_pos/features/payments/data/repositories/refund_repository_impl.dart';
import 'package:gastrocore_pos/features/payments/presentation/providers/refund_provider.dart';

// ---------------------------------------------------------------------------
// RefundScreen
// ---------------------------------------------------------------------------

class RefundScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const RefundScreen({super.key, required this.ticketId});

  @override
  ConsumerState<RefundScreen> createState() => _RefundScreenState();
}

class _RefundScreenState extends ConsumerState<RefundScreen> {
  final Set<String> _selectedIds = {};
  String _selectedReason = kRefundReasons.first;
  String _refundMethod = 'original';
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _customReasonController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    _customReasonController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  List<OrderItemEntity> _refundableItems(TicketEntity ticket) {
    return ticket.items
        .where((i) => i.status != OrderItemStatus.voidStatus)
        .toList();
  }

  List<OrderItemEntity> _selectedItems(List<OrderItemEntity> refundable) {
    return refundable.where((i) => _selectedIds.contains(i.id)).toList();
  }

  int _subtotal(List<OrderItemEntity> items) =>
      items.fold<int>(0, (s, i) => s + i.subtotal);

  int _tax(List<OrderItemEntity> items) =>
      items.fold<int>(0, (s, i) => s + i.taxAmount);

  String _fmt(int cents) {
    final isNeg = cents < 0;
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return '${isNeg ? '-' : ''}$whole.$frac';
  }

  String get _effectiveReason =>
      _selectedReason == 'Diğer' && _customReasonController.text.trim().isNotEmpty
          ? _customReasonController.text.trim()
          : _selectedReason;

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  void _selectAll(List<OrderItemEntity> refundable) {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(refundable.map((i) => i.id));
    });
  }

  void _clearSelection() => setState(() => _selectedIds.clear());

  Future<void> _onSubmitRefund(TicketEntity ticket) async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    final selectedItemsForRefund = _selectedItems(_refundableItems(ticket));
    if (selectedItemsForRefund.isEmpty) return;

    // Show manager PIN dialog.
    final approver = await ManagerPinDialog.show(
      context: context,
      ref: ref,
      operationLabel: 'İade İşlemi — ${selectedItemsForRefund.length} kalem',
    );
    if (approver == null || !mounted) return;

    final ok = await ref.read(refundOperationProvider.notifier).processRefund(
          ticketId: ticket.id,
          orderItemIds: _selectedIds.toList(),
          reason: _effectiveReason,
          refundMethod: _refundMethod,
          requestedBy: currentUser,
          approvedBy: approver,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );

    if (!mounted) return;

    if (ok) {
      final result =
          (ref.read(refundOperationProvider) as RefundSuccess).result;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.green,
          content: Text(
            'İade başarılı: ₺${_fmt(result.refundAmount)}',
            style: const TextStyle(
                color: Color(0xFF003A11), fontWeight: FontWeight.w600),
          ),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) context.go('/order-center');
      });
    } else {
      final failure = ref.read(refundOperationProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            failure is RefundFailure ? failure.message : 'İade başarısız',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ticketAsync = ref.watch(ticketByIdProvider(widget.ticketId));

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: ticketAsync.when(
        data: (ticket) =>
            ticket != null ? _buildBody(ticket) : _buildFallback(),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _buildFallback(),
      ),
    );
  }

  // Fallback when ticket cannot be loaded (e.g. screen opened from deeplink).
  Widget _buildFallback() {
    return Column(
      children: [
        _buildTopBarStatic(),
        const Expanded(
          child: Center(
            child: Text('Sipariş yüklenemedi',
                style: TextStyle(color: AppColors.textDim)),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(TicketEntity ticket) {
    final refundable = _refundableItems(ticket);
    final selected = _selectedItems(refundable);
    final selectedSubtotal = _subtotal(selected);
    final selectedTax = _tax(selected);
    final selectedTotal = selectedSubtotal + selectedTax;

    return Column(
      children: [
        _buildTopBar(ticket),
        Expanded(
          child: Row(
            children: [
              Expanded(
                  child: _buildOriginalOrder(ticket, refundable, selected)),
              Expanded(
                  child: _buildRefundSummary(
                      ticket, selected, selectedSubtotal, selectedTax, selectedTotal)),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Top bar
  // -------------------------------------------------------------------------

  Widget _buildTopBar(TicketEntity ticket) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: AppColors.surface,
      child: Row(
        children: [
          const Text(
            'GastroCore',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            'Refund / İade',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              'Sipariş #${ticket.orderNumber}',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => context.go('/order-center'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded,
                      size: 14, color: AppColors.textSecondary),
                  SizedBox(width: 4),
                  Text('Geri',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBarStatic() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: AppColors.surface,
      child: Row(
        children: [
          const Text('GastroCore',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(width: 16),
          const Text('Refund / İade',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const Spacer(),
          GestureDetector(
            onTap: () => context.go('/order-center'),
            child: const Text('Geri',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Left: original order items
  // -------------------------------------------------------------------------

  Widget _buildOriginalOrder(
    TicketEntity ticket,
    List<OrderItemEntity> refundable,
    List<OrderItemEntity> selected,
  ) {
    return Container(
      color: AppColors.surfaceDim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Orijinal Sipariş',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'Sipariş #${ticket.orderNumber}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateTime(ticket.openedAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Select all / clear
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _chip('Tümünü Seç', () => _selectAll(refundable)),
                const SizedBox(width: 8),
                _chip('Temizle', _clearSelection),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Item list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: refundable.length,
              itemBuilder: (_, i) {
                final item = refundable[i];
                final isSelected = _selectedIds.contains(item.id);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedIds.remove(item.id);
                      } else {
                        _selectedIds.add(item.id);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.redDim
                          : AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.red
                                : AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check_rounded,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              '${item.quantity.toInt()}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.productName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          '₺${_fmt(item.subtotal)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            color: AppColors.surfaceContainerLow,
            child: Row(
              children: [
                Text('${_selectedIds.length} ürün seçildi',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
                const Spacer(),
                Text(
                  '₺${_fmt(_subtotal(selected))}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Right: refund summary
  // -------------------------------------------------------------------------

  Widget _buildRefundSummary(
    TicketEntity ticket,
    List<OrderItemEntity> selected,
    int subtotal,
    int tax,
    int total,
  ) {
    return Container(
      color: AppColors.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'İade Özeti',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),

            // Selected items
            if (selected.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: const Center(
                  child: Text('İade için ürün seçiniz',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textDim)),
                ),
              )
            else
              for (final item in selected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${item.quantity.toInt()}x ${item.productName}',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textPrimary),
                        ),
                      ),
                      Text(
                        '₺${_fmt(item.subtotal)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),

            const SizedBox(height: 16),

            // Totals box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _summaryRow('Ara Toplam', subtotal, false),
                  const SizedBox(height: 6),
                  _summaryRow('KDV', tax, false),
                  const SizedBox(height: 10),
                  _summaryRow('İade Toplam', total, true),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Refund method
            const Text(
              'İade Yöntemi',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _methodChip('Orijinal Yöntem', 'original'),
                const SizedBox(width: 8),
                _methodChip('Nakit', 'cash'),
              ],
            ),
            const SizedBox(height: 24),

            // Reason
            const Text(
              'İade Nedeni',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            ReasonSelector(
              reasons: kRefundReasons,
              selected: _selectedReason,
              onSelected: (r) => setState(() => _selectedReason = r),
            ),

            if (_selectedReason == 'Diğer') ...[
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _customReasonController,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'İade nedenini yazınız...',
                    hintStyle: TextStyle(
                        fontSize: 13, color: AppColors.textDim),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Notes
            const Text(
              'Notlar',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _notesController,
                maxLines: 3,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Ek not ekleyin...',
                  hintStyle:
                      TextStyle(fontSize: 13, color: AppColors.textDim),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Warning
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.orangeDim,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: AppColors.orange),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bu işlem yönetici onayı gerektirir',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.go('/order-center'),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text('İptal',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _selectedIds.isEmpty
                        ? null
                        : () => _onSubmitRefund(ticket),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _selectedIds.isEmpty ? 0.4 : 1.0,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF3B30), Color(0xFFCC2F26)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.replay_rounded,
                                size: 20, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(
                              'İade Et  ₺${_fmt(total)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
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

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Widget _summaryRow(String label, int amount, bool isTotal) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 14 : 12,
            fontWeight: isTotal ? FontWeight.w600 : FontWeight.w400,
            color:
                isTotal ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        Text(
          '₺${_fmt(amount)}',
          style: TextStyle(
            fontSize: isTotal ? 22 : 13,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
            color: isTotal ? AppColors.red : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _methodChip(String label, String value) {
    final isActive = _refundMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _refundMethod = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color:
              isActive ? AppColors.accentDim : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? AppColors.accent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final d = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d  $t';
  }
}
