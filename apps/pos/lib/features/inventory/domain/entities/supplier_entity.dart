/// Domain entity for a supplier / vendor.
library;

class SupplierEntity {
  final String id;
  final String tenantId;
  final String name;
  final String? email;
  final String? phone;
  final String? address;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SupplierEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    this.email,
    this.phone,
    this.address,
    this.notes,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  SupplierEntity copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? email,
    String? phone,
    String? address,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SupplierEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupplierEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
