/// Combo / set-menu entities.
///
/// A combo is a regular [ProductEntity] with `isCombo = true` that
/// bundles a list of [ComboItemEntity] children. When the cashier adds
/// a combo to a ticket the POS expands the bundle into its components
/// so each component prints to its correct station; the combo price is
/// either the combo's own [price] or `sum(components) - comboDiscountCents`
/// depending on [ComboPricingMode].
library;

/// How a combo's total price is computed at checkout.
enum ComboPricingMode {
  /// Use the combo product's own [price] column. Simpler for menus that
  /// advertise a fixed bundle price (e.g. "Menu 3 — CHF 19.90").
  fixed,

  /// Sum the component prices and subtract `comboDiscountCents`, floored
  /// at zero. Used when each component's stand-alone price is shown and
  /// the bundle advertises a saving.
  sumMinusDiscount,
}

class ComboItemEntity {
  const ComboItemEntity({
    required this.id,
    required this.tenantId,
    required this.comboProductId,
    required this.itemProductId,
    this.itemProductName,
    this.itemUnitPrice,
    this.quantity = 1,
    this.groupName,
    this.isRequired = true,
    this.canSubstitute = false,
    this.displayOrder = 0,
  });

  final String id;
  final String tenantId;

  /// The PARENT combo product.
  final String comboProductId;

  /// The child (component) product included in this combo slot.
  final String itemProductId;

  /// Convenience cache so the UI can render a combo without a second
  /// product lookup. Populated by the repository when it joins against
  /// [Products] during load; callers writing combos leave it null.
  final String? itemProductName;
  final int? itemUnitPrice;

  final int quantity;

  /// Slot label — `null` means a fixed component ("+ Small fries"),
  /// a non-null value means a pickable group ("Choose your drink").
  final String? groupName;

  /// Whether the operator must pick this slot at POS time. Only
  /// meaningful when [groupName] is set (group items that aren't
  /// required can be skipped). Default true.
  final bool isRequired;

  /// Whether the operator is allowed to swap the component for another
  /// product at POS time. Default false.
  final bool canSubstitute;

  final int displayOrder;

  ComboItemEntity copyWith({
    String? id,
    String? tenantId,
    String? comboProductId,
    String? itemProductId,
    String? itemProductName,
    int? itemUnitPrice,
    int? quantity,
    String? Function()? groupName,
    bool? isRequired,
    bool? canSubstitute,
    int? displayOrder,
  }) {
    return ComboItemEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      comboProductId: comboProductId ?? this.comboProductId,
      itemProductId: itemProductId ?? this.itemProductId,
      itemProductName: itemProductName ?? this.itemProductName,
      itemUnitPrice: itemUnitPrice ?? this.itemUnitPrice,
      quantity: quantity ?? this.quantity,
      groupName: groupName != null ? groupName() : this.groupName,
      isRequired: isRequired ?? this.isRequired,
      canSubstitute: canSubstitute ?? this.canSubstitute,
      displayOrder: displayOrder ?? this.displayOrder,
    );
  }
}

/// View-model that pairs a combo's parent product with its resolved
/// component list. Returned by the menu repository's `getComboFor`.
class ComboEntity {
  const ComboEntity({
    required this.comboProductId,
    required this.items,
    this.discountCents,
  });

  final String comboProductId;
  final List<ComboItemEntity> items;

  /// When non-null the combo price at checkout is
  /// `sum(item.unitPrice * item.quantity) - discountCents`, floored at 0.
  /// When null the parent product's own `price` is used instead.
  final int? discountCents;

  ComboPricingMode get mode =>
      discountCents == null ? ComboPricingMode.fixed : ComboPricingMode.sumMinusDiscount;

  /// Price the combo given a fallback [fixedPrice] from the combo's
  /// parent product row. Returns cents. Never negative.
  int priceCents({required int fixedPrice}) {
    if (discountCents == null) return fixedPrice;
    final sum = items.fold<int>(
      0,
      (acc, e) => acc + (e.itemUnitPrice ?? 0) * e.quantity,
    );
    final adjusted = sum - discountCents!;
    return adjusted < 0 ? 0 : adjusted;
  }
}
