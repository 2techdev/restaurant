/// Swiss MWST / VAT rate definition.
///
/// The three Swiss MWST rates (as of 2024-01-01):
///   * 8.1 % — standard
///   * 2.6 % — reduced (food, non-alcoholic drinks)
///   * 3.8 % — accommodation / hotel
library;

/// Canonical Swiss MWST bucket.
enum SwissMwstBucket {
  standard,
  reduced,
  accommodation,
  exempt;

  /// Default rate in percent for this bucket.
  double get defaultRate => switch (this) {
        SwissMwstBucket.standard => 8.1,
        SwissMwstBucket.reduced => 2.6,
        SwissMwstBucket.accommodation => 3.8,
        SwissMwstBucket.exempt => 0.0,
      };
}

class TaxEntity {
  final String id;
  final String tenantId;

  /// Human-readable name (e.g. "MWST 8.1%").
  final String name;

  /// Rate in percent (e.g. 8.1).
  final double rate;

  final SwissMwstBucket bucket;

  /// Two-letter country code. Almost always "CH" for GastroCore tenants.
  final String countryCode;

  /// If `true`, prices in the catalogue are tax-inclusive (gross).
  final bool inclusive;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TaxEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.rate,
    required this.bucket,
    this.countryCode = 'CH',
    this.inclusive = true,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Baseline Swiss VAT: 8.1 % standard, tax-inclusive. Deterministic ids —
  /// useful for seeds + tests, not persisted as-is.
  static TaxEntity swissStandard({
    required String tenantId,
    DateTime? at,
  }) {
    final now = at ?? DateTime.utc(2024, 1, 1);
    return TaxEntity(
      id: 'ch-mwst-standard',
      tenantId: tenantId,
      name: 'MWST 8.1%',
      rate: 8.1,
      bucket: SwissMwstBucket.standard,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory TaxEntity.fromJson(Map<String, dynamic> json) => TaxEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        name: json['name'] as String,
        rate: (json['rate'] as num).toDouble(),
        bucket: SwissMwstBucket.values.firstWhere(
          (e) => e.name == json['bucket'],
          orElse: () => SwissMwstBucket.standard,
        ),
        countryCode: json['country_code'] as String? ?? 'CH',
        inclusive: json['inclusive'] as bool? ?? true,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        'rate': rate,
        'bucket': bucket.name,
        'country_code': countryCode,
        'inclusive': inclusive,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  TaxEntity copyWith({
    String? id,
    String? tenantId,
    String? name,
    double? rate,
    SwissMwstBucket? bucket,
    String? countryCode,
    bool? inclusive,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TaxEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      rate: rate ?? this.rate,
      bucket: bucket ?? this.bucket,
      countryCode: countryCode ?? this.countryCode,
      inclusive: inclusive ?? this.inclusive,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaxEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          rate == other.rate &&
          bucket == other.bucket &&
          inclusive == other.inclusive;

  @override
  int get hashCode =>
      Object.hash(id, tenantId, rate, bucket, inclusive);

  @override
  String toString() =>
      'TaxEntity(id: $id, rate: $rate%, bucket: ${bucket.name})';
}
