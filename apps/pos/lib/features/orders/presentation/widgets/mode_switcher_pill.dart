/// Mode-switcher pill — one-tap mode change from any primary screen.
///
/// Lives in the sidebar head (`_Rail`), floor-plan top-nav and the
/// Mixed hub header. Tapping pops a 3-option popup; selecting writes
/// the new mode through [restaurantConfigOverrideProvider] and routes
/// to the new mode's home, preserving the currently active ticket so
/// the operator's in-flight sale isn't lost in the transition.
///
/// Faz A of the 2026-05-17 UX overhaul. Replaces the
/// Settings → POS Modu radio as the primary mode-switch entry point.
library;
// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/features/fast_sale/domain/restaurant_config.dart';
import 'package:gastrocore_pos/features/fast_sale/presentation/providers/restaurant_config_provider.dart';

/// Per-mode visual identity. Drives the pill colour, icon and label so
/// the operator gets an at-a-glance read of the active flow without
/// reading text.
class ModeIdentity {
  const ModeIdentity({
    required this.label,
    required this.icon,
    required this.tint,
    required this.tintBg,
  });
  final String label;
  final IconData icon;
  final Color tint;
  final Color tintBg;

  static ModeIdentity of(PosMode m) {
    return switch (m) {
      PosMode.fastSale => const ModeIdentity(
          label: 'Schnellverkauf',
          icon: Icons.flash_on_rounded,
          tint: Color(0xFFEA580C),
          tintBg: Color(0xFFFFEDD5),
        ),
      PosMode.hybrid => const ModeIdentity(
          label: 'Tische',
          icon: Icons.restaurant_rounded,
          tint: Color(0xFF1E40AF),
          tintBg: Color(0xFFDBEAFE),
        ),
      PosMode.mixed => const ModeIdentity(
          label: 'Mixed',
          icon: Icons.dashboard_rounded,
          tint: Color(0xFF15803D),
          tintBg: Color(0xFFDCFCE7),
        ),
    };
  }
}

/// Compact / expanded layouts so the pill can adapt to the host.
/// `compact` renders icon-only (sidebar); `expanded` shows icon + label
/// + chevron (floor-plan / hub headers).
enum ModeSwitcherStyle { compact, expanded }

class ModeSwitcherPill extends ConsumerWidget {
  const ModeSwitcherPill({
    super.key,
    this.style = ModeSwitcherStyle.expanded,
  });
  final ModeSwitcherStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(effectiveRestaurantConfigProvider);
    final current = cfg.posMode;
    final id = ModeIdentity.of(current);
    return PopupMenuButton<PosMode>(
      tooltip: 'Modus wechseln',
      offset: const Offset(0, 44),
      position: PopupMenuPosition.under,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      itemBuilder: (_) => [
        for (final m in const [
          PosMode.fastSale,
          PosMode.hybrid,
          PosMode.mixed,
        ])
          PopupMenuItem<PosMode>(
            value: m,
            child: _ModeOption(mode: m, current: current == m),
          ),
      ],
      onSelected: (next) async {
        if (next == current) return;
        // Persist + route. Cart state (currentTicketProvider) is NOT
        // cleared so the in-flight ticket survives the transition; the
        // operator can resume it via the rail Order entry on the new
        // shell. Future enhancement: explicit transfer prompts when
        // moving table→counter or vice versa.
        await ref
            .read(restaurantConfigOverrideProvider.notifier)
            .setOverride(cfg.copyWith(
              posMode: next,
              featureTisch: next == PosMode.fastSale
                  ? cfg.featureTisch
                  : true,
            ));
        if (!context.mounted) return;
        final route = switch (next) {
          PosMode.fastSale => AppRoutes.fastSale,
          PosMode.hybrid => AppRoutes.tables,
          PosMode.mixed => AppRoutes.mixedHub,
        };
        context.go(route);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: style == ModeSwitcherStyle.compact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: id.tintBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: id.tint.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: id.tint.withValues(alpha: 0.10),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(id.icon, size: 16, color: id.tint),
            if (style == ModeSwitcherStyle.expanded) ...[
              const SizedBox(width: 7),
              Text(
                id.label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: id.tint,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, size: 14, color: id.tint),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.mode, required this.current});
  final PosMode mode;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final id = ModeIdentity.of(mode);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: id.tintBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(id.icon, size: 16, color: id.tint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  id.label,
                  style: TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: id.tint,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _subtitleFor(mode),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10.5,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          if (current) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_rounded, size: 16, color: id.tint),
          ],
        ],
      ),
    );
  }

  String _subtitleFor(PosMode m) => switch (m) {
        PosMode.fastSale => 'Sepete direkt — sayaç / theke',
        PosMode.hybrid => 'Masa planı + servis akışı',
        PosMode.mixed => 'Sayaç + masa, tek hub',
      };
}
