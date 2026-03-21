/// Domain entity for a stockable inventory item.
library;

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.tenantId,
    required this.name,
    this.sku,
    required this.unit,
    required this.currentQty,
    required this.minQty,
    this.maxQty,
    this.costPerUnit,
    this.supplier,
    this.notes,
    required this.isActive,
    required this.isLow,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String tenantId;
  final String name;
  final String? sku;
  final String unit;
  final double currentQty;
  final double minQty;
  final double? maxQty;
  final int? costPerUnit; // cents
  final String? supplier;
  final String? notes;
  final bool isActive;
  final bool isLow;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      name: json['name'] as String,
      sku: json['sku'] as String?,
      unit: json['unit'] as String? ?? 'unit',
      currentQty: (json['current_qty'] as num).toDouble(),
      minQty: (json['min_qty'] as num).toDouble(),
      maxQty: json['max_qty'] != null ? (json['max_qty'] as num).toDouble() : null,
      costPerUnit: json['cost_per_unit'] as int?,
      supplier: json['supplier'] as String?,
      notes: json['notes'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      isLow: json['is_low'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        if (sku != null) 'sku': sku,
        'unit': unit,
        'current_qty': currentQty,
        'min_qty': minQty,
        if (maxQty != null) 'max_qty': maxQty,
        if (costPerUnit != null) 'cost_per_unit': costPerUnit,
        if (supplier != null) 'supplier': supplier,
        if (notes != null) 'notes': notes,
        'is_active': isActive,
      };

  InventoryItem copyWith({
    double? currentQty,
    bool? isLow,
    bool? isActive,
    String? name,
    double? minQty,
    double? maxQty,
    String? unit,
    String? supplier,
    String? notes,
  }) {
    return InventoryItem(
      id: id,
      tenantId: tenantId,
      name: name ?? this.name,
      sku: sku,
      unit: unit ?? this.unit,
      currentQty: currentQty ?? this.currentQty,
      minQty: minQty ?? this.minQty,
      maxQty: maxQty ?? this.maxQty,
      costPerUnit: costPerUnit,
      supplier: supplier ?? this.supplier,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      isLow: isLow ?? this.isLow,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
