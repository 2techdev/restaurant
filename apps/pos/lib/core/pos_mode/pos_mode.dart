/// POS service mode — fine dining, fast food, or quick service.
///
/// Drives which [Shell] widget the order-centre route renders and which
/// fine-grain features are exposed (course/Gang panel, seat selector,
/// hold-and-fire, cover banner, split-by-seat payment).
///
/// Defaults to [PosMode.fineDining] for the POS flavour because the pilot
/// restaurant is fine-dining. Other flavours (waiter, kds, kiosk, ods) don't
/// read this provider.
///
/// Persisted via [SharedPreferences] under [_prefsKey] so a mode change
/// survives a restart — the pilot terminal stays in fine-dining across
/// app updates without any re-configuration.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';

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

  /// Deserialize from the persisted string. Unknown values fall back to
  /// [PosMode.fineDining] so an invalid pref value can never brick the UI.
  static PosMode fromName(String? raw) {
    for (final mode in PosMode.values) {
      if (mode.name == raw) return mode;
    }
    return PosMode.fineDining;
  }
}

/// SharedPreferences key for the persisted [PosMode].
const String _prefsKey = 'pos.mode';

/// StateNotifier that owns the currently active [PosMode].
///
/// Reads the persisted value on construction and writes back on every
/// [setMode] call. If SharedPreferences is still loading, the notifier
/// stays at [PosMode.fineDining] — the first persisted read will overwrite
/// it as soon as prefs are ready.
class PosModeNotifier extends StateNotifier<PosMode> {
  PosModeNotifier(this._prefs) : super(_readInitial(_prefs));

  final SharedPreferences? _prefs;

  static PosMode _readInitial(SharedPreferences? prefs) {
    if (prefs == null) return PosMode.fineDining;
    return PosMode.fromName(prefs.getString(_prefsKey));
  }

  /// Persist [mode] and notify listeners. A null [_prefs] (prefs not ready)
  /// still updates in-memory state so the UI is never blocked.
  Future<void> setMode(PosMode mode) async {
    state = mode;
    await _prefs?.setString(_prefsKey, mode.name);
  }
}

/// Currently active [PosMode] for this POS terminal.
///
/// Persists across restarts via [SharedPreferences]. Mutate via
/// `ref.read(posModeProvider.notifier).setMode(...)`.
final posModeProvider =
    StateNotifierProvider<PosModeNotifier, PosMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).valueOrNull;
  return PosModeNotifier(prefs);
});

/// Gang (course) cardinality is configured per-restaurant via
/// `RestaurantSettings.maxGangs` (1..5) and can be disabled entirely via
/// `gangsEnabled`. The former constants `kMaxGangs` / `kGangNumbers` were
/// removed on 2026-04-17 when the model moved from a hardcoded 3 to a
/// runtime setting — read `restaurantSettingsProvider` instead.
