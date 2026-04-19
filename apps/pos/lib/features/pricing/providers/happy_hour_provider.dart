/// Riverpod provider supplying the active happy-hour rule list.
///
/// Pilot scope: hardcoded list — one rule that matches anything named "bira"
/// (Turkish for beer) or in the 'beverages' category, 17:00-19:00, Mon-Fri,
/// -20%. A future iteration can swap this for a repository-backed provider
/// without touching callers.
library;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/features/pricing/domain/happy_hour_rule.dart';

/// Default rule set for the pilot.
///
/// Exposed as a top-level `const` so tests can inject it directly without
/// spinning up a ProviderContainer.
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

/// Active happy-hour rules available to the evaluator.
///
/// Kept `Provider<List<HappyHourRule>>` (not Future) so the addItem hot path
/// doesn't have to await anything — the pilot list is synchronous.
final happyHourRulesProvider = Provider<List<HappyHourRule>>((ref) {
  return happyHourDefaultRules;
});
