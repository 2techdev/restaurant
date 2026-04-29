/// Riverpod provider supplying the active happy-hour rule list.
///
/// Rules are persisted via [SettingsRepository] (SharedPreferences under
/// `settings.v1.happyHour`). The list is hydrated on first access; the
/// in-memory state starts from [happyHourDefaultRules] so the POS grid
/// evaluator always has a synchronous answer — even before disk load
/// completes — and matches whatever the operator saves afterwards.
library;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/features/pricing/domain/happy_hour_rule.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/happy_hour_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/repositories/settings_repository.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';

/// Default rule set for the pilot.
///
/// Exposed as a top-level constant so tests can inject it directly without
/// spinning up a ProviderContainer. Also used as the first-launch seed —
/// if the SharedPreferences blob is empty the notifier writes this list
/// out on hydrate so the Back Office editor shows a sensible starting
/// point instead of a blank page.
final happyHourDefaultRules = <HappyHourRule>[
  HappyHourRule(
    id: 'hh-beer-pilot',
    name: 'Happy Hour Bira',
    categoryId: 'beverages',
    productNameContains: 'bira',
    discountPercent: 20,
    startTime: const TimeOfDay(hour: 17, minute: 0),
    endTime: const TimeOfDay(hour: 19, minute: 0),
    daysOfWeek: const [1, 2, 3, 4, 5], // Mon-Fri (ISO)
    active: true,
  ),
];

/// Active happy-hour rules. Stays synchronous so the order-panel addItem
/// hot path can `ref.read` without awaiting.
final happyHourRulesProvider =
    StateNotifierProvider<HappyHourRulesNotifier, List<HappyHourRule>>((ref) {
  final notifier = HappyHourRulesNotifier();
  // Hydrate from disk as soon as the repository future resolves. We do not
  // `watch` the repo with a full state reset — that would clobber in-memory
  // saves — instead we pull the value once and call [hydrate] idempotently.
  ref.listen(
    settingsRepositoryProvider,
    (_, next) => next.whenData(notifier.hydrate),
    fireImmediately: true,
  );
  return notifier;
});

class HappyHourRulesNotifier extends StateNotifier<List<HappyHourRule>> {
  HappyHourRulesNotifier() : super(List.unmodifiable(happyHourDefaultRules));

  SettingsRepository? _repo;
  bool _hydrated = false;

  /// First-run hydration. Reads persisted rules; if none are stored yet
  /// (typically on a fresh install) seeds [happyHourDefaultRules] so the
  /// Back Office editor has something to show.
  Future<void> hydrate(SettingsRepository repo) async {
    if (_hydrated) {
      _repo = repo;
      return;
    }
    _hydrated = true;
    _repo = repo;
    try {
      final settings = await repo.loadHappyHourSettings();
      if (settings.rules.isEmpty) {
        await repo.saveHappyHourSettings(
          HappyHourSettings(rules: happyHourDefaultRules),
        );
        state = List.unmodifiable(happyHourDefaultRules);
      } else {
        state = List.unmodifiable(settings.rules);
      }
    } catch (_) {
      // Keep the default state on any load failure so the POS grid keeps
      // working. A subsequent save will repair the blob.
    }
  }

  /// Create or replace a rule by id.
  Future<void> upsert(HappyHourRule rule) async {
    final next = [...state];
    final i = next.indexWhere((r) => r.id == rule.id);
    if (i >= 0) {
      next[i] = rule;
    } else {
      next.add(rule);
    }
    await _persist(next);
  }

  /// Delete a rule by id.
  Future<void> remove(String id) async {
    final next = state.where((r) => r.id != id).toList(growable: false);
    await _persist(next);
  }

  /// Flip the active flag on a rule without editing its other fields.
  Future<void> toggleActive(String id) async {
    final next = state
        .map((r) => r.id == id ? r.copyWith(active: !r.active) : r)
        .toList(growable: false);
    await _persist(next);
  }

  Future<void> _persist(List<HappyHourRule> rules) async {
    final repo = _repo;
    if (repo != null) {
      await repo.saveHappyHourSettings(HappyHourSettings(rules: rules));
    }
    state = List.unmodifiable(rules);
  }
}
