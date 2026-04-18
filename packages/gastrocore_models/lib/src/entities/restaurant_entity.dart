/// Top-level tenant (restaurant / brand) record.
///
/// One [RestaurantEntity] may own multiple [StoreEntity] rows — see
/// `store_entity.dart`.
library;

/// Subscription plan the tenant is on. Additive only.
enum RestaurantPlan {
  freemium,
  starter,
  pro,
  enterprise,
}

class RestaurantEntity {
  final String id;

  /// Display name of the restaurant / brand.
  final String name;

  /// Legal entity (optional — needed for Swiss receipts).
  final String? legalName;

  /// Swiss UID (e.g. "CHE-123.456.789") for MWST. Optional.
  final String? uid;

  /// Default currency for every store under this tenant. ISO 4217, e.g. "CHF".
  final String currency;

  /// IETF BCP 47 default locale, e.g. "de-CH".
  final String locale;

  final String timezone;
  final RestaurantPlan plan;

  /// If `true`, tenant is locked (e.g. subscription lapsed).
  final bool isSuspended;

  final DateTime createdAt;
  final DateTime updatedAt;

  const RestaurantEntity({
    required this.id,
    required this.name,
    this.legalName,
    this.uid,
    this.currency = 'CHF',
    this.locale = 'de-CH',
    this.timezone = 'Europe/Zurich',
    this.plan = RestaurantPlan.freemium,
    this.isSuspended = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RestaurantEntity.fromJson(Map<String, dynamic> json) =>
      RestaurantEntity(
        id: json['id'] as String,
        name: json['name'] as String,
        legalName: json['legal_name'] as String?,
        uid: json['uid'] as String?,
        currency: json['currency'] as String? ?? 'CHF',
        locale: json['locale'] as String? ?? 'de-CH',
        timezone: json['timezone'] as String? ?? 'Europe/Zurich',
        plan: RestaurantPlan.values.firstWhere(
          (e) => e.name == json['plan'],
          orElse: () => RestaurantPlan.freemium,
        ),
        isSuspended: json['is_suspended'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (legalName != null) 'legal_name': legalName,
        if (uid != null) 'uid': uid,
        'currency': currency,
        'locale': locale,
        'timezone': timezone,
        'plan': plan.name,
        'is_suspended': isSuspended,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  RestaurantEntity copyWith({
    String? id,
    String? name,
    String? Function()? legalName,
    String? Function()? uid,
    String? currency,
    String? locale,
    String? timezone,
    RestaurantPlan? plan,
    bool? isSuspended,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RestaurantEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      legalName: legalName != null ? legalName() : this.legalName,
      uid: uid != null ? uid() : this.uid,
      currency: currency ?? this.currency,
      locale: locale ?? this.locale,
      timezone: timezone ?? this.timezone,
      plan: plan ?? this.plan,
      isSuspended: isSuspended ?? this.isSuspended,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RestaurantEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          currency == other.currency &&
          plan == other.plan &&
          isSuspended == other.isSuspended;

  @override
  int get hashCode => Object.hash(id, name, currency, plan, isSuspended);

  @override
  String toString() =>
      'RestaurantEntity(id: $id, name: $name, plan: ${plan.name})';
}
