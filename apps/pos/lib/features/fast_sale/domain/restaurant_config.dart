/// Restaurant-wide POS feature configuration.
///
/// Drives whether the device boots into the dense floor-plan / table
/// flow ("hybrid") or the single-screen Fast Sale flow used by snack
/// bars, bakeries, and food-truck pilots.
///
/// The struct is fed by `GET /api/v1/me/restaurant/config`; offline /
/// 404 paths fall back to the defaults below ([PosMode.hybrid],
/// [featureTisch] = true), so a freshly paired device boots into the
/// existing floor-plan / table service UI by default. Snack-bar /
/// bakery / food-truck pilots opt out via the cloud config (or the
/// per-device override) once the endpoint flips them to `fastSale`.
library;

import 'dart:convert';

enum PosMode {
  /// Single-screen counter ordering (fast food / takeaway / bakery).
  /// Home = empty cart, ready for next sale.
  fastSale('fastSale'),

  /// Classic fine-dining floor plan with table grid + service flow.
  /// Home = floor plan; opens ticket-per-table.
  hybrid('hybrid'),

  /// Order Center hub — both flows live side-by-side. Operator sees
  /// the active ticket preview + floor grid + a quick-sale CTA panel
  /// on one screen. 2026-05-15: introduced for restaurants that mix
  /// counter + dine-in shifts (lunch counter / dinner service).
  mixed('mixed');

  const PosMode(this.code);
  final String code;

  static PosMode fromCode(String? code) {
    for (final m in PosMode.values) {
      if (m.code == code) return m;
    }
    // Cold-start / unknown payload falls back to the table-service
    // flow so existing dine-in pilots keep their classic floor-plan
    // boot screen even before the cloud config arrives.
    return PosMode.hybrid;
  }
}

class RestaurantConfig {
  final PosMode posMode;
  final bool featureTisch;

  const RestaurantConfig({
    this.posMode = PosMode.hybrid,
    this.featureTisch = true,
  });

  /// The default configuration applied when the device has no cached
  /// config and the network is unavailable — hybrid mode with the
  /// table feature on. The three demo restaurants (Pizzeria Da Mario,
  /// Sushi Zen, Burger House) match this in migration 017; snack-bar
  /// pilots flip off both flags via the cloud config once paired.
  static const RestaurantConfig defaults = RestaurantConfig();

  RestaurantConfig copyWith({
    PosMode? posMode,
    bool? featureTisch,
  }) {
    return RestaurantConfig(
      posMode: posMode ?? this.posMode,
      featureTisch: featureTisch ?? this.featureTisch,
    );
  }

  Map<String, dynamic> toJson() => {
        'posMode': posMode.code,
        'featureTisch': featureTisch,
      };

  factory RestaurantConfig.fromJson(Map<String, dynamic> j) {
    return RestaurantConfig(
      posMode: PosMode.fromCode(j['posMode'] as String?),
      featureTisch: j['featureTisch'] as bool? ?? true,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory RestaurantConfig.fromJsonString(String s) =>
      RestaurantConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RestaurantConfig &&
          runtimeType == other.runtimeType &&
          posMode == other.posMode &&
          featureTisch == other.featureTisch;

  @override
  int get hashCode => Object.hash(posMode, featureTisch);

  @override
  String toString() =>
      'RestaurantConfig(posMode: ${posMode.code}, featureTisch: $featureTisch)';
}
