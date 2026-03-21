/// Landing screen — restaurant branding, language selector, "View Menu" CTA.
/// Entry point when customer scans QR code: /{restaurantId}?table={n}
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gastrocore_online/core/theme/app_theme.dart';
import 'package:gastrocore_online/domain/models/menu_models.dart';
import 'package:gastrocore_online/l10n/app_localizations.dart';
import 'package:gastrocore_online/providers/cart_provider.dart';
import 'package:gastrocore_online/providers/locale_provider.dart';
import 'package:gastrocore_online/providers/menu_provider.dart';
import 'package:gastrocore_online/widgets/language_selector.dart';

class LandingScreen extends ConsumerStatefulWidget {
  const LandingScreen({
    super.key,
    required this.restaurantId,
    this.tableFromQr,
  });

  final String restaurantId;
  final int? tableFromQr;

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends ConsumerState<LandingScreen> {
  @override
  void initState() {
    super.initState();
    // Pre-fill table number from QR and initialise cart order type
    if (widget.tableFromQr != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(cartProvider.notifier).setTableNumber(widget.tableFromQr);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final menu = ref.watch(menuProvider(widget.restaurantId));

    return Scaffold(
      body: menu.when(
        loading: () => _buildContent(context, l10n, null),
        error: (e, _) => _buildContent(context, l10n, null),
        data: (m) => _buildContent(context, l10n, m.restaurant),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppLocalizations l10n,
    OnlineRestaurant? restaurant,
  ) {
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Stack(
      children: [
        // Background cover image / gradient
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  OnlineColors.primary.withOpacity(0.85),
                  OnlineColors.primaryDark,
                ],
              ),
            ),
            child: restaurant?.coverImageUrl != null
                ? Image.network(
                    restaurant!.coverImageUrl!,
                    fit: BoxFit.cover,
                    color: Colors.black38,
                    colorBlendMode: BlendMode.darken,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  )
                : null,
          ),
        ),

        // Language selector — top right
        Positioned(
          top: MediaQuery.paddingOf(context).top + 16,
          right: 16,
          child: const LanguageSelector(),
        ),

        // Main content
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: screenHeight * 0.55,
          child: Container(
            decoration: const BoxDecoration(
              color: OnlineColors.bgCard,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(kRadiusXl),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: _BottomContent(
              restaurant: restaurant,
              restaurantId: widget.restaurantId,
              tableFromQr: widget.tableFromQr,
            ),
          ),
        ),

        // Logo / restaurant icon
        Positioned(
          top: screenHeight * 0.45 - 48,
          left: 0,
          right: 0,
          child: Center(
            child: _RestaurantLogo(restaurant: restaurant),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Restaurant logo
// ---------------------------------------------------------------------------

class _RestaurantLogo extends StatelessWidget {
  const _RestaurantLogo({this.restaurant});
  final OnlineRestaurant? restaurant;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: OnlineColors.bgCard,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: restaurant?.logoUrl != null
            ? Image.network(restaurant!.logoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _defaultIcon())
            : _defaultIcon(),
      ),
    );
  }

  Widget _defaultIcon() => const Center(
        child: Icon(
          Icons.restaurant,
          size: 48,
          color: OnlineColors.primary,
        ),
      );
}

// ---------------------------------------------------------------------------
// Bottom card content
// ---------------------------------------------------------------------------

class _BottomContent extends ConsumerWidget {
  const _BottomContent({
    required this.restaurant,
    required this.restaurantId,
    this.tableFromQr,
  });

  final OnlineRestaurant? restaurant;
  final String restaurantId;
  final int? tableFromQr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Restaurant name
        Text(
          restaurant?.name ?? 'Restaurant',
          style: Theme.of(context).textTheme.headlineLarge,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (restaurant?.description != null) ...[
          const SizedBox(height: 8),
          Text(
            restaurant!.description!,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: OnlineColors.textSecondary),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 16),

        // Table chip
        if (tableFromQr != null) ...[
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: OnlineColors.primaryLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.table_restaurant,
                    size: 16, color: OnlineColors.primary),
                const SizedBox(width: 6),
                Text(
                  l10n.tableAutoFilled('$tableFromQr'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: OnlineColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Open/closed status
        if (restaurant != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: restaurant!.isOpen
                      ? OnlineColors.green
                      : OnlineColors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                restaurant!.isOpen ? 'Open' : 'Closed',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: restaurant!.isOpen
                      ? OnlineColors.green
                      : OnlineColors.red,
                ),
              ),
              if (restaurant!.isOpen) ...[
                const SizedBox(width: 12),
                Icon(Icons.access_time,
                    size: 14, color: OnlineColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '~${restaurant!.estimatedWaitMinutes} min',
                  style: const TextStyle(
                    fontSize: 13,
                    color: OnlineColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
        ] else
          const SizedBox(height: 24),

        const Spacer(),

        // CTA button
        ElevatedButton.icon(
          onPressed: restaurant?.isOpen == false
              ? null
              : () {
                  final tableQuery =
                      tableFromQr != null ? '?table=$tableFromQr' : '';
                  context.go('/$restaurantId/menu$tableQuery');
                },
          icon: const Icon(Icons.restaurant_menu),
          label: Text(l10n.viewMenu),
        ),

        const SizedBox(height: 16),

        // Powered by
        Text(
          'Powered by GastroCore',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: OnlineColors.textDim),
        ),
      ],
    );
  }
}
