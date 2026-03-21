/// Domain entity for an inventory stock movement.
library;

enum TransactionType {
  restock,
  sale,
  waste,
  adjustment;

  static TransactionType fromString(String s) => TransactionType.values
      .firstWhere((e) => e.name == s, orElse: () => TransactionType.adjustment);

  bool get isInbound => this == TransactionType.restock;
  bool get isOutbound =>
      this == TransactionType.sale || this == TransactionType.waste;
}

class InventoryTransactionEntity {
  final String id;
  final String tenantId;
  final String itemId;
  final TransactionType type;

  /// Signed delta: positive = stock added, negative = stock removed.
  final double quantity;
  final double quantityBefore;
  final double quantityAfter;
  final DateTime timestamp;
  final String? userId;
  final String? userName;
  final String? ticketId;
  final String? notes;

  const InventoryTransactionEntity({
    required this.id,
    required this.tenantId,
    required this.itemId,
    required this.type,
    required this.quantity,
    required this.quantityBefore,
    required this.quantityAfter,
    required this.timestamp,
    this.userId,
    this.userName,
    this.ticketId,
    this.notes,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryTransactionEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
