import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/payments/domain/entities/payment_entity.dart';
import 'package:gastrocore_pos/features/payments/domain/mixed_tender_calculator.dart';

void main() {
  group('MixedTenderCalculator', () {
    test('empty calculator — nothing paid, full balance outstanding', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      expect(calc.paidCents, 0);
      expect(calc.outstandingCents, 5000);
      expect(calc.changeCents, 0);
      expect(calc.isFullyPaid, isFalse);
      expect(calc.hasTenders, isFalse);
    });

    test('single exact tender closes the bill', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      final r = calc.addTender(
        method: PaymentMethod.creditCard,
        amountCents: 5000,
      );
      expect(r.isSuccess, isTrue);
      final next = r.calculator!;
      expect(next.outstandingCents, 0);
      expect(next.isFullyPaid, isTrue);
      expect(next.changeCents, 0);
    });

    test('partial card tender reduces the outstanding balance', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      final next = calc
          .addTender(method: PaymentMethod.creditCard, amountCents: 3000)
          .calculator!;
      expect(next.paidCents, 3000);
      expect(next.outstandingCents, 2000);
      expect(next.isFullyPaid, isFalse);
    });

    test('mixed tender: card then cash covers grand total', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      final afterCard = calc
          .addTender(method: PaymentMethod.creditCard, amountCents: 3000)
          .calculator!;
      final afterCash = afterCard
          .addTender(method: PaymentMethod.cash, amountCents: 2000)
          .calculator!;
      expect(afterCash.paidCents, 5000);
      expect(afterCash.outstandingCents, 0);
      expect(afterCash.isFullyPaid, isTrue);
      expect(afterCash.changeCents, 0);
      expect(afterCash.tenders.length, 2);
    });

    test('cash over-tender produces change on the last row', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      final afterCard = calc
          .addTender(method: PaymentMethod.creditCard, amountCents: 3000)
          .calculator!;
      final afterCash = afterCard
          .addTender(method: PaymentMethod.cash, amountCents: 5000)
          .calculator!;
      expect(afterCash.isFullyPaid, isTrue);
      // Raw handed over 3000 + 5000 = 8000; bill 5000 → 3000 change.
      expect(afterCash.changeCents, 3000);
      // paidCents caps at grandTotal so reports aren't inflated.
      expect(afterCash.paidCents, 5000);
    });

    test('non-cash over-pay is rejected', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      final r = calc.addTender(
        method: PaymentMethod.creditCard,
        amountCents: 7000,
      );
      expect(r.isSuccess, isFalse);
      expect(r.error, AddTenderError.overPayNonCash);
    });

    test('cash over-pay is allowed (change), even as first tender', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      final r = calc.addTender(
        method: PaymentMethod.cash,
        amountCents: 10000,
      );
      expect(r.isSuccess, isTrue);
      expect(r.calculator!.isFullyPaid, isTrue);
      expect(r.calculator!.changeCents, 5000);
    });

    test('zero or negative tender rejected', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      expect(
        calc.addTender(method: PaymentMethod.cash, amountCents: 0).error,
        AddTenderError.nonPositive,
      );
      expect(
        calc.addTender(method: PaymentMethod.cash, amountCents: -100).error,
        AddTenderError.nonPositive,
      );
    });

    test('cannot add tender to fully paid bill', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      final paid = calc
          .addTender(method: PaymentMethod.cash, amountCents: 5000)
          .calculator!;
      final r = paid.addTender(
        method: PaymentMethod.creditCard,
        amountCents: 100,
      );
      expect(r.isSuccess, isFalse);
      expect(r.error, AddTenderError.alreadyFullyPaid);
    });

    test('removeTenderAt out-of-range returns identical calculator', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      final next = calc.removeTenderAt(5);
      expect(identical(next, calc), isTrue);
    });

    test('removeTenderAt drops the entry and reopens balance', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      final withTwo = calc
          .addTender(method: PaymentMethod.creditCard, amountCents: 3000)
          .calculator!
          .addTender(method: PaymentMethod.cash, amountCents: 2000)
          .calculator!;
      expect(withTwo.isFullyPaid, isTrue);

      final withOne = withTwo.removeTenderAt(0);
      expect(withOne.tenders.length, 1);
      expect(withOne.outstandingCents, 3000);
      expect(withOne.isFullyPaid, isFalse);
      expect(withOne.tenders.first.method, PaymentMethod.cash);
    });

    test('clear() resets tenders', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      final withTender = calc
          .addTender(method: PaymentMethod.cash, amountCents: 2000)
          .calculator!;
      final cleared = withTender.clear();
      expect(cleared.tenders, isEmpty);
      expect(cleared.outstandingCents, 5000);
    });

    test('withGrandTotal preserves tenders but recomputes balance', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      final withCash = calc
          .addTender(method: PaymentMethod.cash, amountCents: 2000)
          .calculator!;
      // Tip of 500 cents added to grand total.
      final updated = withCash.withGrandTotal(5500);
      expect(updated.tenders.length, 1);
      expect(updated.outstandingCents, 3500);
    });

    test('change stays zero when the final tender is non-cash', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      // Cash first (with over-tender amount), then card exact — final
      // tender is card, so no change on this snapshot.
      final afterCash = calc
          .addTender(method: PaymentMethod.cash, amountCents: 2000)
          .calculator!;
      final afterCard = afterCash
          .addTender(method: PaymentMethod.creditCard, amountCents: 3000)
          .calculator!;
      expect(afterCard.isFullyPaid, isTrue);
      expect(afterCard.changeCents, 0);
    });

    test('voucher tender carries its reference through', () {
      const calc = MixedTenderCalculator(grandTotalCents: 5000);
      final next = calc
          .addTender(
            method: PaymentMethod.other,
            amountCents: 1000,
            reference: 'VOUCHER:ABC123',
          )
          .calculator!;
      expect(next.tenders.first.reference, 'VOUCHER:ABC123');
    });

    test('zero grand total never reports fully paid', () {
      // Guard rail: a zero-total bill should not be auto-closed by the
      // calculator; UI is expected to disable pay when total is 0.
      const calc = MixedTenderCalculator(grandTotalCents: 0);
      expect(calc.isFullyPaid, isFalse);
    });
  });
}
