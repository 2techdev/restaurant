/// Modifier group and modifier entities.
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
  final int minSelections;
  final int maxSelections;
  final bool isRequired;
  final int displayOrder;
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

  factory ModifierGroupEntity.fromJson(Map<String, dynamic> json) =>
      ModifierGroupEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String? ?? '',
        name: json['name'] as String,
        selectionType: json['selection_type'] == 'multiple'
            ? ModifierSelectionType.multiple
            : ModifierSelectionType.single,
        minSelections: json['min_selections'] as int? ?? 0,
        maxSelections: json['max_selections'] as int? ?? 1,
        isRequired: json['is_required'] as bool? ?? false,
        displayOrder: json['display_order'] as int? ?? 0,
        modifiers: (json['modifiers'] as List<dynamic>? ?? [])
            .map((m) => ModifierEntity.fromJson(m as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        'selection_type': selectionType.name,
        'min_selections': minSelections,
        'max_selections': maxSelections,
        'is_required': isRequired,
        'display_order': displayOrder,
        'modifiers': modifiers.map((m) => m.toJson()).toList(),
      };

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
  final String groupId;
  final String name;

  /// Price adjustment in cents. Positive adds cost, negative gives discount.
  final int priceDelta;

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

  factory ModifierEntity.fromJson(Map<String, dynamic> json) => ModifierEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String? ?? '',
        groupId: json['group_id'] as String? ?? '',
        name: json['name'] as String,
        priceDelta: (json['price_delta'] as num?)?.toInt() ?? 0,
        isDefault: json['is_default'] as bool? ?? false,
        displayOrder: json['display_order'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'group_id': groupId,
        'name': name,
        'price_delta': priceDelta,
        'is_default': isDefault,
        'display_order': displayOrder,
      };

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
