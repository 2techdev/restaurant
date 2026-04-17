/// POS service mode — fine dining, fast food, or quick service.
///
/// Drives which [Shell] widget the order-centre route renders and which
/// fine-grain features are exposed (course/Gang panel, seat selector,
/// hold-and-fire, cover banner, split-by-seat payment).
///
/// Defaults to [PosMode.fineDining] for the POS flavour because the pilot
/// restaurant is fine-dining. Other flavours (waiter, kds, kiosk, ods) don't
/// read this provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which operational mode the POS terminal is running in.
enum PosMode {
  /// Multi-course table service with seat/Gang/hold-fire primitives.
  fineDining,

  /// Counter ordering — single list, quick-pay CTA, no courses.
  fastFood,

  /// Self-service quick service — still a placeholder, v2.
  quickService;

  /// True when the UI should surface the course (Gang) panel.
  bool get showsGangs => this == PosMode.fineDining;

  /// True when the UI should show cover count + captain banner.
  bool get showsCoverBanner => this == PosMode.fineDining;

  /// True when hold & fire controls should be exposed on each Gang row.
  bool get showsHoldFire => this == PosMode.fineDining;

  /// True when split-by-seat is available on the payment screen.
  bool get showsSplitBySeat => this == PosMode.fineDining;

  /// Display name for debug / settings UI. Copy is deliberately untranslated
  /// — fine-dining vs fast-food are operator-level modes, not guest-facing.
  String get label => switch (this) {
        PosMode.fineDining => 'Fine Dining',
        PosMode.fastFood => 'Fast Food',
        PosMode.quickService => 'Quick Service',
      };
}

/// Currently active [PosMode] for this POS terminal. In-memory only for now;
/// the persisted setting lives under [RestaurantSettings] and is wired in a
/// follow-up.
final posModeProvider = StateProvider<PosMode>((ref) => PosMode.fineDining);

/// Maximum number of Gangs (courses) supported by the UI. Product decision
/// 2026-04-17: pilot restaurant is capped at 3 (Vorspeise / Hauptgang /
/// Dessert in Swiss-German). Raising this requires widening the Gang chip
/// row and verifying printer routing.
const int kMaxGangs = 3;

/// Indexable Gang numbers (1-based) — `[1, 2, 3]`.
const List<int> kGangNumbers = [1, 2, 3];
