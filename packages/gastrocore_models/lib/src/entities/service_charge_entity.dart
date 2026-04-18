/// Configurable service charge (fee) definition.
library;

/// How the service charge amount is computed.
enum ServiceChargeType {
  /// Fixed amount in cents (e.g. CHF 2.00 cover per guest).
  fixed,

  /// Percentage of the subtotal. Value is percentage * 100 (e.g. 1000 = 10.00%).
  percentage,
}

/// What triggers the service charge.
enum ServiceChargeTrigger {
  /// Every ticket.
  always,

  /// Only dine-in / table orders.
  dineInOnly,

  /// Only delivery orders.
  deliveryOnly,

  /// Only takeaway orders.
  takeawayOnly,

  /// Per guest / cover (multiplied by guest count).
  perGuest,
}

class ServiceChargeEntity {
  final String id;
  final String tenantId;
  final String name;
  final ServiceChargeType chargeType;
  final int value;
  final ServiceChargeTrigger trigger;

  /// If `true`, the charge is taxable and contributes to VAT base.
  final bool taxable;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ServiceChargeEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.chargeType,
    required this.value,
    this.trigger = ServiceChargeTrigger.always,
    this.taxable = true,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ServiceChargeEntity.fromJson(Map<String, dynamic> json) =>
      ServiceChargeEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        name: json['name'] as String,
        chargeType: ServiceChargeType.values.firstWhere(
          (e) => e.name == json['charge_type'],
          orElse: () => ServiceChargeType.percentage,
        ),
        value: (json['value'] as num).toInt(),
        trigger: ServiceChargeTrigger.values.firstWhere(
          (e) => e.name == json['trigger'],
          orElse: () => ServiceChargeTrigger.always,
        ),
        taxable: json['taxable'] as bool? ?? true,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        'charge_type': chargeType.name,
        'value': value,
        'trigger': trigger.name,
        'taxable': taxable,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  ServiceChargeEntity copyWith({
    String? id,
    String? tenantId,
    String? name,
    ServiceChargeType? chargeType,
    int? value,
    ServiceChargeTrigger? trigger,
    bool? taxable,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ServiceChargeEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      chargeType: chargeType ?? this.chargeType,
      value: value ?? this.value,
      trigger: trigger ?? this.trigger,
      taxable: taxable ?? this.taxable,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServiceChargeEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          chargeType == other.chargeType &&
          value == other.value &&
          trigger == other.trigger &&
          isActive == other.isActive;

  @override
  int get hashCode =>
      Object.hash(id, tenantId, chargeType, value, trigger, isActive);

  @override
  String toString() =>
      'ServiceChargeEntity(id: $id, name: $name, ${chargeType.name}=$value)';
}
