/// Discount application dialog with optional manager PIN for large discounts.
///
/// Supports:
///  - Percentage-based discount (e.g. 10%)
///  - Fixed-amount discount (e.g. ₺5.00)
///  - Mandatory reason selection
///  - Automatic manager override trigger when discount exceeds [kManagerThresholdPercent]
///
/// Usage:
/// ```dart
/// final result = await DiscountDialog.show(context: context, ref: ref);
/// if (result != null) {
///   ref.read(currentTicketProvider.notifier).applyDiscount(result);
/// }
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/overrides/presentation/widgets/manager_pin_dialog.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Discounts above this percentage require manager PIN approval.
const double kManagerThresholdPercent = 20.0;

/// Standard discount reasons.
const kDiscountReasons = [
  'Müşteri Sadakati',
  'Personel İndirimi',
  'Kampanya',
  'Müşteri Şikayeti',
  'Diğer',
];

// ---------------------------------------------------------------------------
// DiscountResult
// ---------------------------------------------------------------------------

class DiscountResult {
  final DiscountType discountType;
  final int discountValue; // percent (0-100) or cents
  final String reason;
  final UserEntity? approvedBy; // null = no override required

  const DiscountResult({
    required this.discountType,
    required this.discountValue,
    required this.reason,
    this.approvedBy,
  });
}

// ---------------------------------------------------------------------------
// DiscountDialog
// ---------------------------------------------------------------------------

class DiscountDialog extends ConsumerStatefulWidget {
  /// Current order total in cents, used to validate fixed discounts.
  final int orderTotal;

  const DiscountDialog({super.key, required this.orderTotal});

  static Future<DiscountResult?> show({
    required BuildContext context,
    required WidgetRef ref,
    required int orderTotal,
  }) {
    return showDialog<DiscountResult?>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: DiscountDialog(orderTotal: orderTotal),
      ),
    );
  }

  @override
  ConsumerState<DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends ConsumerState<DiscountDialog> {
  DiscountType _type = DiscountType.percentage;
  final TextEditingController _valueController = TextEditingController();
  String _selectedReason = kDiscountReasons.first;
  final TextEditingController _customReasonController =
      TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _valueController.dispose();
    _customReasonController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Validation
  // -------------------------------------------------------------------------

  String? _validate() {
    final raw = _valueController.text.trim();
    if (raw.isEmpty) return 'Bir değer giriniz';

    final value = double.tryParse(raw.replaceAll(',', '.'));
    if (value == null || value <= 0) return 'Geçerli bir değer giriniz';

    if (_type == DiscountType.percentage && value > 100) {
      return 'Yüzde 0-100 arasında olmalıdır';
    }

    if (_type == DiscountType.fixed) {
      final cents = (value * 100).round();
      if (cents >= widget.orderTotal) {
        return 'İndirim sipariş tutarından büyük olamaz';
      }
    }

    if (_selectedReason == 'Diğer' &&
        _customReasonController.text.trim().isEmpty) {
      return 'İndirim nedeni giriniz';
    }

    return null;
  }

  /// Whether manager PIN is needed for the current input.
  bool _requiresOverride() {
    if (_type == DiscountType.fixed) {
      final raw = _valueController.text.trim();
      final value = double.tryParse(raw.replaceAll(',', '.')) ?? 0;
      final cents = (value * 100).round();
      if (widget.orderTotal == 0) return false;
      return (cents / widget.orderTotal * 100) >= kManagerThresholdPercent;
    } else {
      final raw = _valueController.text.trim();
      final pct = double.tryParse(raw.replaceAll(',', '.')) ?? 0;
      return pct >= kManagerThresholdPercent;
    }
  }

  // -------------------------------------------------------------------------
  // Apply
  // -------------------------------------------------------------------------

  Future<void> _onApply() async {
    final error = _validate();
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }

    final raw = _valueController.text.trim();
    final value = double.parse(raw.replaceAll(',', '.'));
    final intValue = _type == DiscountType.percentage
        ? value.round()
        : (value * 100).round();

    final effectiveReason =
        _selectedReason == 'Diğer' && _customReasonController.text.trim().isNotEmpty
            ? _customReasonController.text.trim()
            : _selectedReason;

    UserEntity? approver;

    if (_requiresOverride()) {
      approver = await ManagerPinDialog.show(
        context: context,
        ref: ref,
        operationLabel:
            'İndirim: %${_type == DiscountType.percentage ? value.toInt() : ''} — $effectiveReason',
      );
      if (approver == null || !mounted) return;
    } else {
      // Check if current user has permission (manager/admin can apply without PIN).
      final currentUser = ref.read(currentUserProvider);
      if (currentUser?.role == UserRole.cashier ||
          currentUser?.role == UserRole.waiter) {
        // Even below threshold, non-manager staff require override.
        approver = await ManagerPinDialog.show(
          context: context,
          ref: ref,
          operationLabel: 'İndirim Onayı — $effectiveReason',
        );
        if (approver == null || !mounted) return;
      }
    }

    Navigator.of(context).pop(DiscountResult(
      discountType: _type,
      discountValue: intValue,
      reason: effectiveReason,
      approvedBy: approver,
    ));
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.discount_outlined,
                      size: 22, color: AppColors.accent),
                  const SizedBox(width: 10),
                  const Text(
                    'İndirim Uygula',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(null),
                    child: const Icon(Icons.close_rounded,
                        size: 20, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Type selector
              const Text(
                'İndirim Türü',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _typeButton(
                      label: 'Yüzde (%)',
                      type: DiscountType.percentage,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _typeButton(
                      label: 'Tutar (₺)',
                      type: DiscountType.fixed,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Value input
              Text(
                _type == DiscountType.percentage
                    ? 'İndirim Yüzdesi'
                    : 'İndirim Tutarı (₺)',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _errorMessage != null
                        ? AppColors.red
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _valueController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[\d.,]')),
                        ],
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: _type == DiscountType.percentage
                              ? '10'
                              : '5.00',
                          hintStyle: const TextStyle(
                              fontSize: 24, color: AppColors.textDim),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                        onChanged: (_) {
                          setState(() => _errorMessage = null);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Text(
                        _type == DiscountType.percentage ? '%' : '₺',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w300,
                          color: AppColors.textDim,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Manager override hint
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: _requiresOverride()
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_outline_rounded,
                                size: 14, color: AppColors.orange),
                            const SizedBox(width: 6),
                            Text(
                              'Bu indirim yönetici onayı gerektirir'
                              ' (≥%${kManagerThresholdPercent.toInt()})',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.orange,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.red),
                  ),
                ),

              const SizedBox(height: 20),

              // Reason
              const Text(
                'İndirim Nedeni',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              ReasonSelector(
                reasons: kDiscountReasons,
                selected: _selectedReason,
                onSelected: (r) => setState(() => _selectedReason = r),
              ),
              if (_selectedReason == 'Diğer') ...[
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _customReasonController,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'İndirim nedenini giriniz...',
                      hintStyle:
                          TextStyle(fontSize: 13, color: AppColors.textDim),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(null),
                      child: Container(
                        height: 48,
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
                      onTap: _onApply,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Text(
                            'Uygula',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
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
      ),
    );
  }

  Widget _typeButton({
    required String label,
    required DiscountType type,
  }) {
    final isActive = _type == type;
    return GestureDetector(
      onTap: () => setState(() {
        _type = type;
        _errorMessage = null;
        _valueController.clear();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 40,
        decoration: BoxDecoration(
          color: isActive ? AppColors.accentDim : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
