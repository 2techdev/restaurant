/// Order Center Screen for GastroCore POS.
///
/// The main POS hub with three top-bar tabs: Ongoing, Table, and Menu.
/// Uses an IndexedStack so tab switches feel instant with no rebuilds.
/// Follows the OrderPin navigation pattern combined with the Stitch
/// "Precision POS Framework" design system.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/online_orders/presentation/providers/online_order_provider.dart';
import 'package:gastrocore_pos/features/online_orders/presentation/widgets/online_order_overlay.dart';
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
  int _selectedTab = 2; // 0 = Ongoing, 1 = Table, 2 = Menu (start on Menu)

  @override
  void initState() {
    super.initState();
    // Activate the POS WebSocket connection for the duration this screen
    // is mounted. The provider is autoDispose so it tears down cleanly.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(posWsClientProvider);
    });
  }

  void _switchToMenu() {
    setState(() => _selectedTab = 2);
  }

  void _onOrderTap(TicketEntity ticket) async {
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
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Stack(
        children: [
          Column(
            children: [
              // -- Top bar with tabs --
              _buildTopBar(),
              // -- Tab content (IndexedStack for instant switching) --
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
          // -- Online order slide-in notification overlay --
          const OnlineOrderOverlay(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Top bar
  // -------------------------------------------------------------------------

  Widget _buildTopBar() {
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'Staff';
    final userRole = user?.role.name.toUpperCase() ?? 'FSR';
    final initials = _initials(userName);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: AppColors.surfaceContainer,
      child: Row(
        children: [
          // Home / grid icon
          GestureDetector(
            onTap: () => context.go(AppRoutes.home),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 20),

          // Tabs
          _buildOngoingTab(),
          _buildTab('Table', 1, 'tab_table'),
          _buildTab('Menu', 2, 'tab_menu'),

          const Spacer(),

          // Search icon
          GestureDetector(
            onTap: () {
              // Switch to menu tab with search focused
              setState(() => _selectedTab = 2);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.search_rounded,
                size: 20,
                color: AppColors.textDim,
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Print icon — navigates to receipt preview for the active ticket
          GestureDetector(
            onTap: () {
              final ticket = ref.read(currentTicketProvider);
              if (ticket == null || ticket.status == TicketStatus.draft) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No active order to print.'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              context.push(AppRoutes.receiptFor(ticket.id));
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.print_rounded,
                size: 20,
                color: AppColors.textDim,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // User avatar + role
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.15),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accentDim,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              userRole,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "Ongoing" tab with a red dot when there are pending online orders.
  Widget _buildOngoingTab() {
    final pendingCount = ref.watch(pendingOnlineOrdersProvider).length;
    final isActive = _selectedTab == 0;
    return GestureDetector(
      key: const Key('tab_ongoing'),
      onTap: () => setState(() => _selectedTab = 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 56,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Ongoing',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w400,
                      color: isActive
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                Container(
                  height: 3,
                  width: 32,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
            if (pendingCount > 0)
              Positioned(
                top: 10,
                right: -4,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  color:
                      isActive ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ),
            // Active indicator line
            Container(
              height: 3,
              width: 32,
              decoration: BoxDecoration(
                color: isActive ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
