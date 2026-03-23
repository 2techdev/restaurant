/// Discount application dialog with role-based limits and manager PIN for
/// discounts that exceed the current user's authorisation level.
///
/// Role limits (percentage):
///   waiter / cashier → 0 %  (always requires manager approval)
///   manager          → 50 % (anything above requires admin approval)
///   admin            → 100 % (no limit)
///
/// Supports:
///  - Percentage-based discount (e.g. 10%)
///  - Fixed-amount discount (e.g. CHF 5.00)
///  - Mandatory reason selection
///  - Automatic manager / admin override trigger when discount exceeds limit
///
/// Usage:
/// ```dart
/// final result = await DiscountDialog.show(
///   context: context, ref: ref, orderTotal: ticket.total);
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
// Role-based discount limits
// ---------------------------------------------------------------------------

/// Maximum discount percentage a [UserRole.waiter] or [UserRole.cashier] can
/// apply without any manager override.  Currently 0 — they always need approval.
const double kWaiterMaxDiscountPct = 0.0;

/// Maximum discount percentage a [UserRole.manager] can approve unilaterally.
const double kManagerMaxDiscountPct = 50.0;

/// Maximum discount percentage a [UserRole.admin] can approve (effectively 100%).
const double kAdminMaxDiscountPct = 100.0;

/// Returns the self-authorisation limit for [role].
double _selfLimit(UserRole role) {
  return switch (role) {
    UserRole.admin => kAdminMaxDiscountPct,
    UserRole.manager => kManagerMaxDiscountPct,
    _ => kWaiterMaxDiscountPct,
  };
}

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
  final UserEntity? approvedBy; // null = self-authorised

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
  // Helpers
  // -------------------------------------------------------------------------

  /// Effective percentage the user has entered (0 if invalid).
  double _effectivePct() {
    final raw = _valueController.text.trim();
    final value = double.tryParse(raw.replaceAll(',', '.')) ?? 0;
    if (_type == DiscountType.percentage) return value;
    if (widget.orderTotal == 0) return 0;
    final cents = (value * 100).round();
    return cents / widget.orderTotal * 100;
  }

  /// Whether the current user can self-authorise the entered discount.
  bool _selfAuthorised(UserEntity? user) {
    if (user == null) return false;
    return _effectivePct() <= _selfLimit(user.role);
  }

  /// Whether the current user needs a manager (not admin) approval.
  // ignore: unused_element
  bool _requiresManagerApproval(UserEntity? user) {
    final pct = _effectivePct();
    if (user == null) return pct > 0;
    return pct > _selfLimit(user.role) && pct <= kManagerMaxDiscountPct;
  }

  /// Whether the entered discount exceeds even the manager limit (admin needed).
  bool _requiresAdminApproval() {
    return _effectivePct() > kManagerMaxDiscountPct;
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
        _selectedReason == 'Diğer' &&
                _customReasonController.text.trim().isNotEmpty
            ? _customReasonController.text.trim()
            : _selectedReason;

    final currentUser = ref.read(currentUserProvider);
    UserEntity? approver;

    if (!_selfAuthorised(currentUser)) {
      // Show manager / admin PIN dialog.
      final label = _requiresAdminApproval()
          ? 'Admin Onayı Gerekli — İndirim: %${_effectivePct().toStringAsFixed(0)}'
          : 'Yönetici Onayı — İndirim: %${_effectivePct().toStringAsFixed(0)} — $effectiveReason';

      approver = await ManagerPinDialog.show(
        context: context,
        ref: ref,
        operationLabel: label,
        requireAdmin: _requiresAdminApproval(),
      );
      if (approver == null || !mounted) return;

      // Validate that the approver has sufficient authority.
      if (_requiresAdminApproval() && !approver.canApproveAdminOverride) {
        setState(() =>
            _errorMessage = 'Bu indirim için admin onayı gereklidir (>%${kManagerMaxDiscountPct.toInt()})');
        return;
      }
    }

    if (!mounted) return;
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
    final currentUser = ref.watch(currentUserProvider);

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
                      label: 'Tutar (CHF)',
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
                    : 'İndirim Tutarı (CHF)',
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
                        _type == DiscountType.percentage ? '%' : 'CHF',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w300,
                          color: AppColors.textDim,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Role-limit / override hint
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: _buildOverrideHint(currentUser),
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

  Widget _buildOverrideHint(UserEntity? user) {
    final pct = _effectivePct();
    if (pct <= 0) return const SizedBox.shrink();

    final selfLimit = _selfLimit(user?.role ?? UserRole.waiter);
    final needsOverride = !_selfAuthorised(user);
    final needsAdmin = _requiresAdminApproval();

    if (!needsOverride) return const SizedBox.shrink();

    final color = needsAdmin ? AppColors.red : AppColors.orange;
    final icon = needsAdmin
        ? Icons.admin_panel_settings_rounded
        : Icons.lock_outline_rounded;
    final text = needsAdmin
        ? 'Admin onayı gereklidir (>%${kManagerMaxDiscountPct.toInt()})'
        : user?.role == UserRole.manager
            ? 'Bu indirim için admin onayı gereklidir'
            : 'Yönetici onayı gereklidir (limit: %${selfLimit.toInt()})';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ),
        ],
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
