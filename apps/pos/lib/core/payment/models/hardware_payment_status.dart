/// Status of a hardware terminal payment operation.
enum HardwarePaymentStatus {
  /// Authorised by the card scheme / payment network.
  approved,

  /// Declined by the card scheme or issuer.
  declined,

  /// Cancelled by operator or customer at the terminal.
  cancelled,

  /// Technical failure (timeout, connection error, etc.).
  failed,
}
