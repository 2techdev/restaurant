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

  HappyHourRule copyWith({
    String? id,
    String? name,
    String? categoryId,
    bool clearCategoryId = false,
    String? productNameContains,
    bool clearProductNameContains = false,
    int? discountPercent,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    List<int>? daysOfWeek,
    bool? active,
  }) {
    return HappyHourRule(
      id: id ?? this.id,
      name: name ?? this.name,
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      productNameContains: clearProductNameContains
          ? null
          : (productNameContains ?? this.productNameContains),
      discountPercent: discountPercent ?? this.discountPercent,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      active: active ?? this.active,
    );
  }

  /// JSON map for persistence. [TimeOfDay] is encoded as `HH:mm` so the stored
  /// shape stays stable if Flutter ever changes the class internals.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'categoryId': categoryId,
        'productNameContains': productNameContains,
        'discountPercent': discountPercent,
        'startTime': _fmtTime(startTime),
        'endTime': _fmtTime(endTime),
        'daysOfWeek': daysOfWeek,
        'active': active,
      };

  /// Inverse of [toJson]. Unknown / missing fields fall back to safe defaults
  /// so a partially-written blob never crashes the POS grid evaluator.
  factory HappyHourRule.fromJson(Map<String, dynamic> json) {
    final days = (json['daysOfWeek'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList(growable: false) ??
        const <int>[];
    return HappyHourRule(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      categoryId: json['categoryId']?.toString(),
      productNameContains: json['productNameContains']?.toString(),
      discountPercent: (json['discountPercent'] as num?)?.toInt() ?? 0,
      startTime: _parseTime(json['startTime']?.toString()) ??
          const TimeOfDay(hour: 0, minute: 0),
      endTime: _parseTime(json['endTime']?.toString()) ??
          const TimeOfDay(hour: 0, minute: 0),
      daysOfWeek: days,
      active: json['active'] as bool? ?? true,
    );
  }

  static String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay? _parseTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }
}
