/// User entity and [UserRole] enum.
library;

/// Permissions role assigned to a staff member.
enum UserRole {
  admin,
  manager,
  waiter,
  cashier,
  kitchen,
}

/// Immutable representation of a POS staff member.
class UserEntity {
  final String id;
  final String tenantId;
  final String name;
  final String pinHash;
  final UserRole role;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.pinHash,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserEntity.fromJson(Map<String, dynamic> json) => UserEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        name: json['name'] as String,
        pinHash: json['pin_hash'] as String? ?? '',
        role: UserRole.values.firstWhere(
          (e) => e.name == json['role'],
          orElse: () => UserRole.waiter,
        ),
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        'pin_hash': pinHash,
        'role': role.name,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  UserEntity copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? pinHash,
    UserRole? role,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      pinHash: pinHash ?? this.pinHash,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          name == other.name &&
          role == other.role &&
          isActive == other.isActive;

  @override
  int get hashCode =>
      Object.hash(id, tenantId, name, pinHash, role, isActive);

  @override
  String toString() =>
      'UserEntity(id: $id, name: $name, role: ${role.name})';
}
