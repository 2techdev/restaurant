/// Centralised cloud endpoint configuration for the POS app.
///
/// All production hosts default to the Hetzner pilot deployment
/// (api.2hub.ch / ws.2hub.ch). Override per-build via `--dart-define`:
///
/// ```bash
/// flutter build apk --flavor pos --release \
///     --dart-define=API_HOST=api.example.com \
///     --dart-define=WS_HOST=ws.example.com
/// ```
///
/// Every HTTP and WebSocket call that targets a GastroCore backend should
/// use [apiBaseUrl] or [wsBaseUrl] rather than hard-coding a URL. This lets
/// staging, dev, and self-hosted deployments point the whole app at a
/// different cluster with a single flag.
library;

class AppEndpoints {
  const AppEndpoints._();

  /// Hostname for the REST API. Default: `api.2hub.ch` (Hetzner pilot).
  static const String apiHost = String.fromEnvironment(
    'API_HOST',
    defaultValue: 'api.2hub.ch',
  );

  /// Hostname for the WebSocket hub. Default: `ws.2hub.ch` (Hetzner pilot).
  static const String wsHost = String.fromEnvironment(
    'WS_HOST',
    defaultValue: 'ws.2hub.ch',
  );

  /// Full HTTPS base URL for REST calls (no trailing slash).
  static String get apiBaseUrl => 'https://$apiHost';

  /// Full WSS base URL for WebSocket connections (no trailing slash).
  static String get wsBaseUrl => 'wss://$wsHost';
}
