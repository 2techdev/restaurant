import 'package:equatable/equatable.dart';

class CustomerEntity extends Equatable {
  final String id;
  final String tenantId;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final String? birthday; // "YYYY-MM-DD"
  final DateTime createdAt;
  final DateTime updatedAt;
  final int totalOrders;
  final int totalSpent; // cents
  final int loyaltyPoints;

  const CustomerEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.birthday,
    required this.createdAt,
    required this.updatedAt,
    this.totalOrders = 0,
    this.totalSpent = 0,
    this.loyaltyPoints = 0,
  });

  /// Points needed to earn CHF 1.00 discount.
  static const int pointsPerChf = 100;

  /// Points earned per CHF spent (1 CHF = 1 point).
  static const int pointsPerSpentChf = 1;

  /// Redeemable discount in cents (100 points → 100 cents = CHF 1.00).
  int get redeemableDiscountCents => loyaltyPoints * 1; // 1 point = 1 cent

  /// Whether today is within 7 days of birthday.
  bool get hasBirthdayThisWeek {
    if (birthday == null) return false;
    final parts = birthday!.split('-');
    if (parts.length != 3) return false;
    final now = DateTime.now();
    final bday = DateTime(now.year, int.parse(parts[1]), int.parse(parts[2]));
    final diff = bday.difference(DateTime(now.year, now.month, now.day)).inDays;
    return diff >= 0 && diff <= 7;
  }

  /// Tier based on total spent.
  CustomerTier get tier {
    final chfSpent = totalSpent ~/ 100;
    if (chfSpent >= 500) return CustomerTier.gold;
    if (chfSpent >= 200) return CustomerTier.silver;
    return CustomerTier.bronze;
  }

  CustomerEntity copyWith({
    String? name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    String? birthday,
    DateTime? updatedAt,
    int? totalOrders,
    int? totalSpent,
    int? loyaltyPoints,
  }) {
    return CustomerEntity(
      id: id,
      tenantId: tenantId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      birthday: birthday ?? this.birthday,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalOrders: totalOrders ?? this.totalOrders,
      totalSpent: totalSpent ?? this.totalSpent,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
    );
  }

  @override
  List<Object?> get props => [id, tenantId, name, phone, email, address,
      notes, birthday, createdAt, updatedAt, totalOrders, totalSpent,
      loyaltyPoints];
}

enum CustomerTier { bronze, silver, gold }
