/// Full-screen menu management interface.
///
/// Three tabs:
///   0 – Products  : grid/list view with search, filter, active toggle,
///                   bulk price update, add/edit/delete.
///   1 – Categories: drag-to-sort list with add/edit/delete.
///   2 – Modifiers : modifier group list with CRUD for groups and options.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/menu/presentation/widgets/product_admin_panel.dart';
import 'package:gastrocore_pos/features/menu/presentation/widgets/category_management_panel.dart';
import 'package:gastrocore_pos/features/menu/presentation/widgets/modifier_management_panel.dart';
import 'package:gastrocore_pos/features/menu/presentation/widgets/product_modifier_assignment_panel.dart';

class MenuManagementScreen extends ConsumerWidget {
  const MenuManagementScreen({super.key});

  static const _tabs = [
    _TabItem(label: 'Ürünler', icon: Icons.inventory_2_outlined),
    _TabItem(label: 'Kategoriler', icon: Icons.category_outlined),
    _TabItem(label: 'Modifier Grupları', icon: Icons.tune_rounded),
    _TabItem(label: 'Atamalar', icon: Icons.link_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(menuAdminTabProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _buildTopBar(context, ref, activeTab),
          Expanded(child: _buildBody(activeTab)),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, WidgetRef ref, int activeTab) {
    return Container(
      height: 64,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Back button
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              splashColor: AppColors.textPrimary.withValues(alpha: 0.06),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Menü Yönetimi',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),

          // Tab buttons
          _buildTabBar(ref, activeTab),
        ],
      ),
    );
  }

  Widget _buildTabBar(WidgetRef ref, int activeTab) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_tabs.length, (i) {
        final tab = _tabs[i];
        final isActive = i == activeTab;
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            child: Material(
              color:
                  isActive ? AppColors.surfaceBright : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () =>
                    ref.read(menuAdminTabProvider.notifier).state = i,
                splashColor: AppColors.textPrimary.withValues(alpha: 0.05),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tab.icon,
                        size: 16,
                        color: isActive
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tab.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isActive
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildBody(int activeTab) {
    return IndexedStack(
      index: activeTab,
      children: const [
        ProductAdminPanel(),
        CategoryManagementPanel(),
        ModifierManagementPanel(),
        ProductModifierAssignmentPanel(),
      ],
    );
  }
}

class _TabItem {
  final String label;
  final IconData icon;
  const _TabItem({required this.label, required this.icon});
}
