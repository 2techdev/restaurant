/// Bulk price update dialog for menu management.
///
/// Allows the operator to apply a percentage adjustment (increase or decrease)
/// to all products in a selected category, or to all products across the menu.
///
/// Swiss context: prices are stored as integer cents (Rappen). The dialog
/// shows live examples using the current CHF symbol.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/shared/widgets/pos_button.dart';
import 'package:gastrocore_pos/shared/widgets/pos_text_field.dart';

/// Shows the bulk price update dialog.
///
/// [tenantId] — current tenant scope.
/// [categoryId] — if non-null, scope to a single category.
/// [categoryName] — display label for the scoped category.
///
/// Returns `true` when the update was applied.
Future<bool?> showBulkPriceDialog(
  BuildContext context, {
  required String tenantId,
  String? categoryId,
  String? categoryName,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: AppColors.bgOverlay,
    builder: (_) => _BulkPriceDialog(
      tenantId: tenantId,
      categoryId: categoryId,
      categoryName: categoryName,
    ),
  );
}

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

class _BulkPriceDialog extends ConsumerStatefulWidget {
  final String tenantId;
  final String? categoryId;
  final String? categoryName;

  const _BulkPriceDialog({
    required this.tenantId,
    this.categoryId,
    this.categoryName,
  });

  @override
  ConsumerState<_BulkPriceDialog> createState() => _BulkPriceDialogState();
}

class _BulkPriceDialogState extends ConsumerState<_BulkPriceDialog> {
  final _percentCtrl = TextEditingController(text: '5.0');
  bool _isIncrease = true;
  bool _isApplying = false;
  String? _resultMessage;

  double get _parsedPercent {
    final raw = _percentCtrl.text.replaceAll(',', '.');
    return (double.tryParse(raw) ?? 0.0).abs();
  }

  double get _effectiveAdjustment =>
      _isIncrease ? _parsedPercent : -_parsedPercent;

  @override
  void dispose() {
    _percentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceContainerHighest,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Row(
                children: [
                  const Icon(Icons.price_change_outlined,
                      size: 20, color: AppColors.primary),
                  const SizedBox(width: 10),
                  const Text(
                    'Bulk Price Update',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Scope label
              _ScopeChip(
                categoryName: widget.categoryName,
                categoryId: widget.categoryId,
              ),
              const SizedBox(height: 20),

              // Increase / decrease toggle
              const _FieldLabel('Direction'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DirectionButton(
                      label: 'Increase',
                      icon: Icons.trending_up_rounded,
                      color: AppColors.green,
                      isSelected: _isIncrease,
                      onTap: () => setState(() => _isIncrease = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DirectionButton(
                      label: 'Decrease',
                      icon: Icons.trending_down_rounded,
                      color: AppColors.red,
                      isSelected: !_isIncrease,
                      onTap: () => setState(() => _isIncrease = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Percentage input
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: PosTextField(
                      label: 'Adjustment (%)',
                      hint: '5.0',
                      controller: _percentCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Live example
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: _LiveExample(
                      adjustmentPercent: _effectiveAdjustment,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _isIncrease
                    ? 'All prices will be increased by ${_parsedPercent.toStringAsFixed(1)}%'
                    : 'All prices will be decreased by ${_parsedPercent.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  color: _isIncrease ? AppColors.green : AppColors.red,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Prices are rounded to the nearest Rappen (0.01 CHF).',
                style: TextStyle(fontSize: 11, color: AppColors.textDim),
              ),
              const SizedBox(height: 20),

              // MWST reminder
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.yellowDim,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: AppColors.yellow),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Swiss MWST rates: 8.1% dine-in · 2.6% takeaway · 8.1% alcohol. '
                        'This update changes stored prices only — VAT is applied at checkout.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.yellow,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Result message
              if (_resultMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.greenDim,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded,
                          size: 16, color: AppColors.green),
                      const SizedBox(width: 8),
                      Text(
                        _resultMessage!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Actions
              Row(
                children: [
                  Expanded(
                    child: PosGhostButton(
                      label: 'Cancel',
                      onPressed: _isApplying
                          ? null
                          : () => Navigator.pop(context, false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PosGradientButton(
                      label: _isApplying ? 'Applying…' : 'Apply',
                      icon: Icons.check_rounded,
                      height: 48,
                      isLoading: _isApplying,
                      onPressed: _parsedPercent > 0 ? _applyUpdate : null,
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

  Future<void> _applyUpdate() async {
    if (_parsedPercent <= 0) return;

    setState(() {
      _isApplying = true;
      _resultMessage = null;
    });

    try {
      final repo = ref.read(menuRepositoryProvider);
      final count = await repo.bulkUpdatePrices(
        tenantId: widget.tenantId,
        categoryId: widget.categoryId,
        adjustmentPercent: _effectiveAdjustment,
      );

      setState(() {
        _isApplying = false;
        _resultMessage =
            '$count product${count == 1 ? '' : 's'} updated successfully.';
      });

      // Auto-close after a short delay so user sees the confirmation
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isApplying = false;
        _resultMessage = 'Error: $e';
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _ScopeChip extends StatelessWidget {
  final String? categoryName;
  final String? categoryId;

  const _ScopeChip({this.categoryName, this.categoryId});

  @override
  Widget build(BuildContext context) {
    final label = categoryId != null
        ? 'Scope: ${categoryName ?? 'Selected Category'}'
        : 'Scope: All Products';
    final color =
        categoryId != null ? AppColors.purpleDim : AppColors.accentDim;
    final textColor =
        categoryId != null ? AppColors.purple : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

class _DirectionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _DirectionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 52,
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: color.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? color : AppColors.textDim),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveExample extends StatelessWidget {
  final double adjustmentPercent;

  const _LiveExample({required this.adjustmentPercent});

  @override
  Widget build(BuildContext context) {
    // Example: CHF 15.00 after adjustment
    const exampleCents = 1500;
    final newCents =
        (exampleCents * (1.0 + adjustmentPercent / 100)).round();
    final before = 'CHF ${(exampleCents / 100).toStringAsFixed(2)}';
    final after = 'CHF ${(newCents / 100).toStringAsFixed(2)}';

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12),
        children: [
          TextSpan(
            text: before,
            style: const TextStyle(
              color: AppColors.textDim,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const TextSpan(
            text: ' → ',
            style: TextStyle(color: AppColors.textDim),
          ),
          TextSpan(
            text: after,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: adjustmentPercent >= 0
                  ? AppColors.green
                  : AppColors.red,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }
}
