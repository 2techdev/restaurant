import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/customer_entity.dart';

class LoyaltyBadge extends StatelessWidget {
  final CustomerTier tier;
  final bool large;

  const LoyaltyBadge({super.key, required this.tier, this.large = false});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _tierData(tier);
    final fontSize = large ? 13.0 : 11.0;
    final iconSize = large ? 14.0 : 11.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 8,
        vertical: large ? 6 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, IconData) _tierData(CustomerTier tier) {
    return switch (tier) {
      CustomerTier.bronze => (
          'Bronze',
          const Color(0xFFCD7F32),
          Icons.star_rounded,
        ),
      CustomerTier.silver => (
          'Silber',
          const Color(0xFFC0C0C0),
          Icons.star_rounded,
        ),
      CustomerTier.gold => (
          'Gold',
          AppColors.yellow,
          Icons.workspace_premium_rounded,
        ),
    };
  }
}
