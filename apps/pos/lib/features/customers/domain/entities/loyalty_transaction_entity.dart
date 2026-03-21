import 'package:equatable/equatable.dart';

enum LoyaltyTransactionType { earn, redeem, adjust, expire }

class LoyaltyTransactionEntity extends Equatable {
  final String id;
  final String customerId;
  final int points; // positive = earn, negative = redeem/expire
  final LoyaltyTransactionType type;
  final String? orderId;
  final String? description;
  final DateTime createdAt;

  const LoyaltyTransactionEntity({
    required this.id,
    required this.customerId,
    required this.points,
    required this.type,
    this.orderId,
    this.description,
    required this.createdAt,
  });

  bool get isEarning => points > 0;
  bool get isSpending => points < 0;

  @override
  List<Object?> get props => [id, customerId, points, type, orderId,
      description, createdAt];
}
