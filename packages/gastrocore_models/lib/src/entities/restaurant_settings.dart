/// Strongly-typed restaurant-level settings.
///
/// [SettingsEntity] is the generic key/value bag persisted in the backend.
/// [RestaurantSettings] is the typed projection apps work with at runtime:
/// it knows about Gang configuration, service charges, and other tenant
/// toggles, and it handles validation + defaults.
///
/// Storage layout in [SettingsEntity.values]:
///
/// | key                              | type | default                |
/// | -------------------------------- | ---- | ---------------------- |
/// | `gangs.enabled`                  | bool | true                   |
/// | `gangs.max`                      | int  | 3 (clamped to 1..5)    |
/// | `gangs.labels`                   | json | ["Gang 1","Gang 2",…]  |
/// | `service_charge.enabled`         | bool | false                  |
/// | `service_charge.percent`         | double | 0.0                  |
library;

import 'settings_entity.dart';

/// Canonical setting keys. Apps should not hard-code string literals.
abstract final class SettingsKeys {
  static const gangsEnabled = 'gangs.enabled';
  static const gangsMax = 'gangs.max';
  static const gangsLabels = 'gangs.labels';
  static const serviceChargeEnabled = 'service_charge.enabled';
  static const serviceChargePercent = 'service_charge.percent';
}

/// Hard limits that validation pins. Apps must not exceed these.
abstract final class RestaurantSettingsLimits {
  /// Minimum allowed `gangs.max`.
  static const int minGangs = 1;

  /// Maximum allowed `gangs.max`.
  static const int maxGangs = 5;
}

/// Typed view over [SettingsEntity] for the subset of restaurant-wide
/// settings that belong to the shared contract.
class RestaurantSettings {
  /// Master switch for the Gang / course workflow.
  final bool gangsEnabled;

  /// How many gangs the UI should expose (clamped to 1..5).
  final int maxGangs;

  /// Display label for each gang. `length == maxGangs` is guaranteed by
  /// [normalized] (shorter lists get padded with `"Gang N"`, longer lists
  /// get trimmed).
  final List<String> gangLabels;

  /// If true, a service charge line is appended to every ticket.
  final bool serviceChargeEnabled;

  /// Service charge as percent (e.g. 10.0 for 10 %). 0 is allowed.
  final double serviceChargePercent;

  const RestaurantSettings({
    required this.gangsEnabled,
    required this.maxGangs,
    required this.gangLabels,
    required this.serviceChargeEnabled,
    required this.serviceChargePercent,
  });

  /// Default configuration that matches the baseline [Gang] enum.
  static const defaults = RestaurantSettings(
    gangsEnabled: true,
    maxGangs: 3,
    gangLabels: ['Gang 1', 'Gang 2', 'Gang 3'],
    serviceChargeEnabled: false,
    serviceChargePercent: 0.0,
  );

  /// Returns a copy with `gangLabels.length == maxGangs`. Missing labels
  /// are filled with `"Gang N"`; extra labels are trimmed.
  RestaurantSettings normalized() {
    final clampedMax = maxGangs.clamp(
      RestaurantSettingsLimits.minGangs,
      RestaurantSettingsLimits.maxGangs,
    );
    final labels = List<String>.generate(clampedMax, (i) {
      if (i < gangLabels.length && gangLabels[i].trim().isNotEmpty) {
        return gangLabels[i];
      }
      return 'Gang ${i + 1}';
    });
    if (clampedMax == maxGangs &&
        labels.length == gangLabels.length &&
        _listEq(labels, gangLabels)) {
      return this;
    }
    return RestaurantSettings(
      gangsEnabled: gangsEnabled,
      maxGangs: clampedMax,
      gangLabels: labels,
      serviceChargeEnabled: serviceChargeEnabled,
      serviceChargePercent: serviceChargePercent,
    );
  }

  /// Hydrate from a [SettingsEntity]. Missing keys fall back to [defaults].
  factory RestaurantSettings.fromSettings(SettingsEntity entity) {
    final enabled = entity.values[SettingsKeys.gangsEnabled]?.asBool() ??
        defaults.gangsEnabled;
    final max = entity.values[SettingsKeys.gangsMax]?.asInt() ??
        defaults.maxGangs;
    final rawLabels =
        entity.values[SettingsKeys.gangsLabels]?.raw;
    final labels = _parseLabels(rawLabels) ?? List.of(defaults.gangLabels);

    final scEnabled =
        entity.values[SettingsKeys.serviceChargeEnabled]?.asBool() ??
            defaults.serviceChargeEnabled;
    final scPercent =
        entity.values[SettingsKeys.serviceChargePercent]?.asDouble() ??
            defaults.serviceChargePercent;

    return RestaurantSettings(
      gangsEnabled: enabled,
      maxGangs: max,
      gangLabels: labels,
      serviceChargeEnabled: scEnabled,
      serviceChargePercent: scPercent,
    ).normalized();
  }

  /// Project back into the key/value bag. Only writes our keys; callers
  /// should `copyWith(values: { ...other, ...this.toSettingsMap() })` to
  /// preserve unrelated keys.
  Map<String, SettingValue> toSettingsMap() {
    final n = normalized();
    return {
      SettingsKeys.gangsEnabled: SettingValue(
        type: SettingType.bool,
        raw: n.gangsEnabled,
      ),
      SettingsKeys.gangsMax: SettingValue(
        type: SettingType.int,
        raw: n.maxGangs,
      ),
      SettingsKeys.gangsLabels: SettingValue(
        type: SettingType.json,
        raw: List<String>.of(n.gangLabels),
      ),
      SettingsKeys.serviceChargeEnabled: SettingValue(
        type: SettingType.bool,
        raw: n.serviceChargeEnabled,
      ),
      SettingsKeys.serviceChargePercent: SettingValue(
        type: SettingType.double,
        raw: n.serviceChargePercent,
      ),
    };
  }

  /// Convenience: direct JSON (for configs / fixtures that do not go
  /// through [SettingsEntity]).
  factory RestaurantSettings.fromJson(Map<String, dynamic> json) {
    return RestaurantSettings(
      gangsEnabled: json['gangs_enabled'] as bool? ?? defaults.gangsEnabled,
      maxGangs: (json['max_gangs'] as num?)?.toInt() ?? defaults.maxGangs,
      gangLabels: _parseLabels(json['gang_labels']) ??
          List.of(defaults.gangLabels),
      serviceChargeEnabled: json['service_charge_enabled'] as bool? ??
          defaults.serviceChargeEnabled,
      serviceChargePercent:
          (json['service_charge_percent'] as num?)?.toDouble() ??
              defaults.serviceChargePercent,
    ).normalized();
  }

  Map<String, dynamic> toJson() {
    final n = normalized();
    return {
      'gangs_enabled': n.gangsEnabled,
      'max_gangs': n.maxGangs,
      'gang_labels': List<String>.of(n.gangLabels),
      'service_charge_enabled': n.serviceChargeEnabled,
      'service_charge_percent': n.serviceChargePercent,
    };
  }

  RestaurantSettings copyWith({
    bool? gangsEnabled,
    int? maxGangs,
    List<String>? gangLabels,
    bool? serviceChargeEnabled,
    double? serviceChargePercent,
  }) {
    return RestaurantSettings(
      gangsEnabled: gangsEnabled ?? this.gangsEnabled,
      maxGangs: maxGangs ?? this.maxGangs,
      gangLabels: gangLabels ?? this.gangLabels,
      serviceChargeEnabled: serviceChargeEnabled ?? this.serviceChargeEnabled,
      serviceChargePercent: serviceChargePercent ?? this.serviceChargePercent,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RestaurantSettings &&
          runtimeType == other.runtimeType &&
          gangsEnabled == other.gangsEnabled &&
          maxGangs == other.maxGangs &&
          _listEq(gangLabels, other.gangLabels) &&
          serviceChargeEnabled == other.serviceChargeEnabled &&
          serviceChargePercent == other.serviceChargePercent;

  @override
  int get hashCode => Object.hash(
        gangsEnabled,
        maxGangs,
        Object.hashAll(gangLabels),
        serviceChargeEnabled,
        serviceChargePercent,
      );

  @override
  String toString() => 'RestaurantSettings('
      'gangs=${gangsEnabled ? "on" : "off"}, '
      'max=$maxGangs, labels=$gangLabels, '
      'sc=${serviceChargeEnabled ? "$serviceChargePercent%" : "off"})';
}

/// Parse a labels value which may arrive as `List<String>`, `List<dynamic>`,
/// or — in the JSONB-from-backend path — a JSON string. Returns `null` on
/// unusable input so callers can fall through to defaults.
List<String>? _parseLabels(Object? raw) {
  if (raw == null) return null;
  if (raw is List) {
    return raw.map((e) => e?.toString() ?? '').toList();
  }
  // Allow JSON-string encoding (some backends store JSONB as String).
  if (raw is String) {
    final s = raw.trim();
    if (!s.startsWith('[')) return null;
    try {
      final decoded = _cheapDecodeList(s);
      if (decoded == null) return null;
      return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Very small JSON list decoder to avoid taking a `dart:convert` dependency
/// in the callers of this module. Handles only the shapes that Postgres
/// JSONB produces: `["a","b","c"]` or `[]`. Returns `null` on anything else.
List<dynamic>? _cheapDecodeList(String s) {
  if (s == '[]') return const [];
  if (!s.startsWith('[') || !s.endsWith(']')) return null;
  final inner = s.substring(1, s.length - 1);
  final parts = <dynamic>[];
  var i = 0;
  while (i < inner.length) {
    while (i < inner.length && inner[i] != '"') {
      i++;
    }
    if (i >= inner.length) break;
    i++; // consume opening quote
    final buf = StringBuffer();
    while (i < inner.length && inner[i] != '"') {
      if (inner[i] == r'\' && i + 1 < inner.length) {
        buf.write(inner[i + 1]);
        i += 2;
      } else {
        buf.write(inner[i]);
        i++;
      }
    }
    if (i < inner.length) i++; // consume closing quote
    parts.add(buf.toString());
  }
  return parts;
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
