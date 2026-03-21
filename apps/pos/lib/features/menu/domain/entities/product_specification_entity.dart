/// Product specification / variant entity.
///
/// A product can have multiple specifications (e.g. Small / Medium / Large),
/// each with its own price. These are stored in the [ProductSpecifications]
/// table and linked to a [ProductEntity] by [productId].
///
/// Prices are stored as integers in Rappen (1/100 CHF) to avoid
/// floating-point rounding errors.
library;

/// Immutable representation of a single product specification / size variant.
class ProductSpecificationEntity {
  final String id;
  final String tenantId;
  final String productId;

  /// Variant label, e.g. "Small", "Medium", "Large", "Default".
  final String name;

  /// Selling price in Rappen (e.g. 1500 = CHF 15.00).
  final int price;

  /// Whether this is the default / pre-selected variant.
  final bool isDefault;

  final int displayOrder;

  const ProductSpecificationEntity({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.name,
    required this.price,
    this.isDefault = false,
    required this.displayOrder,
  });

  ProductSpecificationEntity copyWith({
    String? id,
    String? tenantId,
    String? productId,
    String? name,
    int? price,
    bool? isDefault,
    int? displayOrder,
  }) {
    return ProductSpecificationEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      price: price ?? this.price,
      isDefault: isDefault ?? this.isDefault,
      displayOrder: displayOrder ?? this.displayOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductSpecificationEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          productId == other.productId &&
          name == other.name &&
          price == other.price &&
          isDefault == other.isDefault &&
          displayOrder == other.displayOrder;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        productId,
        name,
        price,
        isDefault,
        displayOrder,
      );

  @override
  String toString() =>
      'ProductSpecificationEntity(id: $id, name: $name, price: $price)';
}
