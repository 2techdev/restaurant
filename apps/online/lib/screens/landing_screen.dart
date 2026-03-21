/// Landing screen — restaurant hero, info strip, "View Menu" CTA.
/// Entry point when customer scans QR code: /{restaurantId}?table={n}
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gastrocore_online/core/theme/app_theme.dart';
import 'package:gastrocore_online/domain/models/menu_models.dart';
import 'package:gastrocore_online/l10n/app_localizations.dart';
import 'package:gastrocore_online/providers/cart_provider.dart';
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
    if (widget.tableFromQr != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(cartProvider.notifier).setTableNumber(widget.tableFromQr);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(menuProvider(widget.restaurantId));

    return Scaffold(
      backgroundColor: OnlineColors.bgPage,
      body: menu.when(
        loading: () => _buildPage(context, null),
        error: (_, __) => _buildPage(context, null),
        data: (m) => _buildPage(context, m.restaurant),
      ),
    );
  }

  Widget _buildPage(BuildContext context, OnlineRestaurant? restaurant) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroSection(
            restaurant: restaurant,
            restaurantId: widget.restaurantId,
          ),
          _InfoSection(
            restaurant: restaurant,
            restaurantId: widget.restaurantId,
            tableFromQr: widget.tableFromQr,
          ),
          _FooterSection(restaurantId: widget.restaurantId),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero section — cover image with overlay + language selector
// ---------------------------------------------------------------------------

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.restaurant, required this.restaurantId});
  final OnlineRestaurant? restaurant;
  final String restaurantId;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Cover image
        SizedBox(
          height: 280,
          width: double.infinity,
          child: restaurant?.coverImageUrl != null
              ? Image.network(
                  restaurant!.coverImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _defaultCover(),
                )
              : _defaultCover(),
        ),

        // Gradient overlay
        Container(
          height: 280,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x40000000),
                Color(0xD0000000),
              ],
              stops: [0.0, 1.0],
            ),
          ),
        ),

        // Language selector — top right
        Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          right: 16,
          child: const LanguageSelector(),
        ),

        // Restaurant info overlaid at bottom of hero
        Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                restaurant?.name ?? 'Demo Restaurant Zürich',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                  shadows: [
                    const Shadow(
                      color: Color(0x80000000),
                      blurRadius: 8,
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (restaurant?.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  restaurant!.description!,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              // Info strip: rating | delivery time | min order
              Row(
                children: [
                  _InfoChip(
                    icon: Icons.star_rounded,
                    iconColor: const Color(0xFFFFC107),
                    label: '4.8',
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.access_time_rounded,
                    label: restaurant != null
                        ? '${restaurant!.estimatedWaitMinutes}–${restaurant!.estimatedWaitMinutes + 10} min'
                        : '20–30 min',
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.shopping_bag_outlined,
                    label: 'Min. CHF 0',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _defaultCover() => Container(
        color: OnlineColors.charcoal,
        child: Center(
          child: Icon(
            Icons.restaurant,
            size: 64,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
      );
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.iconColor = Colors.white70,
  });
  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info section — status, table chip, CTA
// ---------------------------------------------------------------------------

class _InfoSection extends ConsumerWidget {
  const _InfoSection({
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

    return Container(
      color: OnlineColors.bgCard,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Open / closed status
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: restaurant?.isOpen != false
                      ? OnlineColors.green
                      : OnlineColors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                restaurant?.isOpen != false ? 'Jetzt geöffnet' : 'Geschlossen',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: restaurant?.isOpen != false
                      ? OnlineColors.green
                      : OnlineColors.red,
                ),
              ),
              if (restaurant?.isOpen == true) ...[
                const SizedBox(width: 16),
                Icon(
                  Icons.delivery_dining_rounded,
                  size: 15,
                  color: OnlineColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Lieferung & Abholung',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: OnlineColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),

          // Table chip from QR
          if (tableFromQr != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: OnlineColors.pillActiveBg,
                borderRadius: BorderRadius.circular(kRadiusMedium),
                border: Border.all(
                  color: OnlineColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.table_restaurant,
                      size: 16, color: OnlineColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    l10n.tableAutoFilled('$tableFromQr'),
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

          const SizedBox(height: 24),

          // CTA button
          ElevatedButton(
            onPressed: restaurant?.isOpen == false
                ? null
                : () {
                    final tableQuery =
                        tableFromQr != null ? '?table=$tableFromQr' : '';
                    context.go('/$restaurantId/menu$tableQuery');
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: OnlineColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kRadiusLarge),
              ),
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.restaurant_menu_rounded, size: 20),
                const SizedBox(width: 10),
                Text(
                  l10n.viewMenu,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer section
// ---------------------------------------------------------------------------

class _FooterSection extends StatelessWidget {
  const _FooterSection({required this.restaurantId});
  final String restaurantId;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: OnlineColors.bgPage,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Restaurant details
          _FooterBlock(
            icon: Icons.location_on_outlined,
            text: 'Bahnhofstrasse 1, 8001 Zürich',
          ),
          const SizedBox(height: 10),
          _FooterBlock(
            icon: Icons.phone_outlined,
            text: '+41 44 000 00 00',
          ),
          const SizedBox(height: 10),
          _FooterBlock(
            icon: Icons.access_time_outlined,
            text: 'Mo–Fr 11:30–14:00, 17:30–22:00',
          ),
          const SizedBox(height: 24),
          const Divider(color: OnlineColors.divider),
          const SizedBox(height: 16),

          // Legal links
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _FooterLink(label: 'Impressum'),
              _FooterLink(label: 'Datenschutz'),
              _FooterLink(label: 'AGB'),
            ],
          ),
          const SizedBox(height: 20),

          // Powered by
          Text(
            'Powered by GastroCore',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: OnlineColors.textDim,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterBlock extends StatelessWidget {
  const _FooterBlock({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: OnlineColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: OnlineColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 12,
        color: OnlineColors.textSecondary,
        decoration: TextDecoration.underline,
        decorationColor: OnlineColors.textDim,
      ),
    );
  }
}
