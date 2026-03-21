/// Order confirmation screen — shown after successful order placement.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:gastrocore_online/core/theme/app_theme.dart';
import 'package:gastrocore_online/l10n/app_localizations.dart';

class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({
    super.key,
    required this.restaurantId,
    required this.orderId,
    required this.orderNumber,
  });

  final String restaurantId;
  final String orderId;
  final String orderNumber;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: OnlineColors.bgPage,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(),

              // Success animation
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: OnlineColors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  size: 72,
                  color: OnlineColors.green,
                ),
              ),
              const SizedBox(height: 32),

              Text(
                l10n.orderPlaced,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: OnlineColors.textPrimary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Order number
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: OnlineColors.primaryLight,
                  borderRadius: BorderRadius.circular(kRadiusLarge),
                ),
                child: Text(
                  l10n.orderNumber(orderNumber),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: OnlineColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Message
              Text(
                l10n.orderSentToKitchen,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: OnlineColors.textSecondary,
                      height: 1.5,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Estimated wait
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.access_time,
                      size: 18, color: OnlineColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    l10n.estimatedWait('20'),
                    style: const TextStyle(
                      fontSize: 15,
                      color: OnlineColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Track order button
              ElevatedButton.icon(
                onPressed: () => context.go(
                  '/$restaurantId/tracking/$orderId',
                ),
                icon: const Icon(Icons.radar),
                label: Text(l10n.trackOrder),
              ),
              const SizedBox(height: 12),

              // Back to menu
              TextButton(
                onPressed: () => context.go('/$restaurantId/menu'),
                child: Text(l10n.backToMenu),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
