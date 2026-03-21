/// Back Office Lite screen for on-device restaurant management.
///
/// Tab-based navigation for Menu, Tables, Staff, Reports, and Settings.
/// Managers can edit menu items, table layouts, and staff without cloud access.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/backoffice/presentation/widgets/menu_management_tab.dart';
import 'package:gastrocore_pos/features/backoffice/presentation/widgets/table_management_tab.dart';
import 'package:gastrocore_pos/features/backoffice/presentation/widgets/staff_management_tab.dart';
import 'package:gastrocore_pos/features/backoffice/presentation/widgets/reports_tab.dart';

// ---------------------------------------------------------------------------
// Sidebar tab definition
// ---------------------------------------------------------------------------

class _SidebarTab {
  const _SidebarTab({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

const _tabs = <_SidebarTab>[
  _SidebarTab(icon: Icons.restaurant_menu_rounded, label: 'Menu Yonetimi'),
  _SidebarTab(icon: Icons.table_bar_rounded, label: 'Masa Duzenle'),
  _SidebarTab(icon: Icons.people_rounded, label: 'Personel'),
  _SidebarTab(icon: Icons.bar_chart_rounded, label: 'Raporlar'),
  _SidebarTab(icon: Icons.settings_rounded, label: 'Ayarlar'),
];

// ---------------------------------------------------------------------------
// BackOfficeScreen
// ---------------------------------------------------------------------------

class BackOfficeScreen extends ConsumerStatefulWidget {
  const BackOfficeScreen({super.key});

  @override
  ConsumerState<BackOfficeScreen> createState() => _BackOfficeScreenState();
}

class _BackOfficeScreenState extends ConsumerState<BackOfficeScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          // ── Top bar ──
          _buildTopBar(currentUser?.name ?? 'Manager'),

          // ── Body: sidebar + content ──
          Expanded(
            child: Row(
              children: [
                _buildSidebar(),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Top bar
  // -------------------------------------------------------------------------

  Widget _buildTopBar(String userName) {
    return Container(
      height: 56,
      color: AppColors.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Logo
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Gastro',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryContainer],
                ).createShader(bounds),
                child: const Text(
                  'Core',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),

          // Title
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Back Office',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),

          const Spacer(),

          // User info
          Text(
            userName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                userName.isNotEmpty
                    ? userName.substring(0, 1).toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // POS'a Don button
          Material(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => context.go('/order-center'),
              splashColor: AppColors.textPrimary.withValues(alpha: 0.06),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.point_of_sale_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 8),
                    Text(
                      "POS'a Don",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Sidebar
  // -------------------------------------------------------------------------

  Widget _buildSidebar() {
    return Container(
      width: 220,
      color: AppColors.surface,
      child: Column(
        children: [
          const SizedBox(height: 16),
          for (int i = 0; i < _tabs.length; i++) _buildSidebarItem(i),
          const Spacer(),
          // Version info
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'v1.0.0 Lite',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(int index) {
    final tab = _tabs[index];
    final isSelected = _selectedTab == index;

    return Material(
      color: isSelected ? AppColors.surfaceBright : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        splashColor: AppColors.textPrimary.withValues(alpha: 0.04),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Icon(
                tab.icon,
                size: 20,
                color: isSelected ? AppColors.primary : AppColors.textDim,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  width: 3,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Content area
  // -------------------------------------------------------------------------

  Widget _buildContent() {
    return IndexedStack(
      index: _selectedTab,
      children: const [
        MenuManagementTab(),
        TableManagementTab(),
        StaffManagementTab(),
        ReportsTab(),
        _SettingsPlaceholder(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Settings placeholder
// ---------------------------------------------------------------------------

class _SettingsPlaceholder extends StatelessWidget {
  const _SettingsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.settings_rounded,
            size: 48,
            color: AppColors.textDim,
          ),
          SizedBox(height: 16),
          Text(
            'Ayarlar',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Yakin zamanda eklenecek',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}
