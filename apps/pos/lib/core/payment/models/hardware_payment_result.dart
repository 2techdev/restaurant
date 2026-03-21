import 'hardware_payment_status.dart';

/// Result returned by a hardware payment terminal after a transaction attempt.
class HardwarePaymentResult {
  const HardwarePaymentResult({
    required this.transactionId,
    required this.status,
    required this.amount,
    required this.currency,
    this.errorMessage,
    this.authCode,
    this.cardNumber,
    this.cardType,
    this.entryMethod,
    this.terminalId,
    this.rawResponse,
  });

  /// Terminal-assigned transaction identifier.
  final String transactionId;

  final HardwarePaymentStatus status;

  /// Amount in major currency units.
  final double amount;

  final String currency;

  /// Human-readable error description when [status] is not [HardwarePaymentStatus.approved].
  final String? errorMessage;

  // ── Receipt fields (EP2 / LTI data) ──────────────────────────────────────

  /// Authorisation code from card scheme (e.g. "123456").
  final String? authCode;

  /// Masked PAN (e.g. "411111******1111").
  final String? cardNumber;

  /// Card brand label (e.g. "Mastercard", "Visa", "TWINT").
  final String? cardType;

  /// Entry method (e.g. "CHIP", "CTLS", "MSR").
  final String? entryMethod;

  /// Terminal identifier from the payment device.
  final String? terminalId;

  /// Full raw response payload for debugging / receipt storage.
  final Map<String, dynamic>? rawResponse;

  // ── Convenience getters ───────────────────────────────────────────────────

  bool get isApproved => status == HardwarePaymentStatus.approved;
  bool get isDeclined => status == HardwarePaymentStatus.declined;
  bool get isFailed => status == HardwarePaymentStatus.failed;
  bool get isCancelled => status == HardwarePaymentStatus.cancelled;

  /// Shorthand for creating a failed/error result without a terminal response.
  factory HardwarePaymentResult.error({
    required String transactionId,
    required double amount,
    required String currency,
    required String message,
    HardwarePaymentStatus status = HardwarePaymentStatus.failed,
  }) {
    return HardwarePaymentResult(
      transactionId: transactionId,
      status: status,
      amount: amount,
      currency: currency,
      errorMessage: message,
    );
  }

  @override
  String toString() =>
      'HardwarePaymentResult(id: $transactionId, status: ${status.name}, amount: $amount $currency)';
}
