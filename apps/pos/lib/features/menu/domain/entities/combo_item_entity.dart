/// Combo (set menu) component entity.
///
/// Mirrors the `combo_items` Drift table. Each row is one component of a
/// combo product — either a fixed inclusion (`groupName == null`) or a
/// "choose one" option in a named group ("Choose your drink", "Choose
/// your side"). The POS picker presents each group and lets the cashier
/// confirm or substitute when [canSubstitute] is true.
library;

class ComboItemEntity {
  const ComboItemEntity({
    required this.id,
    required this.tenantId,
    required this.comboProductId,
    required this.itemProductId,
    this.quantity = 1,
    this.groupName,
    this.isRequired = true,
    this.canSubstitute = false,
    this.displayOrder = 0,
  });

  final String id;
  final String tenantId;
  final String comboProductId;
  final String itemProductId;
  final int quantity;

  /// Free-form group name. When non-null, all rows that share this name
  /// form a "choose one" group ([canSubstitute] picks how aggressive the
  /// UI is about offering swaps).
  final String? groupName;

  final bool isRequired;
  final bool canSubstitute;
  final int displayOrder;
}
