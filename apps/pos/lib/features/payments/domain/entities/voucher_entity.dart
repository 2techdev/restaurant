library;

class VoucherEntity {
  final String code;
  final int discountAmount;

  const VoucherEntity({
    required this.code,
    required this.discountAmount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoucherEntity &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          discountAmount == other.discountAmount;

  @override
  int get hashCode => Object.hash(code, discountAmount);

  @override
  String toString() => 'VoucherEntity(code: $code, discount: $discountAmount)';
}
