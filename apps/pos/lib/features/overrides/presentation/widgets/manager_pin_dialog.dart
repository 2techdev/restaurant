/// Reusable manager PIN entry dialog.
///
/// Shows a numpad overlay and verifies the entered PIN against the database.
/// Only users with [UserRole.manager] or [UserRole.admin] can approve.
///
/// Usage:
/// ```dart
/// final approver = await ManagerPinDialog.show(
///   context: context,
///   ref: ref,
///   operationLabel: 'Sipariş İptali',
/// );
/// if (approver != null) { /* proceed */ }
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/features/overrides/presentation/providers/override_provider.dart';

// ---------------------------------------------------------------------------
// PIN hashing (reuse the same method as login)
// ---------------------------------------------------------------------------

import 'dart:convert';
import 'package:crypto/crypto.dart';

String _hashPin(String pin) {
  final bytes = utf8.encode(pin);
  return sha256.convert(bytes).toString();
}

// ---------------------------------------------------------------------------
// ManagerPinDialog
// ---------------------------------------------------------------------------

class ManagerPinDialog extends ConsumerStatefulWidget {
  /// Label shown below the title to explain why authorisation is required.
  final String operationLabel;

  /// When true, only an [UserRole.admin] PIN is accepted.
  ///
  /// Use this for high-value operations (e.g. discounts >50%, bulk refunds).
  final bool requireAdmin;

  const ManagerPinDialog({
    super.key,
    required this.operationLabel,
    this.requireAdmin = false,
  });

  // -------------------------------------------------------------------------
  // Static show helper
  // -------------------------------------------------------------------------

  /// Display the dialog and return the approver [UserEntity], or `null` if
  /// the dialog is dismissed without a successful PIN entry.
  ///
  /// Set [requireAdmin] to true to only accept [UserRole.admin] PINs.
  static Future<UserEntity?> show({
    required BuildContext context,
    required WidgetRef ref,
    required String operationLabel,
    bool requireAdmin = false,
  }) {
    // Reset any stale state before showing.
    ref.read(managerOverrideProvider.notifier).reset();

    return showDialog<UserEntity?>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      barrierDismissible: false,
      builder: (dialogContext) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: ManagerPinDialog(
          operationLabel: operationLabel,
          requireAdmin: requireAdmin,
        ),
      ),
    );
  }

  @override
  ConsumerState<ManagerPinDialog> createState() => _ManagerPinDialogState();
}

class _ManagerPinDialogState extends ConsumerState<ManagerPinDialog> {
  String _pin = '';
  String? _errorMessage;
  bool _isVerifying = false;

  static const int _pinLength = 4;

  // -------------------------------------------------------------------------
  // Input handlers
  // -------------------------------------------------------------------------

  void _onDigit(String digit) {
    if (_pin.length >= _pinLength || _isVerifying) return;
    setState(() {
      _pin += digit;
      _errorMessage = null;
    });
    if (_pin.length == _pinLength) {
      _verify();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty || _isVerifying) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _isVerifying = true);

    final pinHash = _hashPin(_pin);
    final approver = await ref
        .read(managerOverrideProvider.notifier)
        .requestOverride(pinHash);

    if (!mounted) return;

    // If requireAdmin, reject manager-level approvers.
    if (approver != null) {
      if (widget.requireAdmin && !approver.canApproveAdminOverride) {
        setState(() {
          _isVerifying = false;
          _pin = '';
          _errorMessage = 'Bu işlem için Admin yetkisi gereklidir.';
        });
        return;
      }
      Navigator.of(context).pop(approver);
    } else {
      setState(() {
        _isVerifying = false;
        _pin = '';
        _errorMessage = 'Hatalı PIN veya yetersiz yetki. Tekrar deneyin.';
      });
    }
  }

  void _dismiss() => Navigator.of(context).pop(null);

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
          width: 360,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.admin_panel_settings_rounded,
                size: 40,
                color: AppColors.orange,
              ),
              const SizedBox(height: 16),
              const Text(
                'Yönetici Onayı',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.operationLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.requireAdmin
                    ? 'Admin PIN\'i giriniz'
                    : 'Yönetici veya admin PIN\'i giriniz',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // PIN dots
              _buildPinDots(),
              const SizedBox(height: 12),

              // Error message
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _errorMessage != null
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _errorMessage!,
                          key: ValueKey(_errorMessage),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.red,
                          ),
                        ),
                      )
                    : const SizedBox(height: 20, key: ValueKey('empty')),
              ),

              // Numpad
              _buildNumpad(),
              const SizedBox(height: 16),

              // Cancel
              TextButton(
                onPressed: _isVerifying ? null : _dismiss,
                child: const Text(
                  'İptal',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textDim,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pinLength, (i) {
        final filled = i < _pin.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 14,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? (_errorMessage != null ? AppColors.red : AppColors.accent)
                : AppColors.surfaceContainerHigh,
          ),
        );
      }),
    );
  }

  Widget _buildNumpad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((key) {
              if (key.isEmpty) {
                return const SizedBox(width: 72, height: 52);
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _NumKey(
                  label: key,
                  onTap: () {
                    if (key == '⌫') {
                      _onBackspace();
                    } else {
                      _onDigit(key);
                    }
                  },
                  enabled: !_isVerifying,
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// NumKey helper widget
// ---------------------------------------------------------------------------

class _NumKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  const _NumKey({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 100),
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          width: 72,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: label == '⌫'
                ? const Icon(Icons.backspace_outlined,
                    size: 18, color: AppColors.textSecondary)
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reason selector helper widget (shared by void + refund + discount)
// ---------------------------------------------------------------------------

/// Chip-based reason selector.
///
/// [reasons] is the list of localised reason strings.
/// [selected] is the currently selected reason.
/// [onSelected] is called whenever the user taps a chip.
class ReasonSelector extends StatelessWidget {
  final List<String> reasons;
  final String selected;
  final ValueChanged<String> onSelected;

  const ReasonSelector({
    super.key,
    required this.reasons,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: reasons.map((reason) {
        final isActive = selected == reason;
        return GestureDetector(
          onTap: () => onSelected(reason),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.accentDim
                  : AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              reason,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? AppColors.accent
                    : AppColors.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
