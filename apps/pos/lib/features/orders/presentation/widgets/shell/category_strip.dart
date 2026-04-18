/// Horizontal category strip rendered above the product grid.
///
/// Replaces the left-side category sidebar from the legacy `menu_order_tab`.
/// Fine-dining UX calls for a single glance of all categories plus a dedicated
/// "All" tab, so we use a horizontally-scrollable row of pill-shaped chips.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';

class CategoryStrip extends ConsumerWidget {
  const CategoryStrip({super.key, this.trailing});

  /// Optional trailing widget — used by the shell to inject the
  /// column-toggle button right of the category chips.
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final selected = ref.watch(selectedCategoryProvider);

    return Container(
      height: AppTokens.categoryStripHeight,
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
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
    final items = [
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
        return _Chip(
          label: item.label,
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
  bool matchesSelected(String? s);
}

class _AllChipData extends _StripItem {
  const _AllChipData();
  @override
  String get label => 'Tümü';
  @override
  String? get id => null;
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
  bool matchesSelected(String? s) => s == cat.id;
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primaryContainer
          : AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space16,
            vertical: AppTokens.space8,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
