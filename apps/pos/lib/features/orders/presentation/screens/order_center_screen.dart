/// Order Center Screen — Lightspeed-inspired professional POS UI.
///
/// Main POS hub with:
/// - [GcSidebar] left navigation (dark navy, 64px)
/// - Three tabs in the top bar: Ongoing, Table, Menu
/// - IndexedStack for instant tab switching (no rebuilds)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/ongoing_orders_tab.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/table_view_tab.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/menu_order_tab.dart';
import 'package:gastrocore_pos/shared/widgets/gc_sidebar.dart';

// ---------------------------------------------------------------------------
// Order Center Screen
// ---------------------------------------------------------------------------

class OrderCenterScreen extends ConsumerStatefulWidget {
  const OrderCenterScreen({super.key});

  @override
  ConsumerState<OrderCenterScreen> createState() => _OrderCenterScreenState();
}

class _OrderCenterScreenState extends ConsumerState<OrderCenterScreen> {
  int _selectedTab = 2; // 0 = Ongoing, 1 = Table, 2 = Menu

  void _switchToMenu() => setState(() => _selectedTab = 2);

  Future<void> _onOrderTap(TicketEntity ticket) async {
    await ref.read(currentTicketProvider.notifier).loadTicket(ticket.id);
    _switchToMenu();
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'Staff';

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Row(
        children: [
          // ── Navigation sidebar ──────────────────────────────────────────
          GcSidebar(
            activeRoute: '/order-center',
            userName: userName,
            userInitials: _initials(userName),
            onLogout: () => context.go(AppRoutes.shiftClose),
          ),

          // ── Main content area ───────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                _buildTopBar(userName),
                Expanded(
                  child: IndexedStack(
                    index: _selectedTab,
                    children: [
                      OngoingOrdersTab(onOrderTap: _onOrderTap),
                      TableViewTab(onSwitchToMenu: _switchToMenu),
                      const MenuOrderTab(),
                    ],
                  ),
                ),
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
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Logo
          const Text(
            'Gastro',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const Text(
            'Core',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 24),

          // Tabs
          _buildTab('Ongoing', 0, 'tab_ongoing'),
          _buildTab('Tables', 1, 'tab_table'),
          _buildTab('Menu', 2, 'tab_menu'),

          const Spacer(),

          // Action icons
          _buildIconButton(
            icon: Icons.search_rounded,
            tooltip: 'Search',
            onTap: () => setState(() => _selectedTab = 2),
          ),
          const SizedBox(width: 4),
          _buildIconButton(
            icon: Icons.print_rounded,
            tooltip: 'Print receipt',
            onTap: () {},
          ),
          const SizedBox(width: 12),

          // User info
          Text(
            userName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.12),
            ),
            child: Center(
              child: Text(
                _initials(userName),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index, String keyId) {
    final isActive = _selectedTab == index;
    return GestureDetector(
      key: Key(keyId),
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            // Active underline
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3,
              width: isActive ? 32 : 0,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.primary.withValues(alpha: 0.08),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
