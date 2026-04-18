/// Tenant-configurable payment method row (catalog).
///
/// Distinct from the [PaymentMethod] enum (in `payment_entity.dart`) which
/// is the *baseline category* every app understands. This entity is the
/// concrete per-tenant row that a cashier can tap on screen (e.g. a TWINT
/// button that maps onto [PaymentMethod.other]).
library;

import 'payment_entity.dart' show PaymentMethod;

class PaymentMethodEntity {
  final String id;
  final String tenantId;

  /// Display label shown on the cashier keypad.
  final String name;

  /// Baseline category this method maps to. The accounting / Z-report
  /// rollups group by this field.
  final PaymentMethod method;

  /// Optional short code used in receipts / exports (e.g. "TWINT").
  final String? code;

  /// Optional icon key (e.g. "cash", "card", "twint"). UI layer maps this
  /// to an asset / material icon.
  final String? iconKey;

  /// If `true`, cashier is prompted for a numeric change amount (cash flow).
  final bool requiresTender;

  /// If `true`, the method supports tipping.
  final bool tipEnabled;

  /// Display order in the cashier keypad.
  final int displayOrder;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PaymentMethodEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.method,
    this.code,
    this.iconKey,
    this.requiresTender = false,
    this.tipEnabled = true,
    this.displayOrder = 0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaymentMethodEntity.fromJson(Map<String, dynamic> json) =>
      PaymentMethodEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        name: json['name'] as String,
        method: PaymentMethod.values.firstWhere(
          (e) => e.name == json['method'],
          orElse: () => PaymentMethod.other,
        ),
        code: json['code'] as String?,
        iconKey: json['icon_key'] as String?,
        requiresTender: json['requires_tender'] as bool? ?? false,
        tipEnabled: json['tip_enabled'] as bool? ?? true,
        displayOrder: json['display_order'] as int? ?? 0,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        'method': method.name,
        if (code != null) 'code': code,
        if (iconKey != null) 'icon_key': iconKey,
        'requires_tender': requiresTender,
        'tip_enabled': tipEnabled,
        'display_order': displayOrder,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  PaymentMethodEntity copyWith({
    String? id,
    String? tenantId,
    String? name,
    PaymentMethod? method,
    String? Function()? code,
    String? Function()? iconKey,
    bool? requiresTender,
    bool? tipEnabled,
    int? displayOrder,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PaymentMethodEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      method: method ?? this.method,
      code: code != null ? code() : this.code,
      iconKey: iconKey != null ? iconKey() : this.iconKey,
      requiresTender: requiresTender ?? this.requiresTender,
      tipEnabled: tipEnabled ?? this.tipEnabled,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentMethodEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          name == other.name &&
          method == other.method &&
          isActive == other.isActive;

  @override
  int get hashCode =>
      Object.hash(id, tenantId, name, method, isActive);

  @override
  String toString() =>
      'PaymentMethodEntity(id: $id, name: $name, baseline: ${method.name})';
}
