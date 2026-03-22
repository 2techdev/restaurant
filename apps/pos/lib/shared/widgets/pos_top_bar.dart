/// Klein Professional POS — Dark Top Navigation Bar.
///
/// A 64px-tall dark bar with:
/// - Left: "GASTROCORE" wordmark (font-black, tight tracking)
/// - Center: Navigation tabs — ONGOING | TABLES | MENU | STAFF
///   Active tab: primary (#90ABFF) text + 2px bottom border primaryDim
///   Inactive: onSurfaceVariant, hover: surfaceContainerHighest bg
/// - Right: notification icon + settings icon + user avatar + name
///
/// Implements [PreferredSizeWidget] for use with [Scaffold.appBar].
///
/// ```dart
/// PosTopBar(
///   activeTab: PosTab.ongoing,
///   onTabChanged: (tab) => context.go(tab.route),
///   userName: 'Mehmet',
///   userInitials: 'MK',
/// )
/// ```
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// PosTab — navigation tab descriptor
// ---------------------------------------------------------------------------

enum PosTab {
  ongoing(label: 'ONGOING', route: '/order-center', icon: Icons.receipt_long_rounded),
  tables(label: 'TABLES', route: '/tables', icon: Icons.table_restaurant_rounded),
  menu(label: 'MENU', route: '/back-office', icon: Icons.restaurant_menu_rounded),
  staff(label: 'STAFF', route: '/settings', icon: Icons.people_rounded);

  const PosTab({
    required this.label,
    required this.route,
    required this.icon,
  });

  final String label;
  final String route;
  final IconData icon;

  static PosTab? fromRoute(String route) {
    for (final tab in values) {
      if (route.startsWith(tab.route)) return tab;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// TopBarAction
// ---------------------------------------------------------------------------

/// Describes a custom action button in the top bar.
class TopBarAction {
  const TopBarAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.badge,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Optional badge count shown on the icon.
  final int? badge;
}

// ---------------------------------------------------------------------------
// PosTopBar
// ---------------------------------------------------------------------------

/// Dark top navigation bar — 64px tall, surface (#0B0E14) background.
///
/// Center-aligned tabs replace the sidebar for main navigation.
class PosTopBar extends StatelessWidget implements PreferredSizeWidget {
  const PosTopBar({
    super.key,
    this.activeTab,
    this.onTabChanged,
    this.title,
    this.showLogo = true,
    this.showOnlineStatus = false,
    this.isOnline = true,
    this.shiftInfo,
    this.terminalInfo,
    this.userName,
    this.userInitials,
    this.userColor,
    this.actions,
    this.onBack,
    this.bottom,
    this.showTabs = true,
  });

  /// Currently active tab for highlighting.
  final PosTab? activeTab;

  /// Called when a tab is tapped.
  final ValueChanged<PosTab>? onTabChanged;

  final String? title;
  final bool showLogo;
  final bool showOnlineStatus;
  final bool isOnline;
  final String? shiftInfo;
  final String? terminalInfo;
  final String? userName;
  final String? userInitials;
  final Color? userColor;
  final List<TopBarAction>? actions;
  final VoidCallback? onBack;
  final bool showTabs;

  /// Optional bottom widget (e.g. TabBar). Adds height if provided.
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(
        64 + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceDim,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 64,
            child: Row(
              children: [
                // ── Left: Logo / back ──────────────────────────────────────
                SizedBox(
                  width: 180,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: onBack != null
                        ? _buildBackButton()
                        : _buildWordmark(),
                  ),
                ),

                // ── Center: Navigation tabs ────────────────────────────────
                if (showTabs)
                  Expanded(child: _buildTabs())
                else if (title != null)
                  Expanded(
                    child: Center(
                      child: Text(
                        title!.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  )
                else
                  const Expanded(child: SizedBox()),

                // ── Right: Actions + user ──────────────────────────────────
                SizedBox(
                  width: 180,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (showOnlineStatus) ...[
                          _buildOnlineStatus(),
                          const SizedBox(width: 10),
                        ],
                        if (shiftInfo != null) ...[
                          _buildShiftBadge(shiftInfo!),
                          const SizedBox(width: 10),
                        ],
                        if (actions != null)
                          for (final action in actions!) ...[
                            _buildActionButton(action),
                            const SizedBox(width: 6),
                          ],
                        if (userName != null || userInitials != null)
                          _buildUserAvatar(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (bottom != null) bottom!,
        ],
      ),
    );
  }

  // ── Wordmark ──────────────────────────────────────────────────────────────

  Widget _buildWordmark() {
    return const Text(
      'GASTROCORE',
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w900,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
      ),
    );
  }

  // ── Back button ───────────────────────────────────────────────────────────

  Widget _buildBackButton() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onBack,
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            Icons.arrow_back_rounded,
            size: 20,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  // ── Navigation tabs ───────────────────────────────────────────────────────

  Widget _buildTabs() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: PosTab.values.map((tab) {
        final isActive = tab == activeTab;
        return _PosNavTab(
          tab: tab,
          isActive: isActive,
          onTap: () => onTabChanged?.call(tab),
        );
      }).toList(),
    );
  }

  // ── Online status badge ───────────────────────────────────────────────────

  Widget _buildOnlineStatus() {
    final color = isOnline ? AppColors.green : AppColors.orange;
    final label = isOnline ? 'ONLINE' : 'OFFLINE';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  // ── Shift badge ───────────────────────────────────────────────────────────

  Widget _buildShiftBadge(String info) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        info.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // ── Action button ─────────────────────────────────────────────────────────

  Widget _buildActionButton(TopBarAction action) {
    return Tooltip(
      message: action.label,
      child: Stack(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: action.onTap,
              hoverColor: AppColors.surfaceContainerHighest,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  action.icon,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          if (action.badge != null && action.badge! > 0)
            Positioned(
              top: 5,
              right: 5,
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${action.badge}',
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── User avatar ───────────────────────────────────────────────────────────

  Widget _buildUserAvatar() {
    final color = userColor ?? AppColors.primary;
    final initials =
        userInitials ?? (userName?.substring(0, 1).toUpperCase() ?? '?');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (userName != null) ...[
          Text(
            userName!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
          ),
          child: Center(
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _PosNavTab — individual tab widget with hover + active state
// ---------------------------------------------------------------------------

class _PosNavTab extends StatefulWidget {
  const _PosNavTab({
    required this.tab,
    required this.isActive,
    required this.onTap,
  });

  final PosTab tab;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_PosNavTab> createState() => _PosNavTabState();
}

class _PosNavTabState extends State<_PosNavTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _hovered && !widget.isActive
                ? AppColors.surfaceContainerHighest
                : Colors.transparent,
            border: Border(
              bottom: widget.isActive
                  ? const BorderSide(
                      color: AppColors.primaryDim,
                      width: 2,
                    )
                  : BorderSide.none,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.tab.icon,
                size: 14,
                color: widget.isActive
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              const SizedBox(height: 3),
              Text(
                widget.tab.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: widget.isActive
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
