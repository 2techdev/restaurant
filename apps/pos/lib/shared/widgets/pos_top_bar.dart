/// Top navigation bar following the Stitch "Precision POS Framework".
///
/// A 56px-tall bar that provides:
/// - GastroCore logo with gradient accent text
/// - Online/offline status indicator
/// - Shift and terminal information
/// - User avatar with initials
/// - Custom action buttons
/// - Optional back navigation
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

/// Describes a custom action button displayed in the top bar.
class TopBarAction {
  const TopBarAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  /// Tooltip / accessibility label.
  final String label;

  /// Icon displayed inside the action button.
  final IconData icon;

  /// Tap callback.
  final VoidCallback onTap;
}

// ---------------------------------------------------------------------------
// PosTopBar
// ---------------------------------------------------------------------------

/// Top navigation bar used across POS screens.
///
/// Height is fixed at 56px. Background uses [AppColors.surfaceContainer]
/// to sit one level above the scaffold background, following Stitch surface
/// hierarchy. No bottom border — "No-Line" rule.
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
  });

  /// Optional title displayed after the logo or back button.
  final String? title;

  /// Whether to show the GastroCore logo.
  final bool showLogo;

  /// Whether to show the online/offline status indicator.
  final bool showOnlineStatus;

  /// Current connectivity state. Only used when [showOnlineStatus] is true.
  final bool isOnline;

  /// Shift identifier text, e.g. "Shift #402".
  final String? shiftInfo;

  /// Terminal identifier text, e.g. "Terminal 01 • Main Floor".
  final String? terminalInfo;

  /// User's display name shown next to the avatar.
  final String? userName;

  /// One or two characters shown inside the avatar circle.
  final String? userInitials;

  /// Avatar circle background color. Defaults to [AppColors.accent].
  final Color? userColor;

  /// Custom action buttons displayed before the user avatar.
  final List<TopBarAction>? actions;

  /// When non-null, a back arrow is shown as the first element and this
  /// callback fires on tap.
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: AppColors.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 24),
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
            const SizedBox(width: 16),
          ],

          const Spacer(),

          // -- Center / info section --
          if (terminalInfo != null || shiftInfo != null) ...[
            _buildInfoSection(),
            const SizedBox(width: 16),
          ],

          // -- Right section --
          if (actions != null)
            for (final action in actions!) ...[
              _buildActionButton(action),
              const SizedBox(width: 8),
            ],
          if (userName != null || userInitials != null) _buildUserAvatar(),
        ],
      ),
    );
  }

  Widget _buildBackButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
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
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryContainer],
          ).createShader(bounds),
          child: const Text(
            'Core',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white, // masked by shader
              letterSpacing: -0.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineStatus() {
    final color = isOnline ? AppColors.green : AppColors.orange;
    final label = isOnline ? 'ONLINE' : 'OFFLINE';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (terminalInfo != null)
          Text(
            terminalInfo!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        if (shiftInfo != null)
          Text(
            shiftInfo!,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textDim,
            ),
          ),
      ],
    );
  }

  Widget _buildActionButton(TopBarAction action) {
    return Tooltip(
      message: action.label,
      child: Material(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: action.onTap,
          splashColor: AppColors.textPrimary.withValues(alpha: 0.06),
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
    );
  }

  Widget _buildUserAvatar() {
    final color = userColor ?? AppColors.accent;
    final initials = userInitials ?? (userName?.substring(0, 1).toUpperCase() ?? '?');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (userName != null) ...[
          Text(
            userName!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
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
