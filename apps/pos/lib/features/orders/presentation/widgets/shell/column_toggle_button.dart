/// Toggle button that flips the product grid between 1-column (list / long
/// menu) and 2-column (big-button / house-favourites) mode.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
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
        color: GcColors.surfaceContainerHigh,
        child: InkWell(
          key: const Key('product_grid_column_toggle'),
          onTap: () => toggleProductGridColumns(ref),
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
                  color: GcColors.onSurface,
                ),
                const SizedBox(width: 6),
                Text(
                  isOne ? '1 SÜTUN' : '2 SÜTUN',
                  style: GcText.button.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
