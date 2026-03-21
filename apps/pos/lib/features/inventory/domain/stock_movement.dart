/// Domain entity for a stock movement ledger entry.
library;

enum MovementType {
  stockIn,
  stockOut,
  waste,
  restock,
  adjustment;

  String get apiValue {
    switch (this) {
      case MovementType.stockIn:
        return 'stock_in';
      case MovementType.stockOut:
        return 'stock_out';
      case MovementType.waste:
        return 'waste';
      case MovementType.restock:
        return 'restock';
      case MovementType.adjustment:
        return 'adjustment';
    }
  }

  String get label {
    switch (this) {
      case MovementType.stockIn:
        return 'Stock In';
      case MovementType.stockOut:
        return 'Stock Out';
      case MovementType.waste:
        return 'Waste';
      case MovementType.restock:
        return 'Restock';
      case MovementType.adjustment:
        return 'Adjustment';
    }
  }

  bool get isDeduction => this == MovementType.stockOut || this == MovementType.waste;

  static MovementType fromApiValue(String value) {
    switch (value) {
      case 'stock_in':
        return MovementType.stockIn;
      case 'stock_out':
        return MovementType.stockOut;
      case 'waste':
        return MovementType.waste;
      case 'restock':
        return MovementType.restock;
      case 'adjustment':
        return MovementType.adjustment;
      default:
        return MovementType.adjustment;
    }
  }
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.tenantId,
    required this.itemId,
    this.itemName,
    required this.movementType,
    required this.qty,
    required this.qtyBefore,
    required this.qtyAfter,
    this.reference,
    this.notes,
    this.performedBy,
    required this.createdAt,
  });

  final String id;
  final String tenantId;
  final String itemId;
  final String? itemName;
  final MovementType movementType;
  final double qty;
  final double qtyBefore;
  final double qtyAfter;
  final String? reference;
  final String? notes;
  final String? performedBy;
  final DateTime createdAt;

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    return StockMovement(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      itemId: json['item_id'] as String,
      itemName: json['item_name'] as String?,
      movementType: MovementType.fromApiValue(json['movement_type'] as String),
      qty: (json['qty'] as num).toDouble(),
      qtyBefore: (json['qty_before'] as num).toDouble(),
      qtyAfter: (json['qty_after'] as num).toDouble(),
      reference: json['reference'] as String?,
      notes: json['notes'] as String?,
      performedBy: json['performed_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
