library;

import 'package:gastrocore_pos/features/payments/domain/entities/voucher_entity.dart';

abstract class VoucherRepository {
  Future<VoucherEntity?> validate(String code);
}

class StubVoucherRepository implements VoucherRepository {
  const StubVoucherRepository();

  @override
  Future<VoucherEntity?> validate(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.startsWith('GS-') && trimmed.length > 3) {
      return VoucherEntity(code: trimmed, discountAmount: 1000);
    }
    return null;
  }
}
