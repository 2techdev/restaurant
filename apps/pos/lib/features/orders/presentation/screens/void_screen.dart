/// Void (İptal) Screen — manager-approved order and item cancellation.
///
/// Two-column layout matching the RefundScreen design:
///  - Left:  ticket items, each selectable for partial void.
///  - Right: void summary, reason selection, action buttons.
///
/// Manager PIN is required before the void is committed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/void_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart' show ticketByIdProvider;
import 'package:gastrocore_pos/features/orders/presentation/providers/void_provider.dart';
import 'package:gastrocore_pos/features/overrides/presentation/widgets/manager_pin_dialog.dart';

// ---------------------------------------------------------------------------
// VoidScreen
// ---------------------------------------------------------------------------

class VoidScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const VoidScreen({super.key, required this.ticketId});

  @override
  ConsumerState<VoidScreen> createState() => _VoidScreenState();
}

class _VoidScreenState extends ConsumerState<VoidScreen> {
  final Set<String> _selectedItemIds = {};
  String _selectedReason = kVoidReasons.first;
  final TextEditingController _notesController = TextEditingController();
  bool _voidWholeTicket = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  List<OrderItemEntity> _activeItems(TicketEntity ticket) {
    return ticket.items
        .where((i) => i.status != OrderItemStatus.voidStatus)
        .toList();
  }

  List<OrderItemEntity> _selectedItems(List<OrderItemEntity> active) {
    return active.where((i) => _selectedItemIds.contains(i.id)).toList();
  }

  int _selectedSubtotal(List<OrderItemEntity> selected) {
    return selected.fold<int>(0, (s, i) => s + i.subtotal);
  }

  String _fmt(int cents) {
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    return '$whole.$frac';
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  void _toggleAll(List<OrderItemEntity> active) {
    setState(() {
      if (_selectedItemIds.length == active.length) {
        _selectedItemIds.clear();
      } else {
        _selectedItemIds
          ..clear()
          ..addAll(active.map((i) => i.id));
      }
    });
  }

  Future<void> _onConfirmVoid(TicketEntity ticket) async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    // Show manager PIN dialog.
    final approver = await ManagerPinDialog.show(
      context: context,
      ref: ref,
      operationLabel: _voidWholeTicket
          ? 'Sipariş İptali — #${ticket.orderNumber}'
          : '${_selectedItemIds.length} Ürün İptali',
    );
    if (approver == null || !mounted) return;

    final notifier = ref.read(voidOperationProvider.notifier);
    bool ok;

    if (_voidWholeTicket) {
      ok = await notifier.voidTicket(
        ticketId: ticket.id,
        reason: _selectedReason,
        requestedBy: currentUser,
        approvedBy: approver,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
    } else {
      // Void items one by one.
      ok = true;
      for (final itemId in _selectedItemIds) {
        final itemOk = await notifier.voidItem(
          orderItemId: itemId,
          reason: _selectedReason,
          requestedBy: currentUser,
          approvedBy: approver,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
        if (!itemOk) {
          ok = false;
          break;
        }
      }
    }

    if (!mounted) return;

    if (ok) {
      _showSuccess();
    } else {
      final failure = ref.read(voidOperationProvider);
      _showError(failure is VoidFailure ? failure.message : 'İptal başarısız');
    }
  }

  void _showSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.green,
        content: Text(
          'İptal başarıyla gerçekleştirildi',
          style: TextStyle(color: Color(0xFF003A11), fontWeight: FontWeight.w600),
        ),
      ),
    );
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) context.go('/order-center');
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.red,
        content: Text(msg,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
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
        data: (ticket) => ticket != null
            ? _buildBody(ticket)
            : const Center(child: Text('Sipariş bulunamadı')),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
      ),
    );
  }

  Widget _buildBody(TicketEntity ticket) {
    final active = _activeItems(ticket);
    final selected = _selectedItems(active);

    return Stack(
      children: [
        Column(
          children: [
            _buildTopBar(ticket),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildItemList(active)),
                  Expanded(child: _buildSummaryPanel(ticket, active, selected)),
                ],
              ),
            ),
          ],
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
            'Void / İptal',
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
              color: AppColors.redDim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Sipariş #${ticket.orderNumber}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.red,
              ),
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

  // -------------------------------------------------------------------------
  // Left: item list
  // -------------------------------------------------------------------------

  Widget _buildItemList(List<OrderItemEntity> active) {
    return ColoredBox(
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
                  'Sipariş Kalemleri',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${active.length} aktif ürün',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Select all / clear row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _actionChip(
                  label: _selectedItemIds.length == active.length
                      ? 'Seçimi Kaldır'
                      : 'Tümünü Seç',
                  onTap: () => _toggleAll(active),
                ),
                const SizedBox(width: 8),
                if (_selectedItemIds.isNotEmpty)
                  _actionChip(
                    label: 'Temizle',
                    onTap: () => setState(_selectedItemIds.clear),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Item list
          Expanded(
            child: active.isEmpty
                ? const Center(
                    child: Text('Aktif kalem yok',
                        style: TextStyle(color: AppColors.textDim)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: active.length,
                    itemBuilder: (_, i) => _buildItemTile(active[i]),
                  ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            color: AppColors.surfaceContainerLow,
            child: Row(
              children: [
                Text(
                  '${_selectedItemIds.length} ürün seçildi',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
                const Spacer(),
                Text(
                  '₺${_fmt(_selectedSubtotal(_selectedItems(active)))}',
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

  Widget _buildItemTile(OrderItemEntity item) {
    final isSelected = _selectedItemIds.contains(item.id);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedItemIds.remove(item.id);
          } else {
            _selectedItemIds.add(item.id);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  ? const Icon(Icons.close_rounded,
                      size: 14, color: Colors.white)
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (item.notes != null)
                    Text(
                      item.notes!,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textDim),
                    ),
                ],
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
  }

  // -------------------------------------------------------------------------
  // Right: summary / action panel
  // -------------------------------------------------------------------------

  Widget _buildSummaryPanel(
    TicketEntity ticket,
    List<OrderItemEntity> active,
    List<OrderItemEntity> selected,
  ) {
    final canConfirm =
        _voidWholeTicket || _selectedItemIds.isNotEmpty;

    return ColoredBox(
      color: AppColors.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'İptal Özeti',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),

            // Void whole ticket toggle
            GestureDetector(
              onTap: () => setState(() {
                _voidWholeTicket = !_voidWholeTicket;
                if (_voidWholeTicket) _selectedItemIds.clear();
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _voidWholeTicket
                      ? AppColors.redDim
                      : AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _voidWholeTicket
                        ? AppColors.red
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _voidWholeTicket
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      color: _voidWholeTicket
                          ? AppColors.red
                          : AppColors.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Tüm siparişi iptal et',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Selected item summary (partial void)
            if (!_voidWholeTicket) ...[
              const Text(
                'Seçilen Kalemler',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              if (selected.isEmpty)
                const Text(
                  'İptal için kalem seçiniz',
                  style: TextStyle(fontSize: 13, color: AppColors.textDim),
                )
              else
                for (final item in selected)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
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
                            color: AppColors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 20),
            ],

            // Reason selector
            const Text(
              'İptal Nedeni',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            ReasonSelector(
              reasons: kVoidReasons,
              selected: _selectedReason,
              onSelected: (r) => setState(() => _selectedReason = r),
            ),
            const SizedBox(height: 20),

            // Notes
            const Text(
              'Not (opsiyonel)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _notesController,
                maxLines: 2,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Ek bilgi...',
                  hintStyle: TextStyle(fontSize: 13, color: AppColors.textDim),
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
                color: AppColors.redDim,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: AppColors.red),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bu işlem geri alınamaz. Yönetici onayı gereklidir.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.red,
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
                        child: Text(
                          'Vazgeç',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: canConfirm ? () => _onConfirmVoid(ticket) : null,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: canConfirm ? 1.0 : 0.4,
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
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.block_rounded,
                                size: 18, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'İptal Et',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
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

  Widget _actionChip({
    required String label,
    required VoidCallback onTap,
  }) {
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
}
