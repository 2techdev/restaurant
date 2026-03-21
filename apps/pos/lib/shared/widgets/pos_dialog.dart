/// Dialog variants following the Stitch "Precision POS Framework".
///
/// Provides two dialog types and convenience show-helpers:
///
/// - [PosConfirmDialog] — Standard confirmation dialog for destructive or
///   important actions. Uses [AppColors.surfaceContainerHighest] background
///   with 16px radius and no border ("No-Line" rule).
///
/// - [PosManagerPinDialog] — Manager PIN override dialog with a 4-dot PIN
///   entry, built-in numpad, and audit-ready action description.
///   Shows "Yetki Gerekli" (Authorization Required) title.
///
/// Convenience helpers:
/// - [showPosConfirmDialog] — returns `true` on confirm, `null` on dismiss.
/// - [showManagerPinDialog] — returns the entered PIN string, or `null`.
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// PosConfirmDialog
// ---------------------------------------------------------------------------

/// A confirmation dialog for important or destructive actions.
///
/// ```dart
/// final confirmed = await showPosConfirmDialog(
///   context,
///   title: 'Void Item',
///   message: 'Are you sure you want to void 2x Adana Kebap?',
///   confirmLabel: 'Void',
///   confirmColor: AppColors.red,
/// );
/// ```
class PosConfirmDialog extends StatelessWidget {
  const PosConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.confirmColor,
    required this.onConfirm,
  });

  /// Dialog title.
  final String title;

  /// Descriptive message explaining the action.
  final String message;

  /// Label for the confirm button. Defaults to "Confirm".
  final String confirmLabel;

  /// Label for the cancel button. Defaults to "Cancel".
  final String cancelLabel;

  /// Confirm button color. Defaults to gradient primary when null.
  /// Use [AppColors.red] for destructive actions.
  final Color? confirmColor;

  /// Called when the user taps the confirm button.
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceContainerHighest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              // Message
              Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: _DialogButton(
                      label: cancelLabel,
                      color: AppColors.surfaceContainerHigh,
                      textColor: AppColors.textSecondary,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DialogButton(
                      label: confirmLabel,
                      color: confirmColor ?? AppColors.primaryContainer,
                      textColor: Colors.white,
                      onTap: () {
                        onConfirm();
                        Navigator.of(context).pop(true);
                      },
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
}

// ---------------------------------------------------------------------------
// PosManagerPinDialog
// ---------------------------------------------------------------------------

/// A Manager PIN override dialog for authorizing restricted actions.
///
/// Displays a 4-dot PIN entry field with a built-in numpad. The
/// [actionDescription] is shown so the manager can verify what they are
/// authorizing (audit trail).
///
/// ```dart
/// final pin = await showManagerPinDialog(
///   context,
///   actionDescription: 'Void 2x Adana Kebap (CHF 57.00)',
/// );
/// if (pin != null) { /* validate pin, log audit */ }
/// ```
class PosManagerPinDialog extends StatefulWidget {
  const PosManagerPinDialog({
    super.key,
    required this.actionDescription,
    required this.onSubmit,
  });

  /// Human-readable description of the action requiring authorization.
  /// Shown in the dialog for audit clarity.
  final String actionDescription;

  /// Called with the entered PIN string when the user completes entry.
  final void Function(String pin) onSubmit;

  @override
  State<PosManagerPinDialog> createState() => _PosManagerPinDialogState();
}

class _PosManagerPinDialogState extends State<PosManagerPinDialog> {
  static const int _pinLength = 4;
  String _enteredPin = '';
  bool _hasError = false;

  void _addDigit(String digit) {
    if (_enteredPin.length >= _pinLength) return;

    setState(() {
      _enteredPin += digit;
      _hasError = false;
    });

    // Auto-submit when all digits entered.
    if (_enteredPin.length == _pinLength) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          widget.onSubmit(_enteredPin);
        }
      });
    }
  }

  void _backspace() {
    if (_enteredPin.isEmpty) return;
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _hasError = false;
    });
  }

  void _clear() {
    setState(() {
      _enteredPin = '';
      _hasError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceContainerHighest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lock icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.orangeDim,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: AppColors.orange,
                  size: 24,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              const Text(
                'Yetki Gerekli',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),

              // Subtitle
              const Text(
                'Manager PIN eingeben',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),

              // Action description
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.actionDescription,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // PIN dots
              _buildPinDots(),
              const SizedBox(height: 24),

              // Numpad (compact)
              _buildCompactNumpad(),
              const SizedBox(height: 16),

              // Cancel button
              SizedBox(
                width: double.infinity,
                child: _DialogButton(
                  label: 'Abbrechen',
                  color: AppColors.surfaceContainerHigh,
                  textColor: AppColors.textSecondary,
                  onTap: () => Navigator.of(context).pop(),
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
        final isFilled = i < _enteredPin.length;

        return Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: _hasError
                  ? AppColors.red
                  : (isFilled
                      ? AppColors.accent
                      : AppColors.surfaceContainerHigh),
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCompactNumpad() {
    const gap = 6.0;
    const keyH = 48.0;

    Widget key(String label, {Color? textColor, VoidCallback? onTap}) {
      return Expanded(
        child: _CompactNumKey(
          label: label,
          height: keyH,
          textColor: textColor,
          onTap: onTap ?? () => _addDigit(label),
        ),
      );
    }

    Widget iconKey(IconData icon, {Color? color, required VoidCallback onTap}) {
      return Expanded(
        child: _CompactNumKey(
          icon: icon,
          height: keyH,
          textColor: color,
          onTap: onTap,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          key('1'),
          const SizedBox(width: gap),
          key('2'),
          const SizedBox(width: gap),
          key('3'),
        ]),
        const SizedBox(height: gap),
        Row(children: [
          key('4'),
          const SizedBox(width: gap),
          key('5'),
          const SizedBox(width: gap),
          key('6'),
        ]),
        const SizedBox(height: gap),
        Row(children: [
          key('7'),
          const SizedBox(width: gap),
          key('8'),
          const SizedBox(width: gap),
          key('9'),
        ]),
        const SizedBox(height: gap),
        Row(children: [
          key('C', textColor: AppColors.orange, onTap: _clear),
          const SizedBox(width: gap),
          key('0'),
          const SizedBox(width: gap),
          iconKey(
            Icons.backspace_outlined,
            color: AppColors.textSecondary,
            onTap: _backspace,
          ),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Show helpers
// ---------------------------------------------------------------------------

/// Shows a [PosConfirmDialog] and returns `true` if confirmed, `null` if
/// dismissed.
///
/// ```dart
/// final result = await showPosConfirmDialog(
///   context,
///   title: 'Close Shift',
///   message: 'All unsettled orders will be cancelled.',
///   confirmLabel: 'Close Shift',
///   confirmColor: AppColors.red,
/// );
/// if (result == true) closeShift();
/// ```
Future<bool?> showPosConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  Color? confirmColor,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: AppColors.bgOverlay,
    builder: (_) => PosConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      confirmColor: confirmColor,
      onConfirm: () {},
    ),
  );
}

/// Shows a [PosManagerPinDialog] and returns the entered PIN string, or
/// `null` if dismissed.
///
/// ```dart
/// final pin = await showManagerPinDialog(
///   context,
///   actionDescription: 'Void 2x Adana Kebap (CHF 57.00)',
/// );
/// ```
Future<String?> showManagerPinDialog(
  BuildContext context, {
  required String actionDescription,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: AppColors.bgOverlay,
    barrierDismissible: false,
    builder: (_) => PosManagerPinDialog(
      actionDescription: actionDescription,
      onSubmit: (pin) => Navigator.of(context).pop(pin),
    ),
  );
}

// ---------------------------------------------------------------------------
// Internal widgets
// ---------------------------------------------------------------------------

/// A simple dialog action button — no border, surface background.
class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white.withValues(alpha: 0.08),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact numpad key for use inside the PIN dialog.
class _CompactNumKey extends StatelessWidget {
  const _CompactNumKey({
    this.label,
    this.icon,
    required this.height,
    required this.onTap,
    this.textColor,
  });

  final String? label;
  final IconData? icon;
  final double height;
  final VoidCallback onTap;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final color = textColor ?? AppColors.textPrimary;

    return SizedBox(
      height: height,
      child: Material(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.textPrimary.withValues(alpha: 0.08),
          highlightColor: AppColors.surfaceBright,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 18, color: color)
                : Text(
                    label ?? '',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
