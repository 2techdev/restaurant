/// Order Center Screen — Stitch "Klein Professional POS" UI.
///
/// Main POS hub — 64px top bar replaces sidebar navigation.
/// Four tabs: ONGOING | TABLES | MENU | STAFF
/// IndexedStack for instant tab switching (no rebuilds).
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

// ---------------------------------------------------------------------------
// Order Center Screen
// ---------------------------------------------------------------------------

class OrderCenterScreen extends ConsumerStatefulWidget {
  const OrderCenterScreen({super.key});

  @override
  ConsumerState<OrderCenterScreen> createState() => _OrderCenterScreenState();
}

class _OrderCenterScreenState extends ConsumerState<OrderCenterScreen> {
  // 0=ONGOING, 1=TABLES, 2=MENU, 3=STAFF
  int _selectedTab = 2;

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
      body: Column(
        children: [
          // ── Stitch 64px top bar ─────────────────────────────────────────
          _buildTopBar(userName),
          // ── Content area ────────────────────────────────────────────────
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                OngoingOrdersTab(onOrderTap: _onOrderTap),
                TableViewTab(onSwitchToMenu: _switchToMenu),
                const MenuOrderTab(),
                _buildStaffPlaceholder(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Stitch Top Bar — 64px, bg surfaceContainerLow (#10131A)
  // -------------------------------------------------------------------------

  Widget _buildTopBar(String userName) {
    const tabs = ['ONGOING', 'TABLES', 'MENU', 'STAFF'];

    return Container(
      height: 64,
      color: AppColors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // ── Wordmark ─────────────────────────────────────────────────────
          const Text(
            'GASTROCORE',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(width: 32),

          // ── Navigation tabs ───────────────────────────────────────────────
          ...List.generate(tabs.length, (i) => _buildTopTab(tabs[i], i)),

          const Spacer(),

          // ── Action icons ──────────────────────────────────────────────────
          _buildTopIconBtn(Icons.notifications_none_rounded, 'Notifications'),
          const SizedBox(width: 4),
          _buildTopIconBtn(Icons.settings_outlined, 'Settings',
              onTap: () => context.go(AppRoutes.settings)),
          const SizedBox(width: 12),

          // ── User avatar + name ────────────────────────────────────────────
          _buildUserChip(userName),
        ],
      ),
    );
  }

  Widget _buildTopTab(String label, int index) {
    final isActive = _selectedTab == index;
    return GestureDetector(
      key: Key('tab_$index'),
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? AppColors.primaryContainer : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isActive ? AppColors.primary : AppColors.textDim,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopIconBtn(IconData icon, String tooltip,
      {VoidCallback? onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap ?? () {},
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 18, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildUserChip(String userName) {
    return GestureDetector(
      onTap: () => context.go(AppRoutes.shiftClose),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryContainer.withValues(alpha: 0.25),
            ),
            child: Center(
              child: Text(
                _initials(userName),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            userName,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Staff placeholder tab
  // -------------------------------------------------------------------------

  Widget _buildStaffPlaceholder() {
    return Container(
      color: AppColors.surfaceDim,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded,
                size: 48, color: AppColors.textDim),
            SizedBox(height: 12),
            Text(
              'Staff Management',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Coming soon',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
