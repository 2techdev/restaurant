import 'hardware_payment_method.dart';

/// Request sent to a hardware payment terminal.
///
/// [amount] is always in major currency units (e.g. 12.50 CHF).
/// Providers convert to minor units internally before sending to the terminal.
class HardwarePaymentRequest {
  const HardwarePaymentRequest({
    required this.reference,
    required this.amount,
    required this.currency,
    this.paymentMethod = HardwarePaymentMethod.card,
  });

  /// Merchant-side reference (ticket or bill ID used for receipt/reconciliation).
  final String reference;

  /// Amount in major currency units (e.g. 12.50 for CHF 12.50).
  final double amount;

  /// ISO 4217 currency code (e.g. 'CHF', 'EUR').
  final String currency;

  /// Terminal operation to perform.
  final HardwarePaymentMethod paymentMethod;

  /// Amount converted to minor units (cents) for terminal communication.
  int get amountMinorUnits => (amount * 100).round();

  @override
  String toString() =>
      'HardwarePaymentRequest(ref: $reference, amount: $amount $currency, method: ${paymentMethod.name})';
}
