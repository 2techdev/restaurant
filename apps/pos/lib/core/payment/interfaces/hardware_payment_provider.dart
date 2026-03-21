import '../models/hardware_payment_request.dart';
import '../models/hardware_payment_result.dart';

/// Abstract interface every hardware payment terminal provider must implement.
///
/// Lifecycle:
///   1. Call [initialize] once after construction.
///   2. Call [processPayment] / [refundPayment] / [cancelPayment] as needed.
///   3. Call [dispose] when the provider is no longer needed.
abstract class HardwarePaymentProvider {
  /// Human-readable provider name (e.g. 'Wallee', 'MyPOS').
  String get providerName;

  /// Whether [initialize] has been called and succeeded.
  bool get isInitialized;

  /// Initialise the provider (open connection, load persisted state, etc.).
  ///
  /// Must be called before any payment operation.
  /// Implementations should be idempotent when called more than once.
  Future<void> initialize();

  /// Send a payment request to the terminal.
  ///
  /// Returns a [HardwarePaymentResult] in all cases — never throws.
  /// Check [HardwarePaymentResult.isApproved] for success.
  Future<HardwarePaymentResult> processPayment(HardwarePaymentRequest request);

  /// Refund a previous transaction.
  ///
  /// [transactionId] — original terminal transaction ID.
  /// [amountCents]   — amount to refund in minor units (null = full refund).
  ///
  /// Returns `true` on success, `false` on failure.
  /// Throws [UnsupportedError] if refunds are not supported by this provider.
  Future<bool> refundPayment(String transactionId, {int? amountCents});

  /// Abort an in-progress terminal transaction.
  ///
  /// Returns `true` if the cancel was acknowledged by the terminal.
  Future<bool> cancelPayment();

  /// Perform end-of-day settlement / batch close.
  ///
  /// Returns a map of settlement data (totals, receipt XML, etc.).
  /// Returns an empty map if the operation is not supported.
  Future<Map<String, dynamic>> endOfDay();

  /// Release resources held by this provider.
  Future<void> dispose();
}
