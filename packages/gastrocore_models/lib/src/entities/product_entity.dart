/// Product (menu item) entity.
library;

import 'modifier_entity.dart';

/// Immutable representation of a menu product.
class ProductEntity {
  final String id;
  final String tenantId;
  final String categoryId;
  final String name;
  final String? description;

  /// Selling price in cents (e.g. 1500 = CHF 15.00).
  final int price;

  /// Cost price in cents for margin calculations.
  final int costPrice;

  /// Tax group identifier (e.g. "food", "beverage", "standard").
  final String taxGroup;

  final String? imagePath;
  final String? barcode;
  final bool isActive;
  final int displayOrder;

  /// Estimated preparation time in minutes.
  final int? prepTimeMinutes;

  /// Printer routing group (e.g. "kitchen", "bar", "dessert").
  final String printerGroup;

  final List<ModifierGroupEntity> modifierGroups;

  /// Stock status: 'in_stock', 'out_of_stock', 'out_of_stock_today', 'delisted'.
  final String stockStatus;

  /// Whether this product allows manual price entry (open price).
  final bool isOpenPrice;

  /// Whether this product uses weight-based pricing.
  final bool isWeightBased;

  /// Unit of weight measurement ('kg', 'g').
  final String? weightUnit;

  const ProductEntity({
    required this.id,
    required this.tenantId,
    required this.categoryId,
    required this.name,
    this.description,
    required this.price,
    required this.costPrice,
    required this.taxGroup,
    this.imagePath,
    this.barcode,
    required this.isActive,
    required this.displayOrder,
    this.prepTimeMinutes,
    required this.printerGroup,
    this.modifierGroups = const [],
    this.stockStatus = 'in_stock',
    this.isOpenPrice = false,
    this.isWeightBased = false,
    this.weightUnit,
  });

  bool get hasModifiers => modifierGroups.isNotEmpty;

  factory ProductEntity.fromJson(Map<String, dynamic> json) => ProductEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        categoryId: json['category_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        price: (json['price'] as num).toInt(),
        costPrice: (json['cost_price'] as num?)?.toInt() ?? 0,
        taxGroup: json['tax_group'] as String? ?? 'standard',
        imagePath: json['image_path'] as String?,
        barcode: json['barcode'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        displayOrder: json['display_order'] as int? ?? 0,
        prepTimeMinutes: json['prep_time_minutes'] as int?,
        printerGroup: json['printer_group'] as String? ?? 'kitchen',
        modifierGroups: (json['modifier_groups'] as List<dynamic>? ?? [])
            .map((g) =>
                ModifierGroupEntity.fromJson(g as Map<String, dynamic>))
            .toList(),
        stockStatus: json['stock_status'] as String? ?? 'in_stock',
        isOpenPrice: json['is_open_price'] as bool? ?? false,
        isWeightBased: json['is_weight_based'] as bool? ?? false,
        weightUnit: json['weight_unit'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'category_id': categoryId,
        'name': name,
        if (description != null) 'description': description,
        'price': price,
        'cost_price': costPrice,
        'tax_group': taxGroup,
        if (imagePath != null) 'image_path': imagePath,
        if (barcode != null) 'barcode': barcode,
        'is_active': isActive,
        'display_order': displayOrder,
        if (prepTimeMinutes != null) 'prep_time_minutes': prepTimeMinutes,
        'printer_group': printerGroup,
        'modifier_groups': modifierGroups.map((g) => g.toJson()).toList(),
        'stock_status': stockStatus,
        'is_open_price': isOpenPrice,
        'is_weight_based': isWeightBased,
        if (weightUnit != null) 'weight_unit': weightUnit,
      };

  ProductEntity copyWith({
    String? id,
    String? tenantId,
    String? categoryId,
    String? name,
    String? Function()? description,
    int? price,
    int? costPrice,
    String? taxGroup,
    String? Function()? imagePath,
    String? Function()? barcode,
    bool? isActive,
    int? displayOrder,
    int? Function()? prepTimeMinutes,
    String? printerGroup,
    List<ModifierGroupEntity>? modifierGroups,
    String? stockStatus,
    bool? isOpenPrice,
    bool? isWeightBased,
    String? Function()? weightUnit,
  }) {
    return ProductEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      description: description != null ? description() : this.description,
      price: price ?? this.price,
      costPrice: costPrice ?? this.costPrice,
      taxGroup: taxGroup ?? this.taxGroup,
      imagePath: imagePath != null ? imagePath() : this.imagePath,
      barcode: barcode != null ? barcode() : this.barcode,
      isActive: isActive ?? this.isActive,
      displayOrder: displayOrder ?? this.displayOrder,
      prepTimeMinutes:
          prepTimeMinutes != null ? prepTimeMinutes() : this.prepTimeMinutes,
      printerGroup: printerGroup ?? this.printerGroup,
      modifierGroups: modifierGroups ?? this.modifierGroups,
      stockStatus: stockStatus ?? this.stockStatus,
      isOpenPrice: isOpenPrice ?? this.isOpenPrice,
      isWeightBased: isWeightBased ?? this.isWeightBased,
      weightUnit: weightUnit != null ? weightUnit() : this.weightUnit,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          categoryId == other.categoryId &&
          name == other.name &&
          price == other.price &&
          costPrice == other.costPrice &&
          taxGroup == other.taxGroup &&
          isActive == other.isActive &&
          displayOrder == other.displayOrder &&
          printerGroup == other.printerGroup &&
          stockStatus == other.stockStatus &&
          isOpenPrice == other.isOpenPrice &&
          isWeightBased == other.isWeightBased;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        categoryId,
        name,
        price,
        costPrice,
        taxGroup,
        isActive,
        displayOrder,
        printerGroup,
        stockStatus,
        isOpenPrice,
        isWeightBased,
      );

  @override
  String toString() =>
      'ProductEntity(id: $id, name: $name, price: $price)';
}
