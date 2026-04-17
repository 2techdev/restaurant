/// Toggle button that flips the product grid between 1-column (list / long
/// menu) and 2-column (big-button / house-favourites) mode.
///
/// Product decision 2026-04-17: operators want one tap to re-flow the grid
/// mid-service without diving into Settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/product_grid.dart';

class ColumnToggleButton extends ConsumerWidget {
  const ColumnToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columns = ref.watch(productGridColumnsProvider);
    final isOne = columns == 1;
    return Tooltip(
      message: isOne
          ? 'Tek sütun — uzun menü / kalabalık servis'
          : 'Çift sütun — sık kullanılan ürünler',
      child: Material(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: InkWell(
          key: const Key('product_grid_column_toggle'),
          onTap: () => toggleProductGridColumns(ref),
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.space12,
              vertical: AppTokens.space8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOne
                      ? Icons.view_agenda_rounded
                      : Icons.grid_view_rounded,
                  size: 18,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 6),
                Text(
                  isOne ? '1 sütun' : '2 sütun',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
