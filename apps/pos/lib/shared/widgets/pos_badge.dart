/// Badges and status indicators following the Stitch "Precision POS Framework".
///
/// Provides four badge types:
///
/// - [PosStatusBadge] — Online/offline connectivity indicator with animated dot.
/// - [PosTableBadge] — Table name chip with customizable color accent.
/// - [PosCountBadge] — Notification/pending-items counter badge.
/// - [PosRoleBadge] — User role chip (e.g. Manager, Waiter, Kitchen).
///
/// All badges follow the "No-Line" rule — using tinted backgrounds (dim
/// semantic colors) instead of 1px borders for visual separation.
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// PosStatusBadge
// ---------------------------------------------------------------------------

/// An online/offline status indicator with a colored dot and label.
///
/// Displays a green dot + "ONLINE" or orange dot + "OFFLINE" based on
/// the [isOnline] flag.
///
/// ```dart
/// PosStatusBadge(isOnline: connectionState.isConnected)
/// ```
class PosStatusBadge extends StatelessWidget {
  const PosStatusBadge({
    super.key,
    required this.isOnline,
  });

  /// Whether the system is currently online.
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppColors.green : AppColors.orange;
    final bgColor = isOnline ? AppColors.greenDim : AppColors.orangeDim;
    final label = isOnline ? 'ONLINE' : 'OFFLINE';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
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
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PosTableBadge
// ---------------------------------------------------------------------------

/// A compact chip showing a table name with a colored accent background.
///
/// Uses a tinted (dim) background derived from the provided [color]
/// — following the "No-Line" rule.
///
/// ```dart
/// PosTableBadge(tableName: 'T5', color: AppColors.red)
/// ```
class PosTableBadge extends StatelessWidget {
  const PosTableBadge({
    super.key,
    required this.tableName,
    this.color,
  });

  /// Table display name, e.g. "T5", "Bar 2", "Terrace 1".
  final String tableName;

  /// Accent color for the badge. Defaults to [AppColors.accent].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accentColor = color ?? AppColors.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tableName,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: accentColor,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PosCountBadge
// ---------------------------------------------------------------------------

/// A small circular or pill-shaped counter badge for notifications,
/// pending items, and unread counts.
///
/// Automatically switches between circular (single digit) and pill
/// (multi-digit) shape. Hides when [count] is 0.
///
/// ```dart
/// PosCountBadge(count: 3, color: AppColors.red)
/// ```
class PosCountBadge extends StatelessWidget {
  const PosCountBadge({
    super.key,
    required this.count,
    this.color,
    this.size = 20,
  });

  /// Number to display. Badge is hidden when 0.
  final int count;

  /// Background color. Defaults to [AppColors.red].
  final Color? color;

  /// Minimum size (height and min-width). Defaults to 20.
  final double size;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final bgColor = color ?? AppColors.red;
    final displayText = count > 99 ? '99+' : count.toString();

    return Container(
      constraints: BoxConstraints(
        minWidth: size,
        minHeight: size,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Center(
        child: Text(
          displayText,
          style: TextStyle(
            fontSize: size * 0.55,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PosRoleBadge
// ---------------------------------------------------------------------------

/// A role indicator chip showing a user role with a semantic color.
///
/// Uses a tinted background (color at 10% opacity) with the color for text
/// — following the "No-Line" rule.
///
/// ```dart
/// PosRoleBadge(role: 'Manager', color: AppColors.purple)
/// PosRoleBadge(role: 'Waiter', color: AppColors.accent)
/// PosRoleBadge(role: 'Kitchen', color: AppColors.orange)
/// ```
class PosRoleBadge extends StatelessWidget {
  const PosRoleBadge({
    super.key,
    required this.role,
    required this.color,
  });

  /// Role display text, e.g. "Manager", "Waiter", "Kitchen".
  final String role;

  /// Semantic color for the badge.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        role,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
