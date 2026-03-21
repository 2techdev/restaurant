/// User entity and [UserRole] enum for the authentication domain.
///
/// Represents a staff member who can log in to the POS terminal via PIN code.
/// Every user belongs to exactly one tenant and has a single role that
/// determines their permissions.
library;

// ---------------------------------------------------------------------------
// UserRole enum
// ---------------------------------------------------------------------------

/// Permissions role assigned to a staff member.
enum UserRole {
  /// Full access: settings, reports, user management.
  admin,

  /// Can manage shifts, void orders, apply discounts.
  manager,

  /// Can take orders, assign tables, process basic payments.
  waiter,

  /// Can process payments, open/close shifts, print receipts.
  cashier,

  /// Kitchen display only: view and update ticket statuses.
  kitchen,
}

// ---------------------------------------------------------------------------
// UserEntity
// ---------------------------------------------------------------------------

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

  /// Create a copy with selectively overridden fields.
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
          pinHash == other.pinHash &&
          role == other.role &&
          isActive == other.isActive &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        name,
        pinHash,
        role,
        isActive,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'UserEntity(id: $id, name: $name, role: ${role.name})';
}
