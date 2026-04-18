/// Configurable discount definition.
///
/// This is the tenant-managed catalogue row that the POS applies to a
/// ticket. It is distinct from the [DiscountType] enum on [TicketEntity]
/// (which records how a particular ticket was discounted inline).
library;

import 'ticket_entity.dart' show DiscountType;

/// How the discount amount is computed.
enum DiscountScope {
  /// Applies to the entire ticket total.
  ticket,

  /// Applies to a single order line / product.
  line,

  /// Applies to a specific category of products.
  category,
}

class DiscountEntity {
  final String id;
  final String tenantId;
  final String name;

  /// Internal short code (e.g. `"HAPPY20"`, `"STAFF"`).
  final String? code;

  final DiscountType discountType;

  /// For [DiscountType.fixed] → amount in cents.
  /// For [DiscountType.percentage] → percentage * 100 (e.g. 2000 = 20.00%).
  final int value;

  final DiscountScope scope;

  /// Optional — restricts the discount to one category if [scope] is
  /// [DiscountScope.category].
  final String? categoryId;

  /// Optional — requires a role permission to apply (`approvalRoleId`).
  final String? approvalRoleId;

  final bool isActive;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DiscountEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    this.code,
    required this.discountType,
    required this.value,
    this.scope = DiscountScope.ticket,
    this.categoryId,
    this.approvalRoleId,
    this.isActive = true,
    this.startsAt,
    this.endsAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool isApplicableAt(DateTime now) {
    if (!isActive) return false;
    if (startsAt != null && now.isBefore(startsAt!)) return false;
    if (endsAt != null && now.isAfter(endsAt!)) return false;
    return true;
  }

  factory DiscountEntity.fromJson(Map<String, dynamic> json) => DiscountEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        name: json['name'] as String,
        code: json['code'] as String?,
        discountType: DiscountType.values.firstWhere(
          (e) => e.name == json['discount_type'],
          orElse: () => DiscountType.fixed,
        ),
        value: (json['value'] as num).toInt(),
        scope: DiscountScope.values.firstWhere(
          (e) => e.name == json['scope'],
          orElse: () => DiscountScope.ticket,
        ),
        categoryId: json['category_id'] as String?,
        approvalRoleId: json['approval_role_id'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        startsAt: json['starts_at'] != null
            ? DateTime.parse(json['starts_at'] as String)
            : null,
        endsAt: json['ends_at'] != null
            ? DateTime.parse(json['ends_at'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        if (code != null) 'code': code,
        'discount_type': discountType.name,
        'value': value,
        'scope': scope.name,
        if (categoryId != null) 'category_id': categoryId,
        if (approvalRoleId != null) 'approval_role_id': approvalRoleId,
        'is_active': isActive,
        if (startsAt != null) 'starts_at': startsAt!.toIso8601String(),
        if (endsAt != null) 'ends_at': endsAt!.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  DiscountEntity copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? Function()? code,
    DiscountType? discountType,
    int? value,
    DiscountScope? scope,
    String? Function()? categoryId,
    String? Function()? approvalRoleId,
    bool? isActive,
    DateTime? Function()? startsAt,
    DateTime? Function()? endsAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DiscountEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      code: code != null ? code() : this.code,
      discountType: discountType ?? this.discountType,
      value: value ?? this.value,
      scope: scope ?? this.scope,
      categoryId: categoryId != null ? categoryId() : this.categoryId,
      approvalRoleId:
          approvalRoleId != null ? approvalRoleId() : this.approvalRoleId,
      isActive: isActive ?? this.isActive,
      startsAt: startsAt != null ? startsAt() : this.startsAt,
      endsAt: endsAt != null ? endsAt() : this.endsAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscountEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          discountType == other.discountType &&
          value == other.value &&
          scope == other.scope &&
          isActive == other.isActive;

  @override
  int get hashCode =>
      Object.hash(id, tenantId, discountType, value, scope, isActive);

  @override
  String toString() =>
      'DiscountEntity(id: $id, name: $name, ${discountType.name}=$value)';
}
