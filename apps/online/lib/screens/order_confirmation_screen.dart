/// Order confirmation screen — shown after successful order placement.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
            child: Column(
              children: [
                // Success icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: OnlineColors.greenLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 56,
                    color: OnlineColors.green,
                  ),
                ),
                const SizedBox(height: 28),

                Text(
                  l10n.orderPlaced,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: OnlineColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.orderSentToKitchen,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: OnlineColors.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Order number card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: OnlineColors.bgCard,
                    borderRadius: BorderRadius.circular(kRadiusXl),
                    border: Border.all(color: OnlineColors.divider),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Bestellnummer',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: OnlineColors.textSecondary,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '#$orderNumber',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: OnlineColors.primary,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: OnlineColors.pillActiveBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: OnlineColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              l10n.estimatedWait('20'),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: OnlineColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // Track order button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => context.go(
                      '/$restaurantId/tracking/$orderId',
                    ),
                    icon: const Icon(Icons.radar_rounded),
                    label: Text(l10n.trackOrder),
                  ),
                ),
                const SizedBox(height: 12),

                // Back to menu
                TextButton(
                  onPressed: () => context.go('/$restaurantId/menu'),
                  child: Text(
                    l10n.backToMenu,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: OnlineColors.primary,
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Powered by
                Text(
                  'Powered by GastroCore',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: OnlineColors.textDim,
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
