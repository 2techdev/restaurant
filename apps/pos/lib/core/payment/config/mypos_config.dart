/// Configuration for the MyPOS Sigma terminal over WiFi (TCP/IP).
///
/// Only TCP/IP (WiFi) connectivity is supported — USB and Bluetooth are
/// explicitly excluded from the GastroCore POS integration.
class MyPosConfig {
  const MyPosConfig({
    required this.terminalIp,
    this.terminalPort = 60180,
    this.currency = 'CHF',
  });

  /// IP address of the MyPOS terminal on the local network.
  final String terminalIp;

  /// TCP port for MyPOS SlaveSDK communication (default: 60180).
  final int terminalPort;

  /// Default currency code for card payments.
  /// TWINT is always CHF regardless of this setting.
  final String currency;

  @override
  String toString() =>
      'MyPosConfig(ip: $terminalIp, port: $terminalPort, currency: $currency)';
}
