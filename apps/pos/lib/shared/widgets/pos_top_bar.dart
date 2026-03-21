/// Top navigation bar — Lightspeed-inspired professional POS UI.
///
/// A 56px-tall white bar with:
/// - GastroCore logo (teal accent) or back button
/// - Online/offline status badge
/// - Shift and terminal information
/// - User avatar with initials
/// - Custom action icon buttons
///
/// Implements [PreferredSizeWidget] for use with [Scaffold.appBar].
///
/// ```dart
/// PosTopBar(
///   showLogo: true,
///   showOnlineStatus: true,
///   isOnline: true,
///   shiftInfo: 'Shift #402',
///   terminalInfo: 'Terminal 01 • Main Floor',
///   userName: 'Mehmet',
///   userInitials: 'MK',
/// )
/// ```
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

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

/// Top navigation bar used across POS screens.
///
/// White background with a bottom border. No sidebar — use [GcSidebar] for
/// the main navigation rail.
class PosTopBar extends StatelessWidget implements PreferredSizeWidget {
  const PosTopBar({
    super.key,
    this.title,
    this.showLogo = false,
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
  });

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

  /// Optional bottom widget (e.g. TabBar). Adds height if provided.
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(
        56 + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: Row(
              children: [
                // -- Left section --
                if (onBack != null) _buildBackButton(),
                if (showLogo) ...[
                  _buildLogo(),
                  const SizedBox(width: 16),
                ],
                if (title != null) ...[
                  Text(
                    title!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                if (showOnlineStatus) ...[
                  _buildOnlineStatus(),
                  const SizedBox(width: 12),
                ],
                if (terminalInfo != null) ...[
                  Text(
                    terminalInfo!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textDim,
                    ),
                  ),
                ],

                const Spacer(),

                // -- Right section --
                if (shiftInfo != null) ...[
                  _buildShiftBadge(shiftInfo!),
                  const SizedBox(width: 12),
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
          if (bottom != null) bottom!,
        ],
      ),
    );
  }

  Widget _buildBackButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onBack,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.arrow_back_rounded,
              size: 22,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
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
        const Text(
          'Core',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineStatus() {
    final color = isOnline ? AppColors.green : AppColors.orange;
    final label = isOnline ? 'ONLINE' : 'OFFLINE';
    final bg = isOnline ? AppColors.greenDim : AppColors.orangeDim;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftBadge(String info) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        info,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildActionButton(TopBarAction action) {
    return Tooltip(
      message: action.label,
      child: Stack(
        children: [
          Material(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: action.onTap,
              splashColor: AppColors.primary.withValues(alpha: 0.08),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  action.icon,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          if (action.badge != null && action.badge! > 0)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: AppColors.red,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${action.badge}',
                    style: const TextStyle(
                      fontSize: 9,
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
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.12),
          ),
          child: Center(
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 13,
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
