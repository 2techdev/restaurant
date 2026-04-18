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

/// Hard upper bound on [ModifierGroupEntity.columnCount]. Keeps the
/// modifier-dialog grid sane regardless of what's been saved.
const int kModifierColumnUpperBound = 6;

/// A named group of modifiers attached to a product.
///
/// Carries SambaPOS-parity Order Tag Group parameters:
///   * [minSelections] / [maxSelections] enforce selection counts
///     (maxSelections = 0 means unlimited).
///   * [askQuantity] — each modifier can be picked with a quantity
///     > 1 (e.g. "3× Extra Cheese").
///   * [freeTagging] — operator can type a free-form tag not in the
///     predefined list (e.g. "less salt").
///   * [columnCount] — grid layout hint for the selection UI.
///   * [prefix] — display prefix for modifier names on receipts and
///     the kitchen ticket (e.g. "+ " for additions, "- " for
///     omissions, "* " for notes).
class ModifierGroupEntity {
  final String id;
  final String tenantId;
  final String name;
  final ModifierSelectionType selectionType;

  /// Minimum number of selections the customer must make.
  final int minSelections;

  /// Maximum number of selections allowed. Zero means unlimited — a
  /// SambaPOS convention that lets callers encode "no cap" without a
  /// magic sentinel like `-1`.
  final int maxSelections;

  /// Whether the group must be acknowledged before adding to order.
  final bool isRequired;

  /// Allow each selected modifier to carry a quantity > 1.
  final bool askQuantity;

  /// Allow the operator to add free-form tags not in [modifiers].
  final bool freeTagging;

  /// Grid layout hint for the selection UI — how many columns to
  /// render. Clamped to `[1, kModifierColumnUpperBound]`.
  final int columnCount;

  /// Display prefix prepended to modifier names on receipts and
  /// kitchen tickets. Common values: `"+ "`, `"- "`, `"* "`.
  final String prefix;

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
    this.askQuantity = false,
    this.freeTagging = false,
    this.columnCount = 1,
    this.prefix = '',
    this.modifiers = const [],
  });

  /// Whether the group enforces an upper bound on selections. Returns
  /// false when [maxSelections] is 0 (= unlimited, SambaPOS convention).
  bool get hasUpperBound => maxSelections > 0;

  /// Given a candidate selection count, is it within this group's
  /// min / max bounds? Used by the selection UI to decide whether to
  /// allow submission.
  bool isSelectionValid(int count) {
    if (count < minSelections) return false;
    if (hasUpperBound && count > maxSelections) return false;
    return true;
  }

  /// Clamp [columnCount] at read-time so a corrupt row can't break
  /// the UI. Returns the effective column count (1..upperBound).
  int get effectiveColumnCount {
    if (columnCount < 1) return 1;
    if (columnCount > kModifierColumnUpperBound) {
      return kModifierColumnUpperBound;
    }
    return columnCount;
  }

  /// Apply the group's [prefix] to a modifier [name]. Returns the
  /// bare name when the prefix is empty so we don't emit stray
  /// leading whitespace onto receipts.
  String displayName(String name) => prefix.isEmpty ? name : '$prefix$name';

  /// Create a copy with selectively overridden fields.
  ModifierGroupEntity copyWith({
    String? id,
    String? tenantId,
    String? name,
    ModifierSelectionType? selectionType,
    int? minSelections,
    int? maxSelections,
    bool? isRequired,
    bool? askQuantity,
    bool? freeTagging,
    int? columnCount,
    String? prefix,
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
      askQuantity: askQuantity ?? this.askQuantity,
      freeTagging: freeTagging ?? this.freeTagging,
      columnCount: columnCount ?? this.columnCount,
      prefix: prefix ?? this.prefix,
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
          askQuantity == other.askQuantity &&
          freeTagging == other.freeTagging &&
          columnCount == other.columnCount &&
          prefix == other.prefix &&
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
        askQuantity,
        freeTagging,
        columnCount,
        prefix,
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
