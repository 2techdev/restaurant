/// Comprehensive tests for [PaymentEntity], [BillEntity] and supporting enums.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/features/payments/domain/entities/payment_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _paidAt = DateTime.utc(2026, 3, 23, 12, 0, 0);

PaymentEntity _payment({
  String id = 'pay-1',
  String tenantId = 'tenant-1',
  String billId = 'bill-1',
  String ticketId = 'ticket-1',
  PaymentMethod paymentMethod = PaymentMethod.cash,
  int amount = 2500,
  int tipAmount = 0,
  int tenderedAmount = 3000,
  int changeAmount = 500,
  String? reference,
  String receivedBy = 'user-1',
  DateTime? paidAt,
  String? paySubChannel,
  String? paymentForm,
  String? paymentReference,
  String? externalChannel,
  String? externalPaymentId,
  String? cashierName,
}) {
  return PaymentEntity(
    id: id,
    tenantId: tenantId,
    billId: billId,
    ticketId: ticketId,
    paymentMethod: paymentMethod,
    amount: amount,
    tipAmount: tipAmount,
    tenderedAmount: tenderedAmount,
    changeAmount: changeAmount,
    reference: reference,
    receivedBy: receivedBy,
    paidAt: paidAt ?? _paidAt,
    paySubChannel: paySubChannel,
    paymentForm: paymentForm,
    paymentReference: paymentReference,
    externalChannel: externalChannel,
    externalPaymentId: externalPaymentId,
    cashierName: cashierName,
  );
}

BillEntity _bill({
  String id = 'bill-1',
  String tenantId = 'tenant-1',
  String ticketId = 'ticket-1',
  String billNumber = 'REC-0001',
  int subtotal = 2313,
  int taxAmount = 187,
  int discountAmount = 0,
  int total = 2500,
  BillStatus status = BillStatus.open,
  List<PaymentEntity> payments = const [],
}) {
  return BillEntity(
    id: id,
    tenantId: tenantId,
    ticketId: ticketId,
    billNumber: billNumber,
    subtotal: subtotal,
    taxAmount: taxAmount,
    discountAmount: discountAmount,
    total: total,
    status: status,
    payments: payments,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // PaymentMethod enum
  // =========================================================================
  group('PaymentMethod enum', () {
    test('all payment methods exist', () {
      expect(PaymentMethod.values, contains(PaymentMethod.cash));
      expect(PaymentMethod.values, contains(PaymentMethod.creditCard));
      expect(PaymentMethod.values, contains(PaymentMethod.debitCard));
      expect(PaymentMethod.values, contains(PaymentMethod.other));
    });
  });

  // =========================================================================
  // BillStatus enum
  // =========================================================================
  group('BillStatus enum', () {
    test('all bill statuses exist', () {
      expect(BillStatus.values, contains(BillStatus.open));
      expect(BillStatus.values, contains(BillStatus.partiallyPaid));
      expect(BillStatus.values, contains(BillStatus.fullyPaid));
      expect(BillStatus.values, contains(BillStatus.voidStatus));
    });
  });

  // =========================================================================
  // PaymentEntity — construction
  // =========================================================================
  group('PaymentEntity — construction', () {
    test('constructs with required fields and defaults', () {
      final p = _payment();
      expect(p.id, 'pay-1');
      expect(p.tenantId, 'tenant-1');
      expect(p.billId, 'bill-1');
      expect(p.ticketId, 'ticket-1');
      expect(p.paymentMethod, PaymentMethod.cash);
      expect(p.amount, 2500);
      expect(p.tipAmount, 0);
      expect(p.tenderedAmount, 3000);
      expect(p.changeAmount, 500);
      expect(p.reference, isNull);
      expect(p.receivedBy, 'user-1');
      expect(p.paidAt, _paidAt);
    });

    test('optional extended fields default to null', () {
      final p = _payment();
      expect(p.paySubChannel, isNull);
      expect(p.paymentForm, isNull);
      expect(p.paymentReference, isNull);
      expect(p.externalChannel, isNull);
      expect(p.externalPaymentId, isNull);
      expect(p.cashierName, isNull);
    });

    test('constructs cash payment with tip', () {
      final p = _payment(amount: 2500, tipAmount: 250);
      expect(p.amount, 2500);
      expect(p.tipAmount, 250);
    });

    test('constructs credit card payment with reference', () {
      final p = _payment(
        paymentMethod: PaymentMethod.creditCard,
        amount: 5000,
        reference: 'TXID-9876',
        paymentForm: 'contactless',
      );
      expect(p.paymentMethod, PaymentMethod.creditCard);
      expect(p.reference, 'TXID-9876');
      expect(p.paymentForm, 'contactless');
    });

    test('constructs TWINT payment with external channel', () {
      final p = _payment(
        paymentMethod: PaymentMethod.other,
        externalChannel: 'TWINT',
        externalPaymentId: 'twint-tx-001',
      );
      expect(p.externalChannel, 'TWINT');
      expect(p.externalPaymentId, 'twint-tx-001');
    });

    test('constructs Wallee/ECR payment with sub-channel', () {
      final p = _payment(
        paymentMethod: PaymentMethod.debitCard,
        paySubChannel: 'GHL:ECR',
      );
      expect(p.paySubChannel, 'GHL:ECR');
    });
  });

  // =========================================================================
  // PaymentEntity — copyWith
  // =========================================================================
  group('PaymentEntity — copyWith', () {
    test('returns identical payment when no overrides', () {
      final p = _payment();
      final copy = p.copyWith();
      expect(copy, equals(p));
    });

    test('overrides amount', () {
      final p = _payment(amount: 2500);
      final copy = p.copyWith(amount: 5000);
      expect(copy.amount, 5000);
      expect(p.amount, 2500);
    });

    test('overrides paymentMethod', () {
      final p = _payment(paymentMethod: PaymentMethod.cash);
      final copy = p.copyWith(paymentMethod: PaymentMethod.creditCard);
      expect(copy.paymentMethod, PaymentMethod.creditCard);
    });

    test('overrides tipAmount', () {
      final p = _payment(tipAmount: 0);
      final copy = p.copyWith(tipAmount: 300);
      expect(copy.tipAmount, 300);
    });

    test('overrides tenderedAmount and changeAmount', () {
      final p = _payment(tenderedAmount: 3000, changeAmount: 500);
      final copy = p.copyWith(tenderedAmount: 5000, changeAmount: 2500);
      expect(copy.tenderedAmount, 5000);
      expect(copy.changeAmount, 2500);
    });

    test('sets reference via nullable override', () {
      final p = _payment();
      final copy = p.copyWith(reference: () => 'REF-001');
      expect(copy.reference, 'REF-001');
    });

    test('clears reference via nullable override', () {
      final p = _payment(reference: 'REF-001');
      final copy = p.copyWith(reference: () => null);
      expect(copy.reference, isNull);
    });

    test('overrides cashierName', () {
      final p = _payment();
      final copy = p.copyWith(cashierName: () => 'Hans Muster');
      expect(copy.cashierName, 'Hans Muster');
    });

    test('overrides externalChannel', () {
      final p = _payment();
      final copy = p.copyWith(externalChannel: () => 'TWINT');
      expect(copy.externalChannel, 'TWINT');
    });

    test('overrides paidAt', () {
      final p = _payment();
      final newTime = DateTime.utc(2026, 4, 1);
      final copy = p.copyWith(paidAt: newTime);
      expect(copy.paidAt, newTime);
    });
  });

  // =========================================================================
  // PaymentEntity — equality and hashCode
  // =========================================================================
  group('PaymentEntity — equality', () {
    test('two identical payments are equal', () {
      final a = _payment();
      final b = _payment();
      expect(a, equals(b));
    });

    test('different id breaks equality', () {
      final a = _payment(id: 'pay-1');
      final b = _payment(id: 'pay-2');
      expect(a, isNot(equals(b)));
    });

    test('different amount breaks equality', () {
      final a = _payment(amount: 2500);
      final b = _payment(amount: 5000);
      expect(a, isNot(equals(b)));
    });

    test('different paymentMethod breaks equality', () {
      final a = _payment(paymentMethod: PaymentMethod.cash);
      final b = _payment(paymentMethod: PaymentMethod.creditCard);
      expect(a, isNot(equals(b)));
    });

    test('different paidAt breaks equality', () {
      final a = _payment(paidAt: DateTime.utc(2026, 1, 1));
      final b = _payment(paidAt: DateTime.utc(2026, 2, 1));
      expect(a, isNot(equals(b)));
    });

    test('hashCode is consistent with equality', () {
      final a = _payment();
      final b = _payment();
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  // =========================================================================
  // PaymentEntity — toString
  // =========================================================================
  group('PaymentEntity — toString', () {
    test('contains id, method and amount', () {
      final p = _payment(id: 'pay-42', paymentMethod: PaymentMethod.cash, amount: 3000);
      final str = p.toString();
      expect(str, contains('pay-42'));
      expect(str, contains('cash'));
      expect(str, contains('3000'));
    });
  });

  // =========================================================================
  // BillEntity — construction and computed properties
  // =========================================================================
  group('BillEntity — construction', () {
    test('constructs with all required fields', () {
      final bill = _bill();
      expect(bill.id, 'bill-1');
      expect(bill.tenantId, 'tenant-1');
      expect(bill.ticketId, 'ticket-1');
      expect(bill.billNumber, 'REC-0001');
      expect(bill.subtotal, 2313);
      expect(bill.taxAmount, 187);
      expect(bill.discountAmount, 0);
      expect(bill.total, 2500);
      expect(bill.status, BillStatus.open);
      expect(bill.payments, isEmpty);
    });

    test('discountAmount defaults to 0', () {
      final bill = _bill();
      expect(bill.discountAmount, 0);
    });
  });

  // =========================================================================
  // BillEntity — totalPaid, remainingBalance, isFullyPaid
  // =========================================================================
  group('BillEntity — payment aggregates', () {
    test('totalPaid returns 0 with no payments', () {
      final bill = _bill();
      expect(bill.totalPaid, 0);
    });

    test('totalPaid sums all payment amounts', () {
      final bill = _bill(
        total: 5000,
        payments: [
          _payment(id: 'p1', amount: 2000),
          _payment(id: 'p2', amount: 3000),
        ],
      );
      expect(bill.totalPaid, 5000);
    });

    test('remainingBalance equals total when no payments', () {
      final bill = _bill(total: 2500);
      expect(bill.remainingBalance, 2500);
    });

    test('remainingBalance decreases with partial payment', () {
      final bill = _bill(
        total: 5000,
        payments: [_payment(amount: 2000)],
      );
      expect(bill.remainingBalance, 3000);
    });

    test('remainingBalance is 0 when fully paid', () {
      final bill = _bill(
        total: 2500,
        payments: [_payment(amount: 2500)],
      );
      expect(bill.remainingBalance, 0);
    });

    test('remainingBalance goes negative on overpayment', () {
      final bill = _bill(
        total: 2500,
        payments: [_payment(amount: 3000)],
      );
      expect(bill.remainingBalance, -500);
    });

    test('isFullyPaid is false when no payment', () {
      final bill = _bill(total: 2500);
      expect(bill.isFullyPaid, isFalse);
    });

    test('isFullyPaid is false for partial payment', () {
      final bill = _bill(
        total: 2500,
        payments: [_payment(amount: 1000)],
      );
      expect(bill.isFullyPaid, isFalse);
    });

    test('isFullyPaid is true for exact payment', () {
      final bill = _bill(
        total: 2500,
        payments: [_payment(amount: 2500)],
      );
      expect(bill.isFullyPaid, isTrue);
    });

    test('isFullyPaid is true when overpaid', () {
      final bill = _bill(
        total: 2500,
        payments: [_payment(amount: 3000)],
      );
      expect(bill.isFullyPaid, isTrue);
    });

    test('split payment across two methods', () {
      final bill = _bill(
        total: 4800,
        payments: [
          _payment(id: 'p1', amount: 2000, paymentMethod: PaymentMethod.cash),
          _payment(id: 'p2', amount: 2800, paymentMethod: PaymentMethod.creditCard),
        ],
      );
      expect(bill.totalPaid, 4800);
      expect(bill.isFullyPaid, isTrue);
      expect(bill.remainingBalance, 0);
    });

    test('three-way split', () {
      final bill = _bill(
        total: 9000,
        payments: [
          _payment(id: 'p1', amount: 3000),
          _payment(id: 'p2', amount: 3000),
          _payment(id: 'p3', amount: 3000),
        ],
      );
      expect(bill.totalPaid, 9000);
      expect(bill.isFullyPaid, isTrue);
    });
  });

  // =========================================================================
  // BillEntity — copyWith
  // =========================================================================
  group('BillEntity — copyWith', () {
    test('returns identical bill when no overrides', () {
      final bill = _bill();
      final copy = bill.copyWith();
      expect(copy, equals(bill));
    });

    test('overrides status', () {
      final bill = _bill(status: BillStatus.open);
      final copy = bill.copyWith(status: BillStatus.fullyPaid);
      expect(copy.status, BillStatus.fullyPaid);
    });

    test('overrides total', () {
      final bill = _bill(total: 2500);
      final copy = bill.copyWith(total: 3000);
      expect(copy.total, 3000);
    });

    test('overrides payments list', () {
      final bill = _bill();
      final copy = bill.copyWith(payments: [_payment()]);
      expect(copy.payments.length, 1);
    });

    test('overrides discountAmount', () {
      final bill = _bill(discountAmount: 0);
      final copy = bill.copyWith(discountAmount: 500);
      expect(copy.discountAmount, 500);
    });

    test('overrides billNumber', () {
      final bill = _bill(billNumber: 'REC-0001');
      final copy = bill.copyWith(billNumber: 'REC-0042');
      expect(copy.billNumber, 'REC-0042');
    });
  });

  // =========================================================================
  // BillEntity — equality and hashCode
  // =========================================================================
  group('BillEntity — equality', () {
    test('two identical bills are equal', () {
      final a = _bill();
      final b = _bill();
      expect(a, equals(b));
    });

    test('different id breaks equality', () {
      final a = _bill(id: 'bill-1');
      final b = _bill(id: 'bill-2');
      expect(a, isNot(equals(b)));
    });

    test('different total breaks equality', () {
      final a = _bill(total: 2500);
      final b = _bill(total: 5000);
      expect(a, isNot(equals(b)));
    });

    test('different status breaks equality', () {
      final a = _bill(status: BillStatus.open);
      final b = _bill(status: BillStatus.fullyPaid);
      expect(a, isNot(equals(b)));
    });

    test('hashCode is consistent with equality', () {
      final a = _bill();
      final b = _bill();
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  // =========================================================================
  // BillEntity — toString
  // =========================================================================
  group('BillEntity — toString', () {
    test('contains id, billNumber, total and status', () {
      final bill = _bill(id: 'bill-99', billNumber: 'REC-0099', total: 4500);
      final str = bill.toString();
      expect(str, contains('bill-99'));
      expect(str, contains('REC-0099'));
      expect(str, contains('4500'));
    });
  });

  // =========================================================================
  // Receipt generation: Swiss VAT breakdown scenarios
  // =========================================================================
  group('Swiss VAT payment scenarios', () {
    test('cash payment with exact amount — no change', () {
      final p = _payment(
        paymentMethod: PaymentMethod.cash,
        amount: 2500,
        tenderedAmount: 2500,
        changeAmount: 0,
      );
      expect(p.changeAmount, 0);
      expect(p.tenderedAmount, p.amount);
    });

    test('cash payment — customer gives banknote, receives change', () {
      // CHF 25.50 bill, customer pays CHF 30.00, change = CHF 4.50
      final p = _payment(
        paymentMethod: PaymentMethod.cash,
        amount: 2550,
        tenderedAmount: 3000,
        changeAmount: 450,
      );
      expect(p.tenderedAmount - p.amount, p.changeAmount);
    });

    test('card payment — no tendered/change', () {
      final p = _payment(
        paymentMethod: PaymentMethod.creditCard,
        amount: 8150,
        tenderedAmount: 0,
        changeAmount: 0,
        reference: 'TERM-0001-TX-4566',
      );
      expect(p.tenderedAmount, 0);
      expect(p.changeAmount, 0);
      expect(p.reference, 'TERM-0001-TX-4566');
    });

    test('bill with 8.1% VAT (dine-in food)', () {
      // CHF 25.00 inclusive at 8.1%: net = 2313, tax = 187
      final bill = _bill(subtotal: 2313, taxAmount: 187, total: 2500);
      expect(bill.subtotal + bill.taxAmount, bill.total);
    });

    test('bill with 2.6% VAT (takeaway food)', () {
      // CHF 25.00 inclusive at 2.6%: net = 2437, tax = 63
      final bill = _bill(subtotal: 2437, taxAmount: 63, total: 2500);
      expect(bill.subtotal + bill.taxAmount, bill.total);
    });

    test('bill with 3.8% VAT (accommodation)', () {
      // CHF 100.00 inclusive at 3.8%: net = 9634, tax = 366
      final bill = _bill(
        subtotal: 9634,
        taxAmount: 366,
        total: 10000,
        billNumber: 'REC-HOTEL-001',
      );
      expect(bill.subtotal + bill.taxAmount, bill.total);
    });

    test('bill fully paid via two split payments is isFullyPaid', () {
      final bill = _bill(
        total: 5000,
        status: BillStatus.fullyPaid,
        payments: [
          _payment(id: 'p1', amount: 2500, paymentMethod: PaymentMethod.cash),
          _payment(id: 'p2', amount: 2500, paymentMethod: PaymentMethod.debitCard),
        ],
      );
      expect(bill.isFullyPaid, isTrue);
      expect(bill.status, BillStatus.fullyPaid);
    });
  });
}
