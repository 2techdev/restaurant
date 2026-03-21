/// Configuration for the Wallee LTI payment terminal.
///
/// Terminal acts as TCP server on [ltiPort] (default 50000).
/// The client (this app) initiates the connection for each transaction.
class WalleeConfig {
  const WalleeConfig({
    required this.terminalIp,
    required this.posId,
    this.ltiPort = 50000,
    this.transactionTimeoutSeconds = 180,
  });

  /// IP address of the Wallee terminal on the local network.
  final String terminalIp;

  /// POS identifier sent in every LTI request (configured in terminal settings).
  final String posId;

  /// TCP port for LTI communication (default: 50000).
  final int ltiPort;

  /// How long to wait for a terminal response before timing out.
  /// Should be ≥ gateway timeout to ensure we always receive a proper response.
  /// Default: 180 seconds (allows for customer PIN entry etc.).
  final int transactionTimeoutSeconds;

  @override
  String toString() =>
      'WalleeConfig(ip: $terminalIp, port: $ltiPort, posId: $posId)';
}
