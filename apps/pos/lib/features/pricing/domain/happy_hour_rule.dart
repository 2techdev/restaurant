/// Time-based (happy-hour) pricing rule.
///
/// Pure, immutable data class. DB-agnostic by design — the pilot ships a
/// hardcoded list in the provider; a future iteration can swap that for a
/// repository without touching the evaluator.
///
/// Matching semantics:
///   * [categoryId] — if non-null, the item's product category must match.
///   * [productNameContains] — case-insensitive substring match on the item's
///     product name. Handy for pilot seeding when category IDs aren't wired up
///     for everything (e.g. "bira" finds every beer).
///   * At least one of the two should be set; otherwise the rule would match
///     every line and that is almost certainly a misconfiguration.
///   * [daysOfWeek] — ISO weekdays (Mon=1 … Sun=7). Empty = every day.
///   * [startTime] / [endTime] — local wall-clock window. If [endTime] is
///     earlier than [startTime] the window wraps past midnight (e.g. 22:00 →
///     02:00). The [startTime] minute is inclusive, [endTime] minute is
///     exclusive, which matches how bar shifts are usually written.
library;

import 'package:flutter/material.dart' show TimeOfDay;

class HappyHourRule {
  final String id;
  final String name;

  /// Category the rule targets. Null means "any category".
  final String? categoryId;

  /// Product-name substring match (case-insensitive). Null means "any name".
  final String? productNameContains;

  /// Discount percentage, 0-100. 20 = -20%.
  final int discountPercent;

  final TimeOfDay startTime;
  final TimeOfDay endTime;

  /// ISO weekdays the rule fires on (Mon=1 … Sun=7). Empty = every day.
  final List<int> daysOfWeek;

  final bool active;

  const HappyHourRule({
    required this.id,
    required this.name,
    this.categoryId,
    this.productNameContains,
    required this.discountPercent,
    required this.startTime,
    required this.endTime,
    this.daysOfWeek = const [],
    this.active = true,
  });

  /// True when [now] falls inside this rule's weekday and time window.
  ///
  /// Pure and synchronous so the evaluator and tests can share the same
  /// logic without a clock abstraction.
  bool isActiveAt(DateTime now) {
    if (!active) return false;

    if (daysOfWeek.isNotEmpty && !daysOfWeek.contains(now.weekday)) {
      return false;
    }

    final nowMinutes = now.hour * 60 + now.minute;
    final startMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;

    if (startMinutes == endMinutes) {
      // Zero-width window — never active. Guards against misconfiguration.
      return false;
    }

    if (startMinutes < endMinutes) {
      // Same-day window: [start, end).
      return nowMinutes >= startMinutes && nowMinutes < endMinutes;
    }

    // Wraps midnight: active from start..23:59 OR 00:00..end.
    return nowMinutes >= startMinutes || nowMinutes < endMinutes;
  }

  /// True when this rule targets the given product category + name.
  ///
  /// Both filters are additive — when both are set, both must match.
  bool matchesProduct({
    required String productCategoryId,
    required String productName,
  }) {
    if (categoryId != null && categoryId != productCategoryId) return false;
    if (productNameContains != null) {
      final needle = productNameContains!.toLowerCase();
      if (!productName.toLowerCase().contains(needle)) return false;
    }
    return true;
  }
}
