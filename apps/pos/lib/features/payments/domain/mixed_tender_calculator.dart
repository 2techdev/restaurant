/// Pure calculator for mixed-tender payments.
///
/// A single bill can be settled with several payment methods (e.g. CHF 50
/// cash + the rest card). This class tracks the running balance without
/// touching the database, so it can be reused across the UI and tests.
///
/// Rules:
///   * Non-cash tenders (card, TWINT, voucher) must not exceed the
///     outstanding balance — you can't "over-pay" on a card.
///   * Cash tenders MAY exceed the outstanding balance; the surplus
///     becomes change (Rückgeld) on the final row.
///   * The bill is fully paid when `outstanding == 0`.
library;

import 'package:gastrocore_pos/features/payments/domain/entities/payment_entity.dart';

/// One tender row (method + amount in cents). Immutable by design; the
/// calculator produces new instances rather than mutating.
class TenderEntry {
  const TenderEntry({
    required this.method,
    required this.amountCents,
    this.reference,
  });

  final PaymentMethod method;

  /// Amount applied against the bill, in cents. Always >= 0. For cash this
  /// is the amount the customer handed over (tenderedAmount); change is
  /// calculated separately by the calculator.
  final int amountCents;

  /// Optional external reference (voucher code, TWINT marker, …).
  final String? reference;

  TenderEntry copyWith({
    PaymentMethod? method,
    int? amountCents,
    String? Function()? reference,
  }) {
    return TenderEntry(
      method: method ?? this.method,
      amountCents: amountCents ?? this.amountCents,
      reference: reference != null ? reference() : this.reference,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TenderEntry &&
          runtimeType == other.runtimeType &&
          method == other.method &&
          amountCents == other.amountCents &&
          reference == other.reference;

  @override
  int get hashCode => Object.hash(method, amountCents, reference);

  @override
  String toString() =>
      'TenderEntry(${method.name}: $amountCents¢${reference == null ? "" : " ref=$reference"})';
}

/// Outcome of attempting to add a tender. The UI uses this to show a
/// descriptive error instead of silently ignoring the tap.
enum AddTenderError {
  /// Tender amount was 0 or negative.
  nonPositive,

  /// Non-cash tender exceeds the outstanding balance.
  overPayNonCash,

  /// Bill already fully paid; no more tenders accepted.
  alreadyFullyPaid,
}

class AddTenderResult {
  const AddTenderResult.success(this.calculator) : error = null;
  const AddTenderResult.failure(this.error) : calculator = null;

  final MixedTenderCalculator? calculator;
  final AddTenderError? error;

  bool get isSuccess => error == null;
}

/// Immutable snapshot of a mixed-tender payment-in-progress.
class MixedTenderCalculator {
  const MixedTenderCalculator({
    required this.grandTotalCents,
    this.tenders = const [],
  });

  /// Grand total the bill has to reach. Constant for the lifetime of a
  /// payment session; rebuild the calculator if tip/voucher/loyalty
  /// changes.
  final int grandTotalCents;

  /// Tenders added so far, in insertion order.
  final List<TenderEntry> tenders;

  /// Total paid so far (sum of tender amounts, capped at grandTotal so
  /// cash over-payment doesn't skew the "paid" column).
  int get paidCents {
    int sum = 0;
    for (final t in tenders) {
      sum += t.amountCents;
    }
    return sum > grandTotalCents ? grandTotalCents : sum;
  }

  /// What's still owed. Never negative.
  int get outstandingCents {
    final raw = grandTotalCents - _rawPaid();
    return raw < 0 ? 0 : raw;
  }

  /// Change to give back. Only non-zero when the *last* tender was cash
  /// and the raw paid total exceeds the grand total.
  int get changeCents {
    if (tenders.isEmpty) return 0;
    final last = tenders.last;
    if (last.method != PaymentMethod.cash) return 0;
    final overshoot = _rawPaid() - grandTotalCents;
    return overshoot > 0 ? overshoot : 0;
  }

  bool get isFullyPaid =>
      grandTotalCents > 0 && _rawPaid() >= grandTotalCents;

  bool get hasTenders => tenders.isNotEmpty;

  /// Try to add a tender. Returns the new calculator on success, or an
  /// error code the UI can turn into a localised message.
  AddTenderResult addTender({
    required PaymentMethod method,
    required int amountCents,
    String? reference,
  }) {
    if (amountCents <= 0) {
      return const AddTenderResult.failure(AddTenderError.nonPositive);
    }
    if (isFullyPaid) {
      return const AddTenderResult.failure(AddTenderError.alreadyFullyPaid);
    }
    if (method != PaymentMethod.cash && amountCents > outstandingCents) {
      return const AddTenderResult.failure(AddTenderError.overPayNonCash);
    }
    final next = List<TenderEntry>.from(tenders)
      ..add(TenderEntry(
        method: method,
        amountCents: amountCents,
        reference: reference,
      ));
    return AddTenderResult.success(
      MixedTenderCalculator(
        grandTotalCents: grandTotalCents,
        tenders: List.unmodifiable(next),
      ),
    );
  }

  /// Remove the tender at [index]. Returns an unchanged calculator if the
  /// index is out of range so callers don't have to guard.
  MixedTenderCalculator removeTenderAt(int index) {
    if (index < 0 || index >= tenders.length) return this;
    final next = List<TenderEntry>.from(tenders)..removeAt(index);
    return MixedTenderCalculator(
      grandTotalCents: grandTotalCents,
      tenders: List.unmodifiable(next),
    );
  }

  MixedTenderCalculator clear() {
    return MixedTenderCalculator(grandTotalCents: grandTotalCents);
  }

  /// Rebuild with a different grand total. Keeps existing tenders so the
  /// UI can react to a tip change without losing earlier entries; call
  /// `clear()` first if you want a fresh start.
  MixedTenderCalculator withGrandTotal(int newGrandTotalCents) {
    return MixedTenderCalculator(
      grandTotalCents: newGrandTotalCents,
      tenders: tenders,
    );
  }

  int _rawPaid() {
    int sum = 0;
    for (final t in tenders) {
      sum += t.amountCents;
    }
    return sum;
  }
}
