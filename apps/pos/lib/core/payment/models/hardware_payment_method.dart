/// Hardware terminal payment methods.
///
/// Distinct from [PaymentMethod] (the domain billing enum).
/// This enum represents what is sent to the physical terminal.
enum HardwarePaymentMethod {
  /// Standard card payment (debit/credit).
  card,

  /// TWINT QR-code payment — CHF only, routed via MyPOS terminal.
  twint,
}
