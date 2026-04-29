/// Happy hour settings entity.
///
/// A thin wrapper around a list of [HappyHourRule]s so the existing
/// SharedPreferences-backed [SettingsRepository] can persist them under a
/// dedicated key without leaking TimeOfDay / dart:ui types into the
/// repository interface.
library;

import 'dart:convert';

import 'package:gastrocore_pos/features/pricing/domain/happy_hour_rule.dart';

class HappyHourSettings {
  const HappyHourSettings({this.rules = const []});

  final List<HappyHourRule> rules;

  HappyHourSettings copyWith({List<HappyHourRule>? rules}) =>
      HappyHourSettings(rules: rules ?? this.rules);

  Map<String, dynamic> toJson() => {
        'rules': rules.map((r) => r.toJson()).toList(growable: false),
      };

  String toJsonString() => jsonEncode(toJson());

  factory HappyHourSettings.fromJson(Map<String, dynamic> json) {
    final raw = json['rules'] as List? ?? const [];
    final rules = raw
        .whereType<Map>()
        .map((m) => HappyHourRule.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
    return HappyHourSettings(rules: rules);
  }

  factory HappyHourSettings.fromJsonString(String raw) =>
      HappyHourSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
}
