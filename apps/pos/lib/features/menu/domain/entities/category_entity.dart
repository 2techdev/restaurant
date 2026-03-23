/// Menu category entity.
///
/// Categories organise products in the POS grid (e.g. "Drinks", "Starters",
/// "Desserts"). They support one level of nesting via [parentId] for
/// sub-categories.
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

  /// Default Gang for products in this category (references gang_templates.id).
  final String? defaultGangId;

  const CategoryEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.displayOrder,
    required this.color,
    required this.icon,
    this.parentId,
    required this.isActive,
    this.defaultGangId,
  });

  /// Create a copy with selectively overridden fields.
  CategoryEntity copyWith({
    String? id,
    String? tenantId,
    String? name,
    int? displayOrder,
    String? color,
    String? icon,
    String? Function()? parentId,
    bool? isActive,
    String? Function()? defaultGangId,
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
      defaultGangId:
          defaultGangId != null ? defaultGangId() : this.defaultGangId,
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
