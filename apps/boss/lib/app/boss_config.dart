/// Static configuration for the Boss app.
library;

class BossConfig {
  static const String defaultApiBaseUrl =
      String.fromEnvironment('BOSS_API_BASE_URL', defaultValue: 'https://api.2hub.ch');

  static const String defaultTenantId =
      String.fromEnvironment('BOSS_TENANT_ID', defaultValue: 'demo');

  static const Duration sessionPollInterval = Duration(seconds: 30);
}
