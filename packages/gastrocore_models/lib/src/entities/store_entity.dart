/// A single physical location owned by a [RestaurantEntity].
library;

class StoreAddress {
  final String street;
  final String postalCode;
  final String city;
  final String countryCode;

  const StoreAddress({
    required this.street,
    required this.postalCode,
    required this.city,
    this.countryCode = 'CH',
  });

  factory StoreAddress.fromJson(Map<String, dynamic> json) => StoreAddress(
        street: json['street'] as String? ?? '',
        postalCode: json['postal_code'] as String? ?? '',
        city: json['city'] as String? ?? '',
        countryCode: json['country_code'] as String? ?? 'CH',
      );

  Map<String, dynamic> toJson() => {
        'street': street,
        'postal_code': postalCode,
        'city': city,
        'country_code': countryCode,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoreAddress &&
          runtimeType == other.runtimeType &&
          street == other.street &&
          postalCode == other.postalCode &&
          city == other.city &&
          countryCode == other.countryCode;

  @override
  int get hashCode =>
      Object.hash(street, postalCode, city, countryCode);

  @override
  String toString() => '$street, $postalCode $city';
}

class StoreEntity {
  final String id;

  /// FK to [RestaurantEntity].
  final String tenantId;

  final String name;

  /// Optional short code used on receipts ("ZH01").
  final String? code;

  final StoreAddress? address;

  /// Overrides [RestaurantEntity.timezone] when not null.
  final String? timezone;

  /// Overrides [RestaurantEntity.currency] when not null.
  final String? currency;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StoreEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    this.code,
    this.address,
    this.timezone,
    this.currency,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StoreEntity.fromJson(Map<String, dynamic> json) => StoreEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        name: json['name'] as String,
        code: json['code'] as String?,
        address: json['address'] != null
            ? StoreAddress.fromJson(json['address'] as Map<String, dynamic>)
            : null,
        timezone: json['timezone'] as String?,
        currency: json['currency'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        if (code != null) 'code': code,
        if (address != null) 'address': address!.toJson(),
        if (timezone != null) 'timezone': timezone,
        if (currency != null) 'currency': currency,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  StoreEntity copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? Function()? code,
    StoreAddress? Function()? address,
    String? Function()? timezone,
    String? Function()? currency,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StoreEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      code: code != null ? code() : this.code,
      address: address != null ? address() : this.address,
      timezone: timezone != null ? timezone() : this.timezone,
      currency: currency != null ? currency() : this.currency,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoreEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          name == other.name &&
          isActive == other.isActive;

  @override
  int get hashCode => Object.hash(id, tenantId, name, isActive);

  @override
  String toString() =>
      'StoreEntity(id: $id, name: $name, active: $isActive)';
}
