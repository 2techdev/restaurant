/// Product (menu item) entity.
///
/// Represents a sellable item on the POS grid. Prices are stored as integers
/// in the smallest currency unit (cents / Rappen) to avoid floating-point
/// rounding issues.
library;

import 'package:gastrocore_pos/features/menu/domain/entities/modifier_entity.dart';

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

  /// Tax group identifier (e.g. "standard", "reduced").
  final String taxGroup;

  /// Optional local asset or network path for the product image.
  final String? imagePath;

  /// Optional EAN / UPC barcode for scanner lookup.
  final String? barcode;

  final bool isActive;

  /// Operator-facing "sold out / 86'd" flag. When false the product is
  /// still on the menu (isActive) but temporarily cannot be ordered —
  /// the POS grid greys it out and blocks taps until the cashier flips
  /// it back on. Default true so existing rows stay sellable.
  final bool isAvailable;

  final int displayOrder;

  /// Estimated preparation time in minutes (shown on kitchen display).
  final int? prepTimeMinutes;

  /// Printer routing group (e.g. "kitchen", "bar", "dessert").
  final String printerGroup;

  /// Modifier groups attached to this product (e.g. "Size", "Extras").
  final List<ModifierGroupEntity> modifierGroups;

  // -------------------------------------------------------------------------
  // Expanded fields (OrderPin-compatible)
  // -------------------------------------------------------------------------

  /// Stock status: 'in_stock', 'out_of_stock', 'out_of_stock_today', 'delisted'.
  final String stockStatus;

  /// Whether this product allows manual price entry (open price).
  final bool isOpenPrice;

  /// Whether this product uses weight-based pricing.
  final bool isWeightBased;

  /// Unit of weight measurement ('kg', 'g').
  final String? weightUnit;

  /// Default Gang (course group) for this product.
  /// References GangTemplate.id. Null = fall back to category default.
  final String? defaultGangId;

  /// Whether this product is a combo / set menu bundling child products.
  /// When true, the repository loads the component list from ComboItems
  /// at cart time.
  final bool isCombo;

  /// Optional flat discount applied to the bundle, in cents. When null
  /// the combo charges the parent product's own [price]; when set the
  /// price is `sum(component unit prices * quantity) - comboDiscountCents`
  /// floored at zero.
  final int? comboDiscountCents;

  /// "Online'da popüler" — surfaced read-only in the linked-items overlay
  /// tab. Authored in the Gastro Hub admin panel and synced down via
  /// menu_sync (server migration 026 / local Drift v24). Default false.
  final bool isPopularOnline;

  /// Raw JSON blob (string-encoded) carrying the cloud allergen breakdown,
  /// e.g. `{"contains":["gluten"],"mayContain":["nuts"],"freeFrom":[]}`.
  /// Decoded only inside [LinkedItemsOverlayTab] — every other surface
  /// ignores it. Null when no allergen info has been published yet.
  final String? allergenInfo;

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
    this.isAvailable = true,
    required this.displayOrder,
    this.prepTimeMinutes,
    required this.printerGroup,
    this.modifierGroups = const [],
    this.stockStatus = 'in_stock',
    this.isOpenPrice = false,
    this.isWeightBased = false,
    this.weightUnit,
    this.defaultGangId,
    this.isCombo = false,
    this.comboDiscountCents,
    this.isPopularOnline = false,
    this.allergenInfo,
  });

  /// Whether this product has configurable modifiers.
  bool get hasModifiers => modifierGroups.isNotEmpty;

  /// Create a copy with selectively overridden fields.
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
    bool? isAvailable,
    int? displayOrder,
    int? Function()? prepTimeMinutes,
    String? printerGroup,
    List<ModifierGroupEntity>? modifierGroups,
    String? stockStatus,
    bool? isOpenPrice,
    bool? isWeightBased,
    String? Function()? weightUnit,
    String? Function()? defaultGangId,
    bool? isCombo,
    int? Function()? comboDiscountCents,
    bool? isPopularOnline,
    String? Function()? allergenInfo,
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
      isAvailable: isAvailable ?? this.isAvailable,
      displayOrder: displayOrder ?? this.displayOrder,
      prepTimeMinutes:
          prepTimeMinutes != null ? prepTimeMinutes() : this.prepTimeMinutes,
      printerGroup: printerGroup ?? this.printerGroup,
      modifierGroups: modifierGroups ?? this.modifierGroups,
      stockStatus: stockStatus ?? this.stockStatus,
      isOpenPrice: isOpenPrice ?? this.isOpenPrice,
      isWeightBased: isWeightBased ?? this.isWeightBased,
      weightUnit: weightUnit != null ? weightUnit() : this.weightUnit,
      defaultGangId:
          defaultGangId != null ? defaultGangId() : this.defaultGangId,
      isCombo: isCombo ?? this.isCombo,
      comboDiscountCents: comboDiscountCents != null
          ? comboDiscountCents()
          : this.comboDiscountCents,
      isPopularOnline: isPopularOnline ?? this.isPopularOnline,
      allergenInfo: allergenInfo != null ? allergenInfo() : this.allergenInfo,
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
          description == other.description &&
          price == other.price &&
          costPrice == other.costPrice &&
          taxGroup == other.taxGroup &&
          imagePath == other.imagePath &&
          barcode == other.barcode &&
          isActive == other.isActive &&
          isAvailable == other.isAvailable &&
          displayOrder == other.displayOrder &&
          prepTimeMinutes == other.prepTimeMinutes &&
          printerGroup == other.printerGroup &&
          stockStatus == other.stockStatus &&
          isOpenPrice == other.isOpenPrice &&
          isWeightBased == other.isWeightBased &&
          weightUnit == other.weightUnit;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        categoryId,
        name,
        description,
        price,
        costPrice,
        taxGroup,
        imagePath,
        barcode,
        isActive,
        isAvailable,
        displayOrder,
        prepTimeMinutes,
        printerGroup,
        stockStatus,
        isOpenPrice,
        isWeightBased,
        weightUnit,
      );

  @override
  String toString() =>
      'ProductEntity(id: $id, name: $name, price: $price)';
}
