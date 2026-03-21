import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/utils/money.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/customer_entity.dart';
import 'package:gastrocore_pos/features/customers/presentation/widgets/loyalty_badge.dart';

class CustomerCard extends StatelessWidget {
  final CustomerEntity customer;
  final VoidCallback onTap;

  const CustomerCard({
    super.key,
    required this.customer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initials = customer.name
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();
    final tierColor = _tierColor(customer.tier);

    return Material(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.primary.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: tierColor, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: tierColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            customer.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (customer.hasBirthdayThisWeek) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.cake_rounded,
                              size: 13, color: AppColors.purple),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (customer.phone != null) ...[
                          const Icon(Icons.phone_rounded,
                              size: 11, color: AppColors.textDim),
                          const SizedBox(width: 3),
                          Text(
                            customer.phone!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          '${customer.totalOrders} Best.',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textDim),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Right side: tier + points
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  LoyaltyBadge(tier: customer.tier),
                  const SizedBox(height: 4),
                  Text(
                    '${customer.loyaltyPoints} Pts',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.yellow,
                    ),
                  ),
                  Text(
                    Money(customer.totalSpent).format('CHF'),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textDim),
                  ),
                ],
              ),

              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }

  Color _tierColor(CustomerTier tier) {
    return switch (tier) {
      CustomerTier.bronze => const Color(0xFFCD7F32),
      CustomerTier.silver => const Color(0xFFC0C0C0),
      CustomerTier.gold => AppColors.yellow,
    };
  }
}
