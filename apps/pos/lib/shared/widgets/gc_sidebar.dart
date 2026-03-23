/// GastroCore Navigation Sidebar.
///
/// A 64px collapsed left sidebar following the Lightspeed-inspired design:
/// - Dark navy background (#1B2838) — always dark regardless of app theme
/// - GC logo tile at top
/// - Icon + label nav items with teal active highlight
/// - User avatar at bottom
///
/// Use on all main POS screens to provide consistent navigation.
///
/// ```dart
/// GcSidebar(
///   activeRoute: '/order-center',
///   userName: 'Mehmet',
///   userInitials: 'MK',
/// )
/// ```
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Nav item descriptor
// ---------------------------------------------------------------------------

class GcNavItem {
  const GcNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
    this.itemKey,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
  final Key? itemKey;
}

const List<GcNavItem> _kNavItems = [
  GcNavItem(
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long,
    label: 'Orders',
    route: '/order-center',
    itemKey: Key('module_order'),
  ),
  GcNavItem(
    icon: Icons.table_restaurant_outlined,
    activeIcon: Icons.table_restaurant,
    label: 'Tables',
    route: '/tables',
  ),
  GcNavItem(
    icon: Icons.restaurant_menu_outlined,
    activeIcon: Icons.restaurant_menu,
    label: 'Menu',
    route: '/back-office',
  ),
  GcNavItem(
    icon: Icons.kitchen_outlined,
    activeIcon: Icons.kitchen,
    label: 'KDS',
    route: '/kitchen',
  ),
  GcNavItem(
    icon: Icons.bar_chart_outlined,
    activeIcon: Icons.bar_chart,
    label: 'Reports',
    route: '/home',
  ),
  GcNavItem(
    icon: Icons.settings_outlined,
    activeIcon: Icons.settings,
    label: 'Settings',
    route: '/settings',
  ),
];

// ---------------------------------------------------------------------------
// GcSidebar
// ---------------------------------------------------------------------------

/// Main navigation sidebar — 64px wide, dark navy.
class GcSidebar extends StatelessWidget {
  const GcSidebar({
    super.key,
    required this.activeRoute,
    this.userInitials,
    this.userName,
    this.onLogout,
  });

  /// Currently active route path (e.g. '/order-center').
  final String activeRoute;

  /// 1-2 character initials shown in the user avatar.
  final String? userInitials;

  /// Full name shown in tooltip.
  final String? userName;

  /// Optional logout callback shown when tapping the user avatar.
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      color: AppColors.navSurface,
      child: Column(
        children: [
          // ── Logo ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.coral,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'GC',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ── Nav items ───────────────────────────────────────────────────
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: _kNavItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 2),
              itemBuilder: (context, index) {
                final item = _kNavItems[index];
                final isActive = activeRoute.startsWith(item.route);
                return _GcNavTile(
                  key: item.itemKey,
                  item: item,
                  isActive: isActive,
                  onTap: () => context.go(item.route),
                );
              },
            ),
          ),

          // ── Bottom divider ───────────────────────────────────────────────
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: AppColors.navDivider,
          ),

          // ── User avatar ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Tooltip(
              message: onLogout != null
                  ? '${userName ?? 'Staff'} — tap to sign out'
                  : (userName ?? 'Staff'),
              preferBelow: false,
              child: GestureDetector(
                onTap: onLogout,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.navSurfaceHover,
                  ),
                  child: Center(
                    child: Text(
                      userInitials ?? '?',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navTextActive,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _GcNavTile
// ---------------------------------------------------------------------------

class _GcNavTile extends StatefulWidget {
  const _GcNavTile({
    super.key,
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  final GcNavItem item;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_GcNavTile> createState() => _GcNavTileState();
}

class _GcNavTileState extends State<_GcNavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.item.label,
      preferBelow: false,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
            height: 52,
            decoration: BoxDecoration(
              color: widget.isActive
                  ? const Color(0xFF2C3E55)
                  : _hovered
                      ? AppColors.navSurfaceHover
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.isActive
                      ? widget.item.activeIcon
                      : widget.item.icon,
                  size: 22,
                  color: widget.isActive
                      ? Colors.white
                      : AppColors.navText,
                ),
                const SizedBox(height: 3),
                Text(
                  widget.item.label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: widget.isActive
                        ? Colors.white
                        : AppColors.navText,
                    letterSpacing: 0.2,
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
