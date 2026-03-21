/// Domain entity for an inventory item (stock record).
library;

enum StockStatus { normal, low, out }

class InventoryItemEntity {
  final String id;
  final String tenantId;
  final String? productId;
  final String name;
  final double quantity;
  final double minQuantity;
  final String unit;
  final String? supplierId;
  final int costPriceCents;
  final DateTime? lastRestockDate;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InventoryItemEntity({
    required this.id,
    required this.tenantId,
    this.productId,
    required this.name,
    required this.quantity,
    required this.minQuantity,
    required this.unit,
    this.supplierId,
    required this.costPriceCents,
    this.lastRestockDate,
    this.notes,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  StockStatus get stockStatus {
    if (quantity <= 0) return StockStatus.out;
    if (minQuantity > 0 && quantity <= minQuantity) return StockStatus.low;
    return StockStatus.normal;
  }

  bool get isLowStock => stockStatus == StockStatus.low;
  bool get isOutOfStock => stockStatus == StockStatus.out;
  bool get needsAttention => stockStatus != StockStatus.normal;

  /// Stock value in cents: quantity × costPriceCents.
  int get stockValueCents => (quantity * costPriceCents).round();

  InventoryItemEntity copyWith({
    String? id,
    String? tenantId,
    String? productId,
    String? name,
    double? quantity,
    double? minQuantity,
    String? unit,
    String? supplierId,
    int? costPriceCents,
    DateTime? lastRestockDate,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InventoryItemEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      minQuantity: minQuantity ?? this.minQuantity,
      unit: unit ?? this.unit,
      supplierId: supplierId ?? this.supplierId,
      costPriceCents: costPriceCents ?? this.costPriceCents,
      lastRestockDate: lastRestockDate ?? this.lastRestockDate,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryItemEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
