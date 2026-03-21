/// Domain models for online ordering menu data.
/// Mirrors the Go backend's online/models.go response shapes.
library;

// ---------------------------------------------------------------------------
// Restaurant info
// ---------------------------------------------------------------------------

class OnlineRestaurant {
  final String id;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? coverImageUrl;
  final bool isOpen;
  final String? closedMessage;
  final int estimatedWaitMinutes;

  const OnlineRestaurant({
    required this.id,
    required this.name,
    this.description,
    this.logoUrl,
    this.coverImageUrl,
    required this.isOpen,
    this.closedMessage,
    this.estimatedWaitMinutes = 20,
  });

  factory OnlineRestaurant.fromJson(Map<String, dynamic> json) =>
      OnlineRestaurant(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        logoUrl: json['logo_url'] as String?,
        coverImageUrl: json['cover_image_url'] as String?,
        isOpen: json['is_open'] as bool? ?? true,
        closedMessage: json['closed_message'] as String?,
        estimatedWaitMinutes:
            json['estimated_wait_minutes'] as int? ?? 20,
      );
}

// ---------------------------------------------------------------------------
// Category
// ---------------------------------------------------------------------------

class OnlineCategory {
  final String id;
  final String name;
  final int displayOrder;
  final String? color;
  final String? iconName;

  const OnlineCategory({
    required this.id,
    required this.name,
    required this.displayOrder,
    this.color,
    this.iconName,
  });

  factory OnlineCategory.fromJson(Map<String, dynamic> json) =>
      OnlineCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        displayOrder: json['display_order'] as int? ?? 0,
        color: json['color'] as String?,
        iconName: json['icon'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Product
// ---------------------------------------------------------------------------

class OnlineProduct {
  final String id;
  final String categoryId;
  final String name;
  final String? description;

  /// Price in Rappen (cents). e.g. 1500 = CHF 15.00.
  final int price;

  final String taxGroup;
  final String? imageUrl;
  final bool isAvailable;
  final int displayOrder;
  final int? prepTimeMinutes;
  final List<OnlineModifierGroup> modifierGroups;

  const OnlineProduct({
    required this.id,
    required this.categoryId,
    required this.name,
    this.description,
    required this.price,
    required this.taxGroup,
    this.imageUrl,
    required this.isAvailable,
    required this.displayOrder,
    this.prepTimeMinutes,
    this.modifierGroups = const [],
  });

  bool get hasModifiers => modifierGroups.isNotEmpty;

  factory OnlineProduct.fromJson(Map<String, dynamic> json) =>
      OnlineProduct(
        id: json['id'] as String,
        categoryId: json['category_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        price: (json['price'] as num).toInt(),
        taxGroup: json['tax_group'] as String? ?? 'standard',
        imageUrl: json['image_url'] as String?,
        isAvailable: json['is_available'] as bool? ?? true,
        displayOrder: json['display_order'] as int? ?? 0,
        prepTimeMinutes: json['prep_time_minutes'] as int?,
        modifierGroups: (json['modifier_groups'] as List<dynamic>? ?? [])
            .map((g) =>
                OnlineModifierGroup.fromJson(g as Map<String, dynamic>))
            .toList(),
      );
}

// ---------------------------------------------------------------------------
// Modifier group & modifier
// ---------------------------------------------------------------------------

class OnlineModifierGroup {
  final String id;
  final String name;
  final String selectionType; // 'single' | 'multiple'
  final int minSelections;
  final int maxSelections;
  final bool isRequired;
  final int displayOrder;
  final List<OnlineModifier> modifiers;

  const OnlineModifierGroup({
    required this.id,
    required this.name,
    required this.selectionType,
    required this.minSelections,
    required this.maxSelections,
    required this.isRequired,
    required this.displayOrder,
    required this.modifiers,
  });

  bool get isSingle => selectionType == 'single';

  factory OnlineModifierGroup.fromJson(Map<String, dynamic> json) =>
      OnlineModifierGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        selectionType: json['selection_type'] as String? ?? 'single',
        minSelections: json['min_selections'] as int? ?? 0,
        maxSelections: json['max_selections'] as int? ?? 1,
        isRequired: json['is_required'] as bool? ?? false,
        displayOrder: json['display_order'] as int? ?? 0,
        modifiers: (json['modifiers'] as List<dynamic>? ?? [])
            .map((m) =>
                OnlineModifier.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

class OnlineModifier {
  final String id;
  final String groupId;
  final String name;

  /// Price delta in Rappen. Positive = surcharge, negative = discount.
  final int priceDelta;
  final bool isDefault;
  final int displayOrder;

  const OnlineModifier({
    required this.id,
    required this.groupId,
    required this.name,
    required this.priceDelta,
    required this.isDefault,
    required this.displayOrder,
  });

  factory OnlineModifier.fromJson(Map<String, dynamic> json) =>
      OnlineModifier(
        id: json['id'] as String,
        groupId: json['group_id'] as String? ?? '',
        name: json['name'] as String,
        priceDelta: (json['price_delta'] as num?)?.toInt() ?? 0,
        isDefault: json['is_default'] as bool? ?? false,
        displayOrder: json['display_order'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Full menu response
// ---------------------------------------------------------------------------

class OnlineMenu {
  final OnlineRestaurant restaurant;
  final List<OnlineCategory> categories;
  final List<OnlineProduct> products;

  const OnlineMenu({
    required this.restaurant,
    required this.categories,
    required this.products,
  });

  factory OnlineMenu.fromJson(Map<String, dynamic> json) => OnlineMenu(
        restaurant: OnlineRestaurant.fromJson(
            json['restaurant'] as Map<String, dynamic>),
        categories: (json['categories'] as List<dynamic>? ?? [])
            .map((c) =>
                OnlineCategory.fromJson(c as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder)),
        products: (json['products'] as List<dynamic>? ?? [])
            .map((p) =>
                OnlineProduct.fromJson(p as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder)),
      );

  List<OnlineProduct> productsForCategory(String categoryId) =>
      products.where((p) => p.categoryId == categoryId).toList();
}
