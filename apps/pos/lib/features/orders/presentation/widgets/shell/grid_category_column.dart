/// Vertical category column — 2-column aspect-square tile grid.
///
/// Replaces the earlier horizontal [CategoryStrip]. For pilot v3 every tile
/// renders in the SambaPOS warm orange default; the active category flips
/// to yellow. The shell keeps the 4-column Kinetic layout and zero-radius
/// rule; only the fill colours reflect the SambaPOS reference screen
/// (019da150) the user approved.
///
/// Column count (1 ↔ 2) is shared with the product grid via
/// [productGridColumnsProvider], so the existing [ColumnToggleButton] flips
/// both the middle and right columns in lock-step.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/product_grid.dart';

class GridCategoryColumn extends ConsumerWidget {
  const GridCategoryColumn({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final selected = ref.watch(selectedCategoryProvider);
    final crossAxis = ref.watch(productGridColumnsProvider);

    return Container(
      width: AppTokens.gridCategoryColumnWidth,
      color: GcColors.surfaceContainerLow,
      padding: const EdgeInsets.all(AppTokens.space8),
      child: categoriesAsync.when(
        data: (categories) => _buildGrid(
          context: context,
          ref: ref,
          categories: categories,
          selectedId: selected,
          crossAxis: crossAxis,
        ),
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildGrid({
    required BuildContext context,
    required WidgetRef ref,
    required List<CategoryEntity> categories,
    required String? selectedId,
    required int crossAxis,
  }) {
    final items = <_Item>[
      const _Item(id: null, label: 'TÜMÜ', colorHex: null),
      ...categories.map(
        (c) => _Item(id: c.id, label: c.name, colorHex: c.color),
      ),
    ];

    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxis.clamp(1, 2),
        mainAxisSpacing: AppTokens.space8,
        crossAxisSpacing: AppTokens.space8,
        childAspectRatio: 1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = item.id == selectedId;
        return _CategoryTile(
          label: item.label,
          colorHex: item.colorHex,
          selected: isSelected,
          onTap: () {
            ref.read(selectedCategoryProvider.notifier).state = item.id;
          },
        );
      },
    );
  }
}

class _Item {
  const _Item({required this.id, required this.label, required this.colorHex});
  final String? id;
  final String label;
  final String? colorHex;
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.colorHex,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? colorHex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = resolveCategoryColor(colorHex, selected: selected);
    final bg = style.bg;
    final fg = style.fg;

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: kInsetHighlight, width: 2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.space4),
            child: Center(
              child: Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GcText.headline.copyWith(
                  fontSize: 12,
                  height: 1.1,
                  letterSpacing: 0.6,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
