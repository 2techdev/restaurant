/// Menu category entity.
library;

/// Immutable representation of a menu category.
class CategoryEntity {
  final String id;
  final String tenantId;
  final String name;
  final int displayOrder;

  /// Hex color string for the category tile, e.g. "#FF9F0A".
  final String color;

  /// Material icon name or code point reference.
  final String icon;

  /// If non-null, this category is a sub-category of [parentId].
  final String? parentId;

  final bool isActive;

  const CategoryEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.displayOrder,
    required this.color,
    required this.icon,
    this.parentId,
    required this.isActive,
  });

  factory CategoryEntity.fromJson(Map<String, dynamic> json) => CategoryEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        name: json['name'] as String,
        displayOrder: json['display_order'] as int? ?? 0,
        color: json['color'] as String? ?? '#FF9F0A',
        icon: json['icon'] as String? ?? 'category',
        parentId: json['parent_id'] as String?,
        isActive: json['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        'display_order': displayOrder,
        'color': color,
        'icon': icon,
        if (parentId != null) 'parent_id': parentId,
        'is_active': isActive,
      };

  CategoryEntity copyWith({
    String? id,
    String? tenantId,
    String? name,
    int? displayOrder,
    String? color,
    String? icon,
    String? Function()? parentId,
    bool? isActive,
  }) {
    return CategoryEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      displayOrder: displayOrder ?? this.displayOrder,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      parentId: parentId != null ? parentId() : this.parentId,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          name == other.name &&
          displayOrder == other.displayOrder &&
          color == other.color &&
          icon == other.icon &&
          parentId == other.parentId &&
          isActive == other.isActive;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        name,
        displayOrder,
        color,
        icon,
        parentId,
        isActive,
      );

  @override
  String toString() =>
      'CategoryEntity(id: $id, name: $name, order: $displayOrder)';
}
