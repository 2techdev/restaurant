/// Horizontal category strip — SambaPOS saturated warm tiles.
///
/// Each category tile is filled with its own colour (warm-spectrum palette
/// from the Kinetic Grid + SambaPOS brief). The operator scans the board
/// by hue first, text second. Text contrast flips automatically via
/// [onCategoryColor] so yellow tiles pick up dark text and red/orange
/// tiles pick up white.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';

class CategoryStrip extends ConsumerWidget {
  const CategoryStrip({super.key, this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final selected = ref.watch(selectedCategoryProvider);

    return Container(
      height: AppTokens.categoryStripHeight,
      color: GcColors.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: categoriesAsync.when(
              data: (categories) => _buildRow(context, ref, categories, selected),
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppTokens.space8),
            trailing!,
            const SizedBox(width: AppTokens.space12),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    WidgetRef ref,
    List<CategoryEntity> categories,
    String? selected,
  ) {
    final items = <_StripItem>[
      const _AllChipData(),
      ...categories.map(_CategoryChipData.new),
    ];
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space12,
        vertical: AppTokens.space8,
      ),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: AppTokens.space8),
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = item.matchesSelected(selected);
        final bg = item.color;
        return _Chip(
          label: item.label,
          bg: bg,
          fg: onCategoryColor(bg),
          selected: isSelected,
          onTap: () {
            ref.read(selectedCategoryProvider.notifier).state = item.id;
          },
        );
      },
    );
  }
}

sealed class _StripItem {
  const _StripItem();
  String get label;
  String? get id;
  Color get color;
  bool matchesSelected(String? s);
}

class _AllChipData extends _StripItem {
  const _AllChipData();
  @override
  String get label => 'Tümü';
  @override
  String? get id => null;
  @override
  Color get color => GcColors.primary;
  @override
  bool matchesSelected(String? s) => s == null;
}

class _CategoryChipData extends _StripItem {
  const _CategoryChipData(this.cat);
  final CategoryEntity cat;
  @override
  String get label => cat.name;
  @override
  String? get id => cat.id;
  @override
  Color get color => resolveCategoryColor(cat.name);
  @override
  bool matchesSelected(String? s) => s == cat.id;
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.bg,
    required this.fg,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color bg;
  final Color fg;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      shape: selected
          ? const Border(
              top: BorderSide(color: kInsetHighlight, width: 2),
              bottom: BorderSide(color: GcColors.primaryDim, width: 3),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space16,
            vertical: AppTokens.space8,
          ),
          child: Center(
            child: Text(
              label.toUpperCase(),
              style: GcText.button.copyWith(color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
