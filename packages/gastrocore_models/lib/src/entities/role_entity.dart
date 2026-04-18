/// Standalone role entity with a permission set.
///
/// [UserRole] (in `user_entity.dart`) remains the stable enum used across apps.
/// [RoleEntity] is a *configurable* row that can be created in backoffice to
/// extend or restrict the baseline enum per tenant without a schema change.
library;

import 'user_entity.dart';

/// Discrete permissions checked by the apps. Additive only — never reorder.
enum Permission {
  posOpenShift,
  posCloseShift,
  posVoidTicket,
  posApplyDiscount,
  posRefund,
  backofficeMenuEdit,
  backofficeStaffEdit,
  backofficeSettingsEdit,
  backofficeReportsView,
  dashboardLiveView,
  kdsBumpOrder,
  waiterTableTransfer,
}

class RoleEntity {
  final String id;
  final String tenantId;
  final String name;

  /// Baseline enum this role maps onto. Apps that only understand
  /// [UserRole] (older builds) can fall back to this.
  final UserRole baseRole;

  final Set<Permission> permissions;
  final bool isSystem;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoleEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.baseRole,
    required this.permissions,
    this.isSystem = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool hasPermission(Permission p) => permissions.contains(p);

  factory RoleEntity.fromJson(Map<String, dynamic> json) => RoleEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        name: json['name'] as String,
        baseRole: UserRole.values.firstWhere(
          (e) => e.name == json['base_role'],
          orElse: () => UserRole.waiter,
        ),
        permissions: ((json['permissions'] as List<dynamic>?) ?? const [])
            .map((p) => Permission.values.firstWhere(
                  (e) => e.name == p,
                  orElse: () => Permission.posApplyDiscount,
                ))
            .toSet(),
        isSystem: json['is_system'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        'base_role': baseRole.name,
        'permissions': permissions.map((p) => p.name).toList(),
        'is_system': isSystem,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  RoleEntity copyWith({
    String? id,
    String? tenantId,
    String? name,
    UserRole? baseRole,
    Set<Permission>? permissions,
    bool? isSystem,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RoleEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      baseRole: baseRole ?? this.baseRole,
      permissions: permissions ?? this.permissions,
      isSystem: isSystem ?? this.isSystem,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoleEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          name == other.name &&
          baseRole == other.baseRole;

  @override
  int get hashCode => Object.hash(id, tenantId, name, baseRole);

  @override
  String toString() =>
      'RoleEntity(id: $id, name: $name, base: ${baseRole.name})';
}
