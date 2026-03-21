/// Colored status badge / chip for displaying order, table, or ticket status.
library;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A compact colored label used to show lifecycle status at a glance.
///
/// ```dart
/// StatusBadge(label: 'In Progress', color: AppColors.orange)
/// StatusBadge.fromTicketStatus(TicketStatus.completed)
/// ```
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  /// Optional explicit background color (defaults to a dim variant of [color]).
  final Color? backgroundColor;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.backgroundColor,
  });

  // ---------------------------------------------------------------------------
  // Convenience constructors for common status types
  // ---------------------------------------------------------------------------

  /// Create a badge for a ticket status string (e.g. "inProgress").
  factory StatusBadge.fromStatusName(String statusName) {
    return StatusBadge(
      label: _formatLabel(statusName),
      color: _colorForStatus(statusName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? color.withValues(alpha: 0.15);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static String _formatLabel(String statusName) {
    // camelCase -> "Camel Case"
    final result = StringBuffer();
    for (int i = 0; i < statusName.length; i++) {
      final ch = statusName[i];
      if (i > 0 && ch == ch.toUpperCase() && ch != ch.toLowerCase()) {
        result.write(' ');
      }
      result.write(i == 0 ? ch.toUpperCase() : ch);
    }
    return result.toString();
  }

  static Color _colorForStatus(String statusName) {
    switch (statusName.toLowerCase()) {
      case 'completed':
      case 'fullypaid':
      case 'available':
        return AppColors.green;
      case 'inprogress':
      case 'preparing':
      case 'open':
        return AppColors.orange;
      case 'cancelled':
      case 'voided':
      case 'failed':
      case 'occupied':
        return AppColors.red;
      case 'ready':
      case 'sent':
        return AppColors.primary;
      case 'draft':
      case 'pending':
        return AppColors.textSecondary;
      case 'reserved':
        return AppColors.purple;
      default:
        return AppColors.textSecondary;
    }
  }
}
