/// Modifier group and modifier entities.
///
/// Modifier groups define a set of options that can be applied to a product
/// (e.g. "Size" with options Small / Medium / Large, or "Extras" with
/// options Extra Cheese / Bacon / Jalapenos).
library;

// ---------------------------------------------------------------------------
// Selection type
// ---------------------------------------------------------------------------

/// How many modifiers can be selected from a group.
enum ModifierSelectionType {
  /// Exactly one option must be chosen (radio-button style).
  single,

  /// Zero or more options may be chosen (checkbox style).
  multiple,
}

// ---------------------------------------------------------------------------
// ModifierGroupEntity
// ---------------------------------------------------------------------------

/// A named group of modifiers attached to a product.
class ModifierGroupEntity {
  final String id;
  final String tenantId;
  final String name;
  final ModifierSelectionType selectionType;

  /// Minimum number of selections the customer must make.
  final int minSelections;

  /// Maximum number of selections allowed.
  final int maxSelections;

  /// Whether the group must be acknowledged before adding to order.
  final bool isRequired;

  final int displayOrder;

  /// Individual modifier options within this group.
  final List<ModifierEntity> modifiers;

  const ModifierGroupEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.selectionType,
    required this.minSelections,
    required this.maxSelections,
    required this.isRequired,
    required this.displayOrder,
    this.modifiers = const [],
  });

  /// Create a copy with selectively overridden fields.
  ModifierGroupEntity copyWith({
    String? id,
    String? tenantId,
    String? name,
    ModifierSelectionType? selectionType,
    int? minSelections,
    int? maxSelections,
    bool? isRequired,
    int? displayOrder,
    List<ModifierEntity>? modifiers,
  }) {
    return ModifierGroupEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      selectionType: selectionType ?? this.selectionType,
      minSelections: minSelections ?? this.minSelections,
      maxSelections: maxSelections ?? this.maxSelections,
      isRequired: isRequired ?? this.isRequired,
      displayOrder: displayOrder ?? this.displayOrder,
      modifiers: modifiers ?? this.modifiers,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModifierGroupEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          name == other.name &&
          selectionType == other.selectionType &&
          minSelections == other.minSelections &&
          maxSelections == other.maxSelections &&
          isRequired == other.isRequired &&
          displayOrder == other.displayOrder;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        name,
        selectionType,
        minSelections,
        maxSelections,
        isRequired,
        displayOrder,
      );

  @override
  String toString() =>
      'ModifierGroupEntity(id: $id, name: $name, type: ${selectionType.name})';
}

// ---------------------------------------------------------------------------
// ModifierEntity
// ---------------------------------------------------------------------------

/// A single modifier option within a [ModifierGroupEntity].
class ModifierEntity {
  final String id;
  final String tenantId;

  /// The group this modifier belongs to.
  final String groupId;

  final String name;

  /// Price adjustment in cents. Positive adds cost, negative gives discount.
  final int priceDelta;

  /// Whether this modifier is pre-selected by default.
  final bool isDefault;

  final int displayOrder;

  const ModifierEntity({
    required this.id,
    required this.tenantId,
    required this.groupId,
    required this.name,
    required this.priceDelta,
    required this.isDefault,
    required this.displayOrder,
  });

  /// Create a copy with selectively overridden fields.
  ModifierEntity copyWith({
    String? id,
    String? tenantId,
    String? groupId,
    String? name,
    int? priceDelta,
    bool? isDefault,
    int? displayOrder,
  }) {
    return ModifierEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      groupId: groupId ?? this.groupId,
      name: name ?? this.name,
      priceDelta: priceDelta ?? this.priceDelta,
      isDefault: isDefault ?? this.isDefault,
      displayOrder: displayOrder ?? this.displayOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModifierEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          groupId == other.groupId &&
          name == other.name &&
          priceDelta == other.priceDelta &&
          isDefault == other.isDefault &&
          displayOrder == other.displayOrder;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        groupId,
        name,
        priceDelta,
        isDefault,
        displayOrder,
      );

  @override
  String toString() =>
      'ModifierEntity(id: $id, name: $name, delta: $priceDelta)';
}
