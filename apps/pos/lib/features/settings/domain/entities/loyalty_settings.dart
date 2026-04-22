/// Loyalty program configuration.
///
/// Exposes the four knobs Swiss pilots ask about most:
///   * earn rate — how many points 1 CHF of revenue produces
///   * redemption rate — how many cents 1 point buys back
///   * silver threshold — lifetime CHF before a customer becomes silver
///   * gold threshold — lifetime CHF before a customer becomes gold
///
/// Defaults match the original hard-coded constants in CustomerEntity so
/// tenants who never open the editor see no change. [isActive] lets an
/// operator turn the program off without wiping the knob values — handy
/// while a new campaign is being prepared.
library;

import 'dart:convert';

class LoyaltySettings {
  const LoyaltySettings({
    this.isActive = true,
    this.pointsPerChfSpent = 1,
    this.centsPerPoint = 1,
    this.silverThresholdCents = 20000,
    this.goldThresholdCents = 50000,
  });

  /// When false the loyalty screen still renders history but earning and
  /// redeeming are disabled — useful for a soft-off before removing tiers.
  final bool isActive;

  /// Integer points granted for every full CHF spent. Default 1 pt/CHF.
  final int pointsPerChfSpent;

  /// Discount (in cents) each point unlocks when redeemed. Default 1
  /// corresponds to the legacy "100 points = CHF 1.00" rule.
  final int centsPerPoint;

  /// Lifetime spend (in cents) required to reach the silver tier.
  final int silverThresholdCents;

  /// Lifetime spend (in cents) required to reach the gold tier.
  final int goldThresholdCents;

  /// Validation: thresholds must be ordered and the economic knobs must
  /// be positive. Throwing here keeps bad configs out of the save path.
  bool get isValid =>
      pointsPerChfSpent > 0 &&
      centsPerPoint > 0 &&
      silverThresholdCents > 0 &&
      goldThresholdCents > silverThresholdCents;

  LoyaltySettings copyWith({
    bool? isActive,
    int? pointsPerChfSpent,
    int? centsPerPoint,
    int? silverThresholdCents,
    int? goldThresholdCents,
  }) =>
      LoyaltySettings(
        isActive: isActive ?? this.isActive,
        pointsPerChfSpent: pointsPerChfSpent ?? this.pointsPerChfSpent,
        centsPerPoint: centsPerPoint ?? this.centsPerPoint,
        silverThresholdCents:
            silverThresholdCents ?? this.silverThresholdCents,
        goldThresholdCents: goldThresholdCents ?? this.goldThresholdCents,
      );

  Map<String, dynamic> toJson() => {
        'isActive': isActive,
        'pointsPerChfSpent': pointsPerChfSpent,
        'centsPerPoint': centsPerPoint,
        'silverThresholdCents': silverThresholdCents,
        'goldThresholdCents': goldThresholdCents,
      };

  String toJsonString() => jsonEncode(toJson());

  factory LoyaltySettings.fromJson(Map<String, dynamic> json) =>
      LoyaltySettings(
        isActive: (json['isActive'] as bool?) ?? true,
        pointsPerChfSpent: (json['pointsPerChfSpent'] as num?)?.toInt() ?? 1,
        centsPerPoint: (json['centsPerPoint'] as num?)?.toInt() ?? 1,
        silverThresholdCents:
            (json['silverThresholdCents'] as num?)?.toInt() ?? 20000,
        goldThresholdCents:
            (json['goldThresholdCents'] as num?)?.toInt() ?? 50000,
      );

  factory LoyaltySettings.fromJsonString(String s) =>
      LoyaltySettings.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoyaltySettings &&
          isActive == other.isActive &&
          pointsPerChfSpent == other.pointsPerChfSpent &&
          centsPerPoint == other.centsPerPoint &&
          silverThresholdCents == other.silverThresholdCents &&
          goldThresholdCents == other.goldThresholdCents;

  @override
  int get hashCode => Object.hash(isActive, pointsPerChfSpent, centsPerPoint,
      silverThresholdCents, goldThresholdCents);
}

/// Resolves a [LoyaltyTier] from lifetime spend in cents. Lives next to
/// the entity so the editor screen, the loyalty screen and the customer
/// list filter all agree on the thresholds.
LoyaltyTier resolveLoyaltyTier(int totalSpentCents, LoyaltySettings s) {
  if (totalSpentCents >= s.goldThresholdCents) return LoyaltyTier.gold;
  if (totalSpentCents >= s.silverThresholdCents) return LoyaltyTier.silver;
  return LoyaltyTier.bronze;
}

/// Mirrors [CustomerTier] but lives with the settings so the editor can
/// reference it without a customers-feature import. The loyalty screen
/// converts between the two in a single switch.
enum LoyaltyTier { bronze, silver, gold }
